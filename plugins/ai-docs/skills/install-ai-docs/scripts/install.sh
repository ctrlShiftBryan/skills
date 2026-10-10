#!/usr/bin/env bash
# Install the ai-docs knowledge base into a GitHub repo. Idempotent: re-running updates the
# vendored skill and instruction sections in place and keeps .ai-docs.json settings.
#
# Usage: install.sh [--target DIR] [--branch NAME] [--repo OWNER/NAME] [--pages auto|on|off]
#                   [--allow-path PATH ...] [--no-github] [--dry-run]
#
#   --target DIR       repo to install into (default: current directory)
#   --branch NAME      knowledge-base branch (default: ai-docs, or the one in .ai-docs.json)
#   --repo OWNER/NAME  GitHub repo (default: .ai-docs.json, else parsed from origin, else gh)
#   --pages MODE       auto (default): enable Pages unless the site would be public on a
#                      private repo, then stop with exit code 3 for the user to decide;
#                      on: enable even if the site would be public; off: leave Pages alone
#   --allow-path PATH  add a path where .md/.html may live on code branches (repeatable;
#                      a trailing / makes it a prefix)
#   --no-github        skip every GitHub API call (no Pages, no ruleset)
#   --dry-run          report what would change; write nothing locally or remotely
#
# Exit codes: 0 done, 1 error, 3 Pages decision needed (nothing was changed).
# Requires git and node; gh (authenticated) unless --no-github.

# BRANCH, REPO, PAGES_URL and PUBLISH_CMD are assigned by eval from install-helper.mjs.
# shellcheck disable=SC2153
set -uo pipefail

target="$PWD" branch="" repo="" pages_mode="auto" no_github=0 dry_run=0
allow_args=()
while (($#)); do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --pages) pages_mode="$2"; shift 2 ;;
    --allow-path) allow_args+=(--allow-path "$2"); shift 2 ;;
    --no-github) no_github=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
case "$pages_mode" in auto|on|off) ;; *) echo "--pages must be auto, on or off" >&2; exit 1 ;; esac

skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assets="$skill_root/assets"
helper="$skill_root/scripts/install-helper.mjs"
RULESET_NAME="ai-docs protection"

die() { echo "✗ $*" >&2; exit 1; }
warn() { echo "  ⚠ $*"; }

# --- preflight ------------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git not found"
command -v node >/dev/null 2>&1 || die "node not found (the ai-docs publish script needs it)"
[[ -d "$target" ]] || die "target is not a directory: $target"
cd "$target" || die "cannot cd to $target"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository: $target"
root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
git rev-parse -q --verify HEAD >/dev/null || die "repo has no commits yet; commit something first"
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote"

if ((!no_github)); then
  command -v gh >/dev/null 2>&1 || die "gh CLI not found (install it, or pass --no-github)"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
fi

# Sets BRANCH, REPO, PAGES_URL (from an existing .ai-docs.json) and PUBLISH_CMD.
resolved="$(node "$helper" resolve --root "$root" ${branch:+--branch "$branch"} ${repo:+--repo "$repo"})" \
  || die "could not read the existing config"
eval "$resolved"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch name: $BRANCH"
if [[ -z "$REPO" ]]; then
  REPO="$(git remote get-url origin | sed -nE 's#^(https://|ssh://)?([^@/]+@)?github\.com[:/]([^/]+/[^/]+)$#\3#p' | sed 's/\.git$//')"
fi
if [[ -z "$REPO" ]] && ((!no_github)); then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi
[[ -z "$REPO" || "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid repo slug: $REPO"
((no_github)) || [[ -n "$REPO" ]] || die "cannot work out the GitHub repo; pass --repo OWNER/NAME"

# jget JSON PATH — print a dotted field from a JSON string (empty when missing or not JSON).
jget() {
  node -e 'try { let v = JSON.parse(process.argv[1]);
    for (const k of process.argv[2].split(".").filter(Boolean)) v = v == null ? undefined : v[k];
    process.stdout.write(v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v)); } catch {}' "$1" "$2"
}
# api ARGS... — gh api; the response body (or error body) lands in $api_out, returns gh's status.
api() { api_out="$(gh api "$@" 2>&1)"; }

# --- GitHub facts ---------------------------------------------------------------------------
visibility="" is_admin="" private_pages_ok=0 pages_json="" pages_branch="" rulesets_json=""
ruleset_id="" rulesets_supported="unknown"
if ((!no_github)); then
  api "repos/$REPO" || die "cannot read repos/$REPO: $api_out"
  repo_json="$api_out"
  visibility="$(jget "$repo_json" visibility)"
  is_admin="$(jget "$repo_json" permissions.admin)"
  owner_type="$(jget "$repo_json" owner.type)"
  [[ "$(jget "$repo_json" permissions.push)" == "true" ]] || die "you need push access to $REPO"
  # Access-controlled (non-public) Pages exist only for org repos on GitHub Enterprise Cloud.
  if [[ "$visibility" == "internal" ]]; then
    private_pages_ok=1
  elif [[ "$owner_type" == "Organization" ]] && api "orgs/${REPO%%/*}" \
      && [[ "$(jget "$api_out" plan.name)" == "enterprise" ]]; then
    private_pages_ok=1
  fi
  if api "repos/$REPO/pages"; then
    pages_json="$api_out"
    pages_branch="$(jget "$pages_json" source.branch)"
  fi
  if api "repos/$REPO/rulesets"; then
    rulesets_supported="yes"
    rulesets_json="$api_out"
    ruleset_id="$(node -e 'try { const r = JSON.parse(process.argv[1]).find((x) => x.name === process.argv[2]);
      process.stdout.write(r ? String(r.id) : ""); } catch {}' "$rulesets_json" "$RULESET_NAME")"
  elif [[ "$api_out" == *"Upgrade to GitHub"* || "$api_out" == *"HTTP 403"* ]]; then
    rulesets_supported="no"
  fi
fi

branch_exists=0
git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && branch_exists=1

# --- decide Pages -----------------------------------------------------------------------------
# pages_action: none | adopt | create-public | create-private | decide
pages_action="none" pages_reason=""
if ((no_github)); then
  pages_reason="--no-github"
elif [[ "$pages_mode" == "off" ]]; then
  pages_reason="--pages off"
elif [[ -n "$pages_json" ]]; then
  if [[ "$pages_branch" == "$BRANCH" ]]; then
    pages_action="adopt"
  else
    pages_reason="Pages already serves branch '${pages_branch:-?}'; leaving it alone"
  fi
elif [[ "$is_admin" != "true" ]]; then
  pages_reason="enabling Pages needs repo admin"
elif [[ "$visibility" == "public" ]]; then
  pages_action="create-public"
elif ((private_pages_ok)); then
  pages_action="create-private"
elif [[ "$pages_mode" == "on" ]]; then
  pages_action="create-public"
else
  pages_action="decide"
fi

world_readable=0
[[ "$visibility" == "public" ]] && world_readable=1
[[ "$pages_action" == "create-public" ]] && world_readable=1
[[ "$pages_action" == "adopt" && "$(jget "$pages_json" public)" == "true" ]] && world_readable=1

# The Pages URL recorded in .ai-docs.json. When this run doesn't look at Pages (--no-github,
# --pages off), keep whatever the config already had.
pages_url="$PAGES_URL"
case "$pages_action" in
  adopt) pages_url="$(jget "$pages_json" html_url)" ;;
  none) [[ "$pages_reason" == "--no-github" || "$pages_reason" == "--pages off" ]] || pages_url="" ;;
  *) pages_url="" ;;
esac
apply_files() {
  node "$helper" apply --root "$root" --assets "$assets" --branch "$BRANCH" --repo "$REPO" \
    --pages-url "$pages_url" --world-readable "$world_readable" ${allow_args[@]+"${allow_args[@]}"} "$@"
}

# --- plan ------------------------------------------------------------------------------------
echo "→ ai-docs install plan for ${REPO:-<no GitHub repo>} ($root)"
echo "  branch       $BRANCH ($( ((branch_exists)) && echo "exists on origin; adopt it" || echo "create as an orphan branch and push"))"
case "$pages_action" in
  adopt) echo "  pages        adopt existing site $(jget "$pages_json" html_url) (public=$(jget "$pages_json" public))" ;;
  create-public) echo "  pages        enable from $BRANCH — the site will be PUBLIC on the internet" ;;
  create-private) echo "  pages        enable from $BRANCH, restricted to people with repo access" ;;
  decide) echo "  pages        DECISION NEEDED: $REPO is $visibility, and a Pages site here would be public on the internet" ;;
  none) echo "  pages        skip ($pages_reason)" ;;
esac
if ((no_github)); then
  echo "  ruleset      skip (--no-github)"
elif [[ "$is_admin" != "true" ]]; then
  echo "  ruleset      skip (needs repo admin)"
elif [[ "$rulesets_supported" == "no" ]]; then
  echo "  ruleset      skip (this repo's plan has no rulesets)"
else
  echo "  ruleset      '$RULESET_NAME' on $BRANCH: block deletion + force-push, admins bypass ($([[ -n "$ruleset_id" ]] && echo "update #$ruleset_id" || echo create))"
fi
echo "  publish cmd  $PUBLISH_CMD"
echo "  files"
apply_files --dry-run || die "file plan failed"
echo
node "$helper" scan --root "$root" ${allow_args[@]+"${allow_args[@]}"}

if [[ "$pages_action" == "decide" ]]; then
  echo
  echo "Pages decision needed: re-run with --pages on (public site) or --pages off (no Pages; links go to GitHub)."
  ((dry_run)) && exit 0
  exit 3
fi
if ((dry_run)); then
  echo
  echo "Dry run: nothing was changed."
  exit 0
fi

# --- 1. bootstrap the branch ------------------------------------------------------------------
echo
echo "→ applying"
if ((!branch_exists)); then
  wt="$(mktemp -d)" cfg="$(mktemp)"
  printf '{"branch":"%s","repo":"%s"}\n' "$BRANCH" "$REPO" > "$cfg"
  git worktree add -q --detach "$wt" >/dev/null 2>&1 || die "could not create a worktree to bootstrap $BRANCH"
  (
    set -e
    cd "$wt"
    git checkout -q --orphan "$BRANCH"
    git rm -rqf . >/dev/null 2>&1 || true
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    : > .nojekyll
    AI_DOCS_CONFIG="$cfg" node "$assets/ai-docs/scripts/ai-docs.mjs" index "$wt" 2>/dev/null
    git add -A
    git config user.name >/dev/null 2>&1 || export GIT_AUTHOR_NAME="ai-docs installer" GIT_COMMITTER_NAME="ai-docs installer" \
      GIT_AUTHOR_EMAIL="ai-docs@users.noreply.github.com" GIT_COMMITTER_EMAIL="ai-docs@users.noreply.github.com"
    git commit -q -m "chore(ai-docs): bootstrap knowledge-base branch"
    git push -q origin "HEAD:refs/heads/$BRANCH"
  )
  rc=$?
  git worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$wt" "$cfg"
  ((rc == 0)) || die "bootstrap of '$BRANCH' failed"
  echo "  created orphan branch '$BRANCH' on origin"
else
  echo "  adopted existing branch '$BRANCH'"
fi

# --- 2. Pages ---------------------------------------------------------------------------------
case "$pages_action" in
  create-public|create-private)
    body="$(printf '{"source":{"branch":"%s","path":"/"},"build_type":"legacy"}' "$BRANCH")"
    if api -X POST "repos/$REPO/pages" --input - <<<"$body"; then
      if [[ "$pages_action" == "create-private" ]]; then
        api -X PUT "repos/$REPO/pages" --input - <<<'{"public":false}' || true
      fi
      for _ in 1 2 3 4 5 6 7 8; do
        api "repos/$REPO/pages" && pages_url="$(jget "$api_out" html_url)"
        [[ -n "$pages_url" ]] && break
        sleep 3
      done
      if [[ "$pages_action" == "create-private" && "$(jget "$api_out" public)" != "false" ]]; then
        api -X DELETE "repos/$REPO/pages" || true
        warn "could not restrict Pages to repo members, so it was turned off again; links go to GitHub"
        pages_url="" world_readable=0
        [[ "$visibility" == "public" ]] && world_readable=1
      else
        echo "  enabled Pages: ${pages_url:-<url pending; re-run the installer to record it>}"
      fi
    else
      warn "could not enable Pages: $api_out"
      [[ "$pages_action" == "create-public" && "$visibility" != "public" ]] && world_readable=0
    fi
    ;;
esac

# --- 3. ruleset -------------------------------------------------------------------------------
if ((!no_github)) && [[ "$is_admin" == "true" && "$rulesets_supported" != "no" ]]; then
  rbody="$(printf '{"name":"%s","target":"branch","enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}],"conditions":{"ref_name":{"include":["refs/heads/%s"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}' "$RULESET_NAME" "$BRANCH")"
  if [[ -n "$ruleset_id" ]]; then
    api -X PUT "repos/$REPO/rulesets/$ruleset_id" --input - <<<"$rbody"; rc=$?
  else
    api -X POST "repos/$REPO/rulesets" --input - <<<"$rbody"; rc=$?
  fi
  if ((rc == 0)); then
    echo "  ruleset '$RULESET_NAME' protects $BRANCH (no deletion, no force-push; admins bypass)"
  else
    warn "ruleset skipped: $(printf '%s' "$api_out" | head -1)"
  fi
fi

# --- 4. files ---------------------------------------------------------------------------------
apply_files || die "writing files failed"

cat <<NEXT

✓ ai-docs installed.

next steps:
  1. review and commit the changes above (the installer leaves them uncommitted).
  2. agents now publish generated docs with:  $PUBLISH_CMD ai-docs/<type>/<YYYY-MM-DD-slug>.<html|md>
NEXT
[[ -n "$pages_url" ]] && echo "  3. knowledge-base index: ${pages_url%/}/ (live 1-2 min after each publish)"
exit 0
