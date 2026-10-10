#!/usr/bin/env bash
# Publishes generated docs (plans, explainers, incident write-ups, investigations, research,
# prototypes) to the docs-only ai-docs branch and rebuilds its knowledge-base index. Docs are
# staged in the gitignored ai-docs/ folder at the repo root, at the same path they get on the
# branch (ai-docs/<type>/<YYYY-MM-DD-slug>.<html|md>). Settings come from .ai-docs.json.
#
# Publishing happens inside a THROWAWAY git worktree, so the current branch and working tree are
# never touched. A push that loses a race with a teammate is retried on top of the new branch tip.
# Staged files are deleted after a successful push (the branch is the source of truth).
#
# Usage:
#   publish.sh ai-docs/incidents/2026-10-09-foo.html [more files...]
#   publish.sh --rm explainers/2026-10-01-old.html   # delete a doc from the branch
# Options:
#   --keep            keep the staged files after publishing
#   --no-open         do not open the first published HTML file locally
#   --rm <path>       remove <path> (relative to the branch root) from the branch; repeatable
#   --allow-secrets   publish even though the secret scan matched (only after checking every hit)
#
# Managed by the install-ai-docs skill: edit .ai-docs.json and re-run the installer, not this file.

# No `set -u`: macOS ships bash 3.2, where expanding an empty array trips it.
set -eo pipefail

# Package-manager aliases (pnpm ai-docs:publish) run from the package root; resolve paths from
# where the user actually ran the command.
[[ -n "${INIT_CWD:-}" ]] && cd "$INIT_CWD"

HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ai-docs.mjs"
ROOT="$(git rev-parse --show-toplevel)"
STAGE="${ROOT}/ai-docs"
export AI_DOCS_CONFIG="${ROOT}/.ai-docs.json"
NAME_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9.-]*\.(html|md)$'

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit "${1:-0}"; }

command -v node >/dev/null 2>&1 || { echo "ai-docs publishing needs node on PATH." >&2; exit 1; }
# Sets AI_BRANCH, REPO_SLUG, PAGES_BASE and TYPES.
cfg="$(node "$HELPER" env)" || { echo "Cannot read ${AI_DOCS_CONFIG}" >&2; exit 1; }
eval "$cfg"

keep=0 open_after=1 allow_secrets=0
files=() abs_files=() rels=() removes=()
while (($#)); do
  case "$1" in
    --keep) keep=1 ;;
    --no-open) open_after=0 ;;
    --allow-secrets) allow_secrets=1 ;;
    --rm) [[ -n "${2:-}" ]] || { echo "--rm needs a path" >&2; exit 1; }; removes+=("$2"); shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) files+=("$1") ;;
  esac
  shift
done
((${#files[@]} + ${#removes[@]})) || usage 1

is_type() { local t; for t in "${TYPES[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

# --- 1. Validate staged files: ai-docs/<type>/<YYYY-MM-DD-slug>.<html|md> ------------------
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { echo "Not found: $f" >&2; exit 1; }
  abs="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
  rel="${abs#"${STAGE}/"}"
  if [[ "$rel" == "$abs" || "$rel" != */* || "${rel#*/}" == */* ]]; then
    echo "Stage docs at ai-docs/<type>/<file> in the repo root: $f" >&2; exit 1
  fi
  type="${rel%%/*}" name="${rel#*/}"
  is_type "$type" || { echo "Unknown type folder '$type' (use: ${TYPES[*]})" >&2; exit 1; }
  [[ "$name" =~ $NAME_RE ]] || { echo "Name must be YYYY-MM-DD-slug.html|md (lowercase): $name" >&2; exit 1; }
  rels+=("$rel") abs_files+=("$abs")
done
files=("${abs_files[@]}")
for r in "${removes[@]}"; do
  [[ "$r" != /* && "$r" != *..* && "$r" != .github/* && "$r" != index.html && "$r" == */* ]] \
    || { echo "Refusing to remove '$r'" >&2; exit 1; }
done

# --- 2. Secret scan --------------------------------------------------------------------------
if ((${#files[@]})) && ! node "$HELPER" scan "${files[@]}"; then
  if ((allow_secrets)); then
    echo "Secret scan matched; publishing anyway (--allow-secrets)." >&2
  else
    echo "Secret scan matched. Redact the values (name the secret store or env var instead) and rerun." >&2
    echo "If every hit is a known non-secret, rerun with --allow-secrets." >&2
    exit 1
  fi
fi

# --- 3. Publish from a throwaway worktree, retrying if a teammate pushed first ---------------
git fetch -q origin "$AI_BRANCH" \
  || { echo "Cannot fetch origin/${AI_BRANCH}. Run the install-ai-docs installer to create it." >&2; exit 1; }
tmp="$(mktemp -d)"
cleanup() { git worktree remove --force "$tmp" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
git worktree add -q --detach "$tmp" "origin/${AI_BRANCH}"

pushed=0
for attempt in 1 2 3 4 5; do
  if ((attempt > 1)); then
    git -C "$tmp" fetch -q origin "$AI_BRANCH"
    git -C "$tmp" reset -q --hard "origin/${AI_BRANCH}"
  fi
  for i in "${!rels[@]}"; do
    mkdir -p "${tmp}/$(dirname "${rels[$i]}")"
    cp "${files[$i]}" "${tmp}/${rels[$i]}"
    git -C "$tmp" add "${rels[$i]}"
  done
  for r in "${removes[@]}"; do
    git -C "$tmp" rm -q --ignore-unmatch -- "$r"
  done
  if git -C "$tmp" diff --cached --quiet >/dev/null; then  # git 2.51 prints new-file headers even with --quiet
    echo "Already published; nothing changed."
    pushed=2; break
  fi
  summary="$(printf '%s ' "${rels[@]}" "${removes[@]/#/-}")"
  git -C "$tmp" commit -q -m "docs(ai-docs): ${summary% }"
  # The index reads first-add authors from git history, so build it after the docs commit.
  node "$HELPER" index "$tmp"
  git -C "$tmp" add index.html
  git -C "$tmp" commit -q --amend --no-edit
  if git -C "$tmp" push -q origin "HEAD:${AI_BRANCH}" 2>/dev/null; then
    pushed=1; break
  fi
  echo "Push rejected (someone published first); retrying ($attempt/5)..." >&2
  sleep $((attempt))
done
((pushed)) || { echo "Could not push to ${AI_BRANCH} after 5 attempts." >&2; exit 1; }

# --- 4. Report URLs --------------------------------------------------------------------------
for rel in "${rels[@]}"; do
  if [[ -n "$PAGES_BASE" && "$rel" == *.html ]]; then
    echo "${PAGES_BASE}/${rel}"
  elif [[ -n "$REPO_SLUG" ]]; then
    echo "https://github.com/${REPO_SLUG}/blob/${AI_BRANCH}/${rel}"
  else
    echo "${AI_BRANCH}:${rel}"
  fi
done
for r in "${removes[@]}"; do echo "removed ${r}"; done
if [[ -n "$PAGES_BASE" ]]; then
  echo "Index: ${PAGES_BASE}/"
  ((pushed == 1)) && echo "(GitHub Pages takes ~1-2 min to go live.)"
fi

# --- 5. Open the first HTML doc locally (a preview copy, since the staged file is deleted) ---
if ((open_after)); then
  for i in "${!rels[@]}"; do
    [[ "${rels[$i]}" == *.html ]] || continue
    preview="${TMPDIR:-/tmp}/ai-docs-preview/${rels[$i]}"
    mkdir -p "$(dirname "$preview")" && cp "${files[$i]}" "$preview"
    bm_open="$(command -v bm-open || echo "${HOME}/.bun/bin/bm-open")"
    if [[ -n "${BMUX_PANE_ID:-}" && -x "$bm_open" ]] && "$bm_open" "$preview" >/dev/null 2>&1; then
      echo "Opened in browser-mux: $preview"
    elif command -v open >/dev/null 2>&1; then
      open "$preview" && echo "Opened: $preview"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$preview" >/dev/null 2>&1 && echo "Opened: $preview"
    fi
    break
  done
fi

# --- 6. Delete staged files (the branch is now the source of truth) ---------------------------
if ((!keep)); then
  for f in "${files[@]}"; do rm -f "$f"; done
  find "$STAGE" -type d -empty -delete 2>/dev/null || true
fi
