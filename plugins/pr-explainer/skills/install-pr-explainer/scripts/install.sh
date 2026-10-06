#!/usr/bin/env bash
# Install the PR-explainer GitHub Action into a repo. Idempotent — re-running is
# safe. Turnkey by default: copies the workflow + scripts + docs, bootstraps the
# orphan docs branch, enables GitHub Pages, and fills in the repo-specific config.
#
# Usage: install.sh [--target DIR] [--base NAME] [--ai-branch NAME]
#                   [--explainer-dir NAME] [--publish-cmd CMD]
#                   [--no-bootstrap] [--no-pages] [--force]
#
# Self-contained: the bundled asset templates live next to this script (../assets).
#
# Requires: git, and (for the turnkey Pages/branch steps) the `gh` CLI,
# authenticated, with a GitHub `origin` remote you can push to.

set -uo pipefail

target="$PWD"
base=""               # default: the repo's default branch
ai_branch="ai-docs"
explainer_dir="html-explainers"
publish_cmd=""        # default: auto-detect from the package manager
do_bootstrap=1
do_pages=1
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        target="$2";        shift 2 ;;
    --base)          base="$2";          shift 2 ;;
    --ai-branch)     ai_branch="$2";     shift 2 ;;
    --explainer-dir) explainer_dir="$2"; shift 2 ;;
    --publish-cmd)   publish_cmd="$2";   shift 2 ;;
    --no-bootstrap)  do_bootstrap=0;     shift ;;
    --no-pages)      do_pages=0;         shift ;;
    --force)         force=1;            shift ;;
    -h|--help)       sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve bundled assets relative to THIS script (../assets).
skill_root="$(cd "$(dirname "$0")/.." && pwd)"
assets="$skill_root/assets"

[[ -d "$target" ]] || { echo "target not a directory: $target" >&2; exit 1; }
[[ -f "$assets/.github/workflows/pr-explainer.yml" ]] \
  || { echo "missing bundled assets at $assets (skill not self-contained?)" >&2; exit 1; }

cd "$target"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "not a git repository: $target" >&2; exit 1; }

have_gh=0
command -v gh >/dev/null 2>&1 && have_gh=1

# --- discover repo facts ----------------------------------------------------
repo=""
if [[ $have_gh -eq 1 ]]; then
  repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi

if [[ -z "$base" ]]; then
  if [[ $have_gh -eq 1 ]]; then
    base="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  fi
  [[ -z "$base" || "$base" == "null" ]] && \
    base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [[ -z "$base" ]] && base="main"
fi

if [[ -z "$publish_cmd" ]]; then
  if [[ -f package.json ]]; then
    if   [[ -f pnpm-lock.yaml ]];            then publish_cmd="pnpm explainer:publish"
    elif [[ -f yarn.lock ]];                 then publish_cmd="yarn explainer:publish"
    elif [[ -f bun.lockb || -f bun.lock ]];  then publish_cmd="bun run explainer:publish"
    else                                          publish_cmd="npm run explainer:publish"
    fi
  else
    publish_cmd="bash scripts/explainer-publish.sh"
  fi
fi

echo "→ installing pr-explainer into $target"
echo "  repo=${repo:-<unknown>}  base=$base  ai-branch=$ai_branch"
echo "  explainer-dir=$explainer_dir  publish-cmd='$publish_cmd'"

# --- helpers ----------------------------------------------------------------
copy() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && $force -eq 0 ]]; then
    echo "  skip  $dst (exists; use --force to overwrite)"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  wrote $dst"
  fi
}

# subst FILE TOKEN VALUE — replace every TOKEN with VALUE in place. No-op if the
# token is absent, so it's safe to run on already-installed files.
subst() {
  local file="$1" token="$2" value="$3" esc
  [[ -f "$file" ]] || return 0
  esc="$(printf '%s' "$value" | sed -e 's/[&|]/\\&/g')"
  sed -i.bak "s|$token|$esc|g" "$file" && rm -f "$file.bak"
}

# --- 1. copy the action files -----------------------------------------------
copy "$assets/.github/workflows/pr-explainer.yml" ".github/workflows/pr-explainer.yml"
copy "$assets/.github/scripts/pr-explainer-check.sh" ".github/scripts/pr-explainer-check.sh"
copy "$assets/.github/prompts/explainer-generation.md" ".github/prompts/explainer-generation.md"
copy "$assets/scripts/explainer-publish.sh" "scripts/explainer-publish.sh"
copy "$assets/docs/pr-explainer.md" "docs/pr-explainer.md"
chmod +x .github/scripts/pr-explainer-check.sh scripts/explainer-publish.sh 2>/dev/null || true

# --- 2. fill in the non-Pages config (PAGES_BASE handled after enabling) -----
for f in .github/workflows/pr-explainer.yml .github/scripts/pr-explainer-check.sh \
         .github/prompts/explainer-generation.md \
         scripts/explainer-publish.sh docs/pr-explainer.md; do
  subst "$f" "__BASE_BRANCH__"   "$base"
  subst "$f" "__AI_BRANCH__"     "$ai_branch"
  subst "$f" "__EXPLAINER_DIR__" "$explainer_dir"
  subst "$f" "__PUBLISH_CMD__"   "$publish_cmd"
done
echo "  filled base/ai-branch/explainer-dir/publish-cmd"

# --- 3. gitignore the explainer dir on the base branch ----------------------
ignore_line="${explainer_dir}/"
if [[ -f .gitignore ]]; then
  if ! grep -qxF "$ignore_line" .gitignore; then
    printf '\n# PR explainers are tracked only on the %s branch (Pages serves them there).\n%s\n' \
      "$ai_branch" "$ignore_line" >> .gitignore
    echo "  added '$ignore_line' to .gitignore"
  else
    echo "  .gitignore already ignores '$ignore_line'"
  fi
else
  printf '# PR explainers are tracked only on the %s branch (Pages serves them there).\n%s\n' \
    "$ai_branch" "$ignore_line" > .gitignore
  echo "  wrote .gitignore"
fi

# --- 4. add the publish script to package.json (if present) -----------------
if [[ -f package.json ]]; then
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    if jq '.scripts |= ((. // {}) + {"explainer:publish":"bash scripts/explainer-publish.sh"})' \
        package.json > "$tmp" 2>/dev/null; then
      mv "$tmp" package.json
      echo "  added \"explainer:publish\" to package.json scripts"
    else
      rm -f "$tmp"
      echo "  ⚠ could not edit package.json (invalid JSON?); add manually:"
      echo '      "explainer:publish": "bash scripts/explainer-publish.sh"'
    fi
  else
    echo "  ⚠ jq not found — add this to package.json scripts manually:"
    echo '      "explainer:publish": "bash scripts/explainer-publish.sh"'
  fi
fi

# --- 5. bootstrap the orphan docs branch ------------------------------------
bootstrap_ai_docs() {
  if git ls-remote --exit-code --heads origin "$ai_branch" >/dev/null 2>&1; then
    echo "  skip  bootstrap (origin/$ai_branch already exists)"
    return 0
  fi
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "  ⚠ repo has no commits yet — commit something, then re-run to bootstrap $ai_branch" >&2
    return 1
  fi
  local wt rc=0; wt="$(mktemp -d)"
  if ! git worktree add -q --detach "$wt" >/dev/null 2>&1; then
    echo "  ⚠ could not create a worktree to bootstrap $ai_branch" >&2
    rm -rf "$wt"; return 1
  fi
  (
    set -e
    cd "$wt"
    git checkout -q --orphan "$ai_branch"
    git rm -rqf . >/dev/null 2>&1 || true
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
    : > .nojekyll
    mkdir -p "$explainer_dir"
    : > "$explainer_dir/.gitkeep"
    cat > .gitignore <<GI
# This is the PR-explainer docs branch. It intentionally TRACKS $explainer_dir/
# (Pages serves those files). Do not add $explainer_dir/ here.
GI
    cat > index.html <<HTML
<!doctype html>
<meta charset="utf-8">
<title>PR explainers</title>
<h1>PR explainers</h1>
<p>AI-generated HTML explainers for pull requests live under
<code>$explainer_dir/</code>. Open a PR's bot comment to find its link.</p>
HTML
    git add -A
    git -c user.name="pr-explainer installer" \
        -c user.email="pr-explainer@users.noreply.github.com" \
        commit -q -m "chore($ai_branch): bootstrap PR-explainer docs branch"
    git push -q -u origin "HEAD:$ai_branch"
  ) || rc=$?
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$wt"
  if [[ $rc -eq 0 ]]; then
    echo "  created orphan branch '$ai_branch' and pushed to origin"
  else
    echo "  ⚠ bootstrap of '$ai_branch' failed (see errors above)" >&2
  fi
  return $rc
}

if [[ $do_bootstrap -eq 1 ]]; then
  if [[ $have_gh -eq 0 ]] && ! git remote get-url origin >/dev/null 2>&1; then
    echo "  ⚠ no 'origin' remote — skipping $ai_branch bootstrap"
  else
    bootstrap_ai_docs || true
  fi
else
  echo "  skip  bootstrap ($ai_branch) — --no-bootstrap"
fi

# --- 6. enable GitHub Pages on the docs branch, capture the URL -------------
# Progress goes to stderr; only the resolved URL is echoed to stdout.
enable_pages() {
  local repo="$1" body i url=""
  body="$(printf '{"source":{"branch":"%s","path":"/"}}' "$ai_branch")"
  if gh api "repos/$repo/pages" >/dev/null 2>&1; then
    echo "  Pages already enabled; pointing source at $ai_branch" >&2
    printf '%s' "$body" | gh api -X PUT "repos/$repo/pages" --input - >/dev/null 2>&1 \
      || echo "  ⚠ could not update Pages source (continuing)" >&2
  else
    echo "  enabling GitHub Pages (branch=$ai_branch, path=/)" >&2
    if ! printf '%s' "$body" | gh api -X POST "repos/$repo/pages" --input - >/dev/null 2>&1; then
      echo "  ⚠ could not enable Pages via API (private repos may need a paid plan)." >&2
      echo "    Enable manually: Settings → Pages → Deploy from a branch → $ai_branch / (root)" >&2
      return 1
    fi
  fi
  # html_url can lag for a freshly-created Pages site; poll briefly.
  for i in 1 2 3 4 5 6 7 8; do
    url="$(gh api "repos/$repo/pages" --jq '.html_url' 2>/dev/null || true)"
    [[ -n "$url" && "$url" != "null" ]] && break
    sleep 3
  done
  printf '%s' "${url%/}"
}

pages_url=""
if [[ $do_pages -eq 1 ]]; then
  if [[ $have_gh -eq 1 && -n "$repo" ]]; then
    pages_url="$(enable_pages "$repo")"
  else
    echo "  ⚠ gh CLI or repo slug unavailable — skipping Pages enablement"
  fi
else
  echo "  skip  Pages enablement — --no-pages"
fi

# --- 7. fill in PAGES_BASE --------------------------------------------------
if [[ -n "$pages_url" && "$pages_url" != "null" ]]; then
  for f in .github/workflows/pr-explainer.yml scripts/explainer-publish.sh docs/pr-explainer.md; do
    subst "$f" "__PAGES_BASE__" "$pages_url"
  done
  echo "  filled PAGES_BASE = $pages_url"
else
  echo "  ⚠ PAGES_BASE not set — Pages URL not available yet."
  echo "    Once Pages is live, finish with either:"
  echo "      • re-run this installer (it will fill PAGES_BASE in), or"
  echo "      • set it by hand from: gh api repos/${repo:-:owner/:repo}/pages --jq .html_url"
fi

# --- done -------------------------------------------------------------------
cat <<NEXT

✓ pr-explainer installed.

next steps:
  1. commit + push these files on '$base' (the workflow, check + publish scripts,
     docs, and the .gitignore / package.json edits), then open/refresh a PR.
  2. the bot posts a 🔴 sticky comment + a failing 'pr-explainer' status.
  3. generate the explainer in Claude Code (copy the prompt from the comment),
     which writes $explainer_dir/<PR#>-<DIFF_ID>-explainer.html
  4. publish it:   $publish_cmd
  5. ~30-60s later the comment flips 🟢 and the status passes.

docs: docs/pr-explainer.md
NEXT

if [[ -z "$pages_url" && $do_pages -eq 1 ]]; then
  echo "NOTE: set PAGES_BASE before step 4 (see the warning above)." >&2
fi
