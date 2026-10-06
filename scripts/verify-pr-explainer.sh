#!/usr/bin/env bash
# Local verification gate for the install-pr-explainer skill. Run from repo root.
# Exits non-zero on any failure so it can gate trunk commits.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
S=plugins/pr-explainer/skills/install-pr-explainer   # the skill dir — scripts + assets are bundled here
fails=0
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails+1)); }
sec(){ printf '\n== %s ==\n' "$1"; }

sec "A. shellcheck (error severity gates)"
for s in "$S/scripts/install.sh" "$S/assets/.github/scripts/pr-explainer-check.sh" "$S/assets/scripts/explainer-publish.sh"; do
  if shellcheck -S error "$s" >/dev/null 2>&1; then pass "no errors: $s"; else fail "shellcheck errors: $s"; fi
done

sec "B. SKILL.md frontmatter"
python3 - "$S/SKILL.md" <<'PY'
import sys,re
def fm(path):
    t=open(path).read()
    m=re.match(r'^---\n(.*?)\n---\n',t,re.S)
    if not m: return None
    d={}
    for line in m.group(1).splitlines():
        if ':' in line:
            k,v=line.split(':',1); d[k.strip()]=v.strip()
    return d
skill=fm(sys.argv[1]); ok=True
if skill and skill.get('name')=='install-pr-explainer' and skill.get('description'):
    print("  PASS SKILL.md frontmatter: name+description present")
else:
    print("  FAIL SKILL.md frontmatter"); ok=False
sys.exit(0 if ok else 1)
PY
[[ $? -eq 0 ]] || fails=$((fails+1))

sec "C. installer matrix (throwaway repos)"
mk(){
  local d; d="$(mktemp -d)"
  (
    cd "$d"; git init -q; git config user.email t@t.co; git config user.name t
    "$@" >/dev/null 2>&1 || true
    echo seed > .seed   # always have something to commit
    git add -A; git commit -qm init
  ) >/dev/null 2>&1
  echo "$d"
}
# Run with CLAUDE_PLUGIN_ROOT UNSET to prove the script self-resolves its assets
# (the standalone-skill install case — the bug from issue #2).
RUN(){ env -u CLAUDE_PLUGIN_ROOT bash "$S/scripts/install.sh" --target "$1" --no-bootstrap --no-pages "${@:2}"; }
notoken(){ ! grep -rqE '__(BASE_BRANCH|AI_BRANCH|EXPLAINER_DIR|PUBLISH_CMD)__' "$1/.github" "$1/scripts" 2>/dev/null; }

# E1: no package.json -> bash publish cmd (the publish cmd lives in the prompt file)
d1="$(mk true)"; RUN "$d1" --base main >/dev/null 2>&1
grep -q 'bash scripts/explainer-publish.sh' "$d1/.github/prompts/explainer-generation.md" \
  && notoken "$d1" && pass "no-pkg: publish-cmd=bash, tokens filled" || fail "no-pkg case"

# E2: pnpm repo -> pnpm publish cmd (the publish cmd lives in the prompt file)
d2="$(mk sh -c 'echo {} > package.json; : > pnpm-lock.yaml')"; RUN "$d2" --base main >/dev/null 2>&1
grep -q 'pnpm explainer:publish' "$d2/.github/prompts/explainer-generation.md" \
  && jq -e '.scripts."explainer:publish"' "$d2/package.json" >/dev/null 2>&1 \
  && pass "pnpm: publish-cmd=pnpm + package.json script added" || fail "pnpm case"

# E3: custom ai-branch + explainer-dir substituted into triggers/paths
d3="$(mk true)"; RUN "$d3" --base trunk --ai-branch docs-site --explainer-dir pr-docs >/dev/null 2>&1
wf="$d3/.github/workflows/pr-explainer.yml"
grep -q 'branches: \[trunk\]' "$wf" && grep -q 'branches: \[docs-site\]' "$wf" \
  && grep -q 'pr-docs/\*\*' "$wf" && notoken "$d3" \
  && pass "custom flags: base/ai-branch/explainer-dir substituted in triggers" || fail "custom-flags case"

# E4: idempotent re-run -> skips existing
d4="$(mk true)"; RUN "$d4" --base main >/dev/null 2>&1
reout="$(RUN "$d4" --base main 2>&1)"
echo "$reout" | grep -q 'skip  .github/workflows/pr-explainer.yml (exists' \
  && pass "idempotent: re-run skips existing files" || fail "idempotent re-run"

# E5: --force overwrites
fout="$(RUN "$d4" --base main --force 2>&1)"
echo "$fout" | grep -q 'wrote .github/workflows/pr-explainer.yml' \
  && pass "--force: overwrites existing files" || fail "--force case"

# E6: --no-pages leaves only PAGES_BASE token, nothing else
d6="$(mk true)"; RUN "$d6" --base main >/dev/null 2>&1
left="$(grep -rhoE '__[A-Z_]+__' "$d6/.github" "$d6/scripts" 2>/dev/null | grep -v '__TOKEN__' | sort -u | tr '\n' ' ')"
[[ "$left" == "__PAGES_BASE__ " ]] && pass "no-pages: only __PAGES_BASE__ remains" || fail "unexpected leftover tokens: [$left]"

rm -rf "$d1" "$d2" "$d3" "$d4" "$d6"

sec "D. skill is self-contained (standalone-skill install — issue #2)"
selfok=1
[[ -f "$S/scripts/install.sh" ]] || { fail "install.sh not bundled in skill dir"; selfok=0; }
for t in .github/workflows/pr-explainer.yml .github/scripts/pr-explainer-check.sh \
         .github/prompts/explainer-generation.md \
         scripts/explainer-publish.sh docs/pr-explainer.md; do
  [[ -f "$S/assets/$t" ]] || { fail "missing bundled template: assets/$t"; selfok=0; }
done
[[ $selfok -eq 1 ]] && pass "install.sh + 5 templates bundled under the skill dir"

sec "RESULT"
if [[ $fails -eq 0 ]]; then printf '\033[32mALL CHECKS PASSED\033[0m\n'; exit 0; else printf '\033[31m%d CHECK(S) FAILED\033[0m\n' "$fails"; exit 1; fi
