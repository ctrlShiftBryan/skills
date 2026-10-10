#!/usr/bin/env bash
# Local verification gate for the install-ai-docs skill. Run from repo root.
# Exits non-zero on any failure so it can gate trunk commits.
#   SKIP_LIVE=1  skip the read-only dry-run against dynasty-nerds-monorepo (needs gh + network)
# Helpers run through check(); literal backticks in patterns are intended.
# shellcheck disable=SC2329,SC2016
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
S="$PWD/plugins/ai-docs/skills/install-ai-docs"
I="$S/scripts/install.sh"
MONOREPO="${MONOREPO:-$HOME/code/dynasty-nerds-monorepo}"
fails=0
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails+1)); }
check(){ local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }
sec(){ printf '\n== %s ==\n' "$1"; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sec "A. lint"
for s in "$I" "$S/assets/ai-docs/scripts/publish.sh" "$0"; do
  check "shellcheck: ${s#"$PWD"/}" shellcheck "$s"
done
for m in "$S/scripts/install-helper.mjs" "$S/assets/ai-docs/scripts/ai-docs.mjs"; do
  check "node --check: ${m#"$PWD"/}" node --check "$m"
done

sec "B. skill files"
fm(){ awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$1"; }
check "install-ai-docs SKILL.md has name + description" \
  sh -c "$(declare -f fm); fm '$S/SKILL.md' | grep -qx 'name: install-ai-docs' && fm '$S/SKILL.md' | grep -q '^description: .'"
check "vendored template is not a SKILL.md (npx skills must not install it globally)" \
  test ! -e "$S/assets/ai-docs/SKILL.md"
check "plugins/ai-docs/README.md exists" test -f plugins/ai-docs/README.md
check "README.md Skills table lists ai-docs" grep -q 'plugins/ai-docs' README.md

# mkrepo NAME [setup-cmd...] — a repo with one commit, pushed to its own bare origin.
mkrepo(){
  local d="$WORK/$1"; shift
  git init -q --bare "$d.git"
  git init -q -b main "$d"
  (
    cd "$d" || exit 1
    git config user.email t@t.co; git config user.name Tester
    echo seed > README.md
    if (($#)); then "$@"; fi
    git add -A; git commit -qm init
    git remote add origin "$d.git"; git push -q origin main
  ) >/dev/null 2>&1
  echo "$d"
}
RUN(){ local d="$1"; shift; bash "$I" --target "$d" --no-github --repo acme/widgets "$@"; }
sum(){ (cd "$1" && git status --porcelain && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 cat) | shasum; }
count(){ grep -c "$1" "$2"; }
eq(){ [[ "$1" == "$2" ]]; }

sec "C. installer: files (no GitHub)"
d="$(mkrepo dry sh -c 'mkdir notes; echo x > notes/a.md')"
before="$(sum "$d")"
out="$(RUN "$d" --dry-run 2>&1)"
check "dry-run: no local writes" eq "$before" "$(sum "$d")"
check "dry-run: no remote branch" sh -c "! git -C '$d' ls-remote --exit-code --heads origin ai-docs"
check "dry-run: scan lists notes/a.md" grep -q 'notes/a.md' <<<"$out"

d="$(mkrepo fresh)"
RUN "$d" >/dev/null 2>&1; rc=$?
check "fresh: exit 0" eq "$rc" 0
check "fresh: AGENTS.md holds the section" grep -q '^## Generated docs' "$d/AGENTS.md"
check "fresh: CLAUDE.md is just @AGENTS.md" eq "$(cat "$d/CLAUDE.md")" "@AGENTS.md"
check "fresh: copilot instructions hold the rule" grep -q 'ai-docs:start' "$d/.github/copilot-instructions.md"
check "fresh: .gitignore has /ai-docs/" grep -qx '/ai-docs/' "$d/.gitignore"
check "fresh: .ai-docs.json is valid" node -e "JSON.parse(require('fs').readFileSync('$d/.ai-docs.json','utf8'))"
check "fresh: vendored publish.sh is executable" test -x "$d/.claude/skills/ai-docs/scripts/publish.sh"
check "fresh: SKILL.md has no unfilled tokens" sh -c "! grep -q '__[A-Z_]*__' '$d/.claude/skills/ai-docs/SKILL.md'"
check "fresh: SKILL.md names the bash publish command" grep -q 'bash .claude/skills/ai-docs/scripts/publish.sh ai-docs/' "$d/.claude/skills/ai-docs/SKILL.md"
check "fresh: orphan branch has .nojekyll + index.html" \
  sh -c "git -C '$d.git' ls-tree --name-only ai-docs | grep -qx .nojekyll && git -C '$d.git' ls-tree --name-only ai-docs | grep -qx index.html"
check "fresh: ai-docs shares no history with main" sh -c "! git -C '$d.git' merge-base main ai-docs"
check "fresh: changes left uncommitted" test -n "$(git -C "$d" status --porcelain)"
before="$(sum "$d")"
RUN "$d" >/dev/null 2>&1
check "re-run: nothing changes" eq "$before" "$(sum "$d")"
RUN "$d" --allow-path notes/ >/dev/null 2>&1
check "re-run with --allow-path: section updated in place" eq "$(count 'ai-docs:start' "$d/AGENTS.md")" 1
check "re-run with --allow-path: new path in the rule" grep -q '`notes/`' "$d/AGENTS.md"
check "re-run with --allow-path: kept in .ai-docs.json" grep -q '"notes/"' "$d/.ai-docs.json"

d="$(mkrepo agents-only sh -c 'printf "# Rules\n\nBe nice.\n" > AGENTS.md')"
RUN "$d" >/dev/null 2>&1
check "AGENTS only: original text kept" grep -q 'Be nice.' "$d/AGENTS.md"
check "AGENTS only: section appended" grep -q '^## Generated docs' "$d/AGENTS.md"
check "AGENTS only: CLAUDE.md created with import" eq "$(cat "$d/CLAUDE.md")" "@AGENTS.md"

d="$(mkrepo both-no-import sh -c 'echo "# A" > AGENTS.md; printf "# Claude\n\nStuff.\n" > CLAUDE.md')"
RUN "$d" >/dev/null 2>&1
check "both, no import: CLAUDE.md starts with @AGENTS.md" eq "$(head -1 "$d/CLAUDE.md")" "@AGENTS.md"
check "both, no import: CLAUDE.md keeps its text" grep -q 'Stuff.' "$d/CLAUDE.md"
check "both, no import: section only in AGENTS.md" sh -c "! grep -q 'ai-docs:start' '$d/CLAUDE.md'"

d="$(mkrepo both-import sh -c 'echo "# A" > AGENTS.md; printf "# Claude\n@AGENTS.md\n" > CLAUDE.md')"
RUN "$d" >/dev/null 2>&1
check "both, with import: CLAUDE.md untouched" eq "$(cat "$d/CLAUDE.md")" "$(printf '# Claude\n@AGENTS.md')"

d="$(mkrepo claude-only sh -c 'printf "# Claude\n" > CLAUDE.md')"
RUN "$d" >/dev/null 2>&1
check "CLAUDE only: section in CLAUDE.md" grep -q '^## Generated docs' "$d/CLAUDE.md"
check "CLAUDE only: no AGENTS.md created" test ! -e "$d/AGENTS.md"

d="$(mkrepo symlinked sh -c 'echo "# A" > AGENTS.md; ln -s AGENTS.md CLAUDE.md')"
RUN "$d" >/dev/null 2>&1
check "CLAUDE.md -> AGENTS.md symlink: still a symlink" test -L "$d/CLAUDE.md"
check "CLAUDE.md -> AGENTS.md symlink: no import line" sh -c "! grep -q '^@AGENTS.md' '$d/AGENTS.md'"

d="$(mkrepo dotclaude sh -c 'echo "# A" > AGENTS.md; mkdir .claude; echo "# C" > .claude/CLAUDE.md')"
RUN "$d" >/dev/null 2>&1
check ".claude/CLAUDE.md: gets @../AGENTS.md" eq "$(head -1 "$d/.claude/CLAUDE.md")" "@../AGENTS.md"
check ".claude/CLAUDE.md: no root CLAUDE.md created" test ! -e "$d/CLAUDE.md"

d="$(mkrepo pnpm sh -c 'printf "{\n    \"name\": \"x\",\n    \"scripts\": {\n        \"test\": \"true\"\n    }\n}\n" > package.json; : > pnpm-lock.yaml')"
RUN "$d" >/dev/null 2>&1
check "pnpm: alias added" sh -c "node -e \"process.exit(require('$d/package.json').scripts['ai-docs:publish']==='bash .claude/skills/ai-docs/scripts/publish.sh'?0:1)\""
check "pnpm: existing scripts kept" grep -q '"test": "true"' "$d/package.json"
check "pnpm: 4-space indent kept" grep -q '^    "name"' "$d/package.json"
check "pnpm: SKILL.md says pnpm ai-docs:publish" grep -q 'pnpm ai-docs:publish ai-docs/' "$d/.claude/skills/ai-docs/SKILL.md"

d="$(mkrepo ignored sh -c 'printf "node_modules\n/ai-docs/\n" > .gitignore')"
RUN "$d" >/dev/null 2>&1
check "existing /ai-docs/ ignore: not duplicated" eq "$(count 'ai-docs/' "$d/.gitignore")" 1

d="$(mkrepo adopt)"
(
  cd "$d" && git checkout -q --orphan ai-docs && git rm -rqf . && mkdir -p html-explainers \
    && echo '<title>PR 1</title>' > html-explainers/1-abc123-explainer.html && git add -A \
    && git commit -qm docs && git push -q origin ai-docs && git checkout -q main
) >/dev/null 2>&1
tip="$(git -C "$d.git" rev-parse ai-docs)"
out="$(RUN "$d" 2>&1)"
check "existing branch: adopted, not recreated" eq "$tip" "$(git -C "$d.git" rev-parse ai-docs)"
check "existing branch: plan says adopt" grep -q 'exists on origin; adopt it' <<<"$out"

sec "D. publish"
d="$(mkrepo pub)"
RUN "$d" >/dev/null 2>&1
P="$d/.claude/skills/ai-docs/scripts/publish.sh"
mkdir -p "$d/ai-docs/plans" "$d/ai-docs/explainers"
printf -- '---\ntitle: Test plan\ndescription: A plan.\n---\n# Test plan\n' > "$d/ai-docs/plans/2026-10-10-test-plan.md"
printf '<!doctype html><title>How X works</title><meta name="description" content="X.">' > "$d/ai-docs/explainers/2026-10-10-how-x.html"
check "staged docs are gitignored" sh -c "! git -C '$d' status --porcelain | grep -q ai-docs/"
out="$(cd "$d" && bash "$P" --no-open ai-docs/plans/2026-10-10-test-plan.md ai-docs/explainers/2026-10-10-how-x.html 2>&1)"; rc=$?
check "publish: exit 0" eq "$rc" 0
check "publish: Markdown URL points at GitHub" grep -q 'https://github.com/acme/widgets/blob/ai-docs/plans/2026-10-10-test-plan.md' <<<"$out"
check "publish: both docs on the branch" \
  sh -c "git -C '$d.git' cat-file -e ai-docs:plans/2026-10-10-test-plan.md && git -C '$d.git' cat-file -e ai-docs:explainers/2026-10-10-how-x.html"
check "publish: index lists both titles" \
  sh -c "git -C '$d.git' show ai-docs:index.html | grep -q 'Test plan' && git -C '$d.git' show ai-docs:index.html | grep -q 'How X works'"
check "publish: staged copies deleted" test ! -e "$d/ai-docs"
printf -- '---\ntitle: Test plan\n---\n# Test plan\n' > "$WORK/same.md"
mkdir -p "$d/ai-docs/plans"; git -C "$d.git" show ai-docs:plans/2026-10-10-test-plan.md > "$d/ai-docs/plans/2026-10-10-test-plan.md"
out="$(cd "$d" && bash "$P" --no-open ai-docs/plans/2026-10-10-test-plan.md 2>&1)"
check "republish unchanged: nothing changed" grep -q 'Already published; nothing changed.' <<<"$out"
mkdir -p "$d/ai-docs/research"; echo 'key AKIAABCDEFGHIJKLMNOP' > "$d/ai-docs/research/2026-10-10-leak.md"
(cd "$d" && bash "$P" --no-open ai-docs/research/2026-10-10-leak.md) >/dev/null 2>&1; rc=$?
check "secret scan: refuses" eq "$rc" 1
check "secret scan: nothing pushed" sh -c "! git -C '$d.git' cat-file -e ai-docs:research/2026-10-10-leak.md"
rm -rf "$d/ai-docs"
mkdir -p "$d/ai-docs/plans" "$d/ai-docs/stuff"
echo x > "$d/ai-docs/plans/Bad Name.md"; echo x > "$d/ai-docs/stuff/2026-10-10-x.md"
check "bad file name: refused" sh -c "cd '$d' && ! bash '$P' --no-open 'ai-docs/plans/Bad Name.md'"
check "unknown type folder: refused" sh -c "cd '$d' && ! bash '$P' --no-open ai-docs/stuff/2026-10-10-x.md"
rm -rf "$d/ai-docs"
check "--rm index.html: refused" sh -c "cd '$d' && ! bash '$P' --rm index.html"
check "--rm ../x: refused" sh -c "cd '$d' && ! bash '$P' --rm plans/../x.md"
(cd "$d" && bash "$P" --rm explainers/2026-10-10-how-x.html) >/dev/null 2>&1
check "--rm: doc removed from the branch" sh -c "! git -C '$d.git' cat-file -e ai-docs:explainers/2026-10-10-how-x.html"
mkdir -p "$d/sub" "$d/ai-docs/plans"; echo '# Sub' > "$d/ai-docs/plans/2026-10-10-from-sub.md"
(cd "$d" && INIT_CWD="$d/sub" bash "$P" --no-open ../ai-docs/plans/2026-10-10-from-sub.md) >/dev/null 2>&1
check "INIT_CWD (package-manager alias): relative path resolved" git -C "$d.git" cat-file -e ai-docs:plans/2026-10-10-from-sub.md

c1="$WORK/clone1" c2="$WORK/clone2"
git clone -q "$d.git" "$c1" 2>/dev/null; git clone -q "$d.git" "$c2" 2>/dev/null
for c in "$c1" "$c2"; do
  git -C "$c" config user.email t@t.co; git -C "$c" config user.name Tester
  cp -R "$d/.claude" "$d/.ai-docs.json" "$d/.gitignore" "$c/"
  mkdir -p "$c/ai-docs/research"
  echo "# $(basename "$c")" > "$c/ai-docs/research/2026-10-10-$(basename "$c").md"
done
(cd "$c1" && bash .claude/skills/ai-docs/scripts/publish.sh --no-open ai-docs/research/2026-10-10-clone1.md) >/dev/null 2>&1 &
(cd "$c2" && bash .claude/skills/ai-docs/scripts/publish.sh --no-open ai-docs/research/2026-10-10-clone2.md) >/dev/null 2>&1 &
wait
check "concurrent publishes: both land" \
  sh -c "git -C '$d.git' cat-file -e ai-docs:research/2026-10-10-clone1.md && git -C '$d.git' cat-file -e ai-docs:research/2026-10-10-clone2.md"
check "concurrent publishes: index lists both" \
  sh -c "git -C '$d.git' show ai-docs:index.html | grep -q 'clone1' && git -C '$d.git' show ai-docs:index.html | grep -q 'clone2'"

sec "E. installer: GitHub decisions (fake gh)"
FAKE_BIN="$WORK/fakebin"; mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Canned responses from $FAKE_GH/<METHOD>_<path with / as _>: line 1 = exit code, rest = body.
# After a write, $FAKE_GH/<same name>.then (if present) runs to change later responses.
[[ "$1" == auth ]] && exit 0
[[ "$1" == api ]] || exit 1
shift; method=GET path="" input=0
while (($#)); do case "$1" in -X) method="$2"; shift 2 ;; --input) input=1; shift 2 ;; *) path="$1"; shift ;; esac; done
body=""; ((input)) && body="$(cat)"
echo "$method $path $body" >> "$FAKE_GH/calls.log"
f="$FAKE_GH/${method}_${path//\//_}"
[[ -f "$f.then" ]] && bash "$f.then"
[[ -f "$f" ]] || { echo '{"message":"Not Found"}'; echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
code="$(head -1 "$f")"; tail -n +2 "$f"; exit "$code"
GH
chmod +x "$FAKE_BIN/gh"
# fake NAME VISIBILITY OWNER_TYPE — a fresh fake-GitHub state dir for acme/widgets.
fake(){
  local F="$WORK/fake-$1"; mkdir -p "$F"; : > "$F/calls.log"
  printf '0\n{"visibility":"%s","owner":{"type":"%s"},"permissions":{"admin":true,"push":true}}\n' "$2" "$3" > "$F/GET_repos_acme_widgets"
  printf '0\n{"plan":{"name":"free"}}\n' > "$F/GET_orgs_acme"
  printf '0\n[]\n' > "$F/GET_repos_acme_widgets_rulesets"
  printf '0\n{"id":7}\n' > "$F/POST_repos_acme_widgets_rulesets"
  printf '0\n{}\n' > "$F/POST_repos_acme_widgets_pages"
  printf '0\n{}\n' > "$F/PUT_repos_acme_widgets_pages"
  printf '0\n{}\n' > "$F/DELETE_repos_acme_widgets_pages"
  echo "$F"
}
# After POST /pages, GET /pages returns a site with the given public flag.
pages_after_post(){ printf 'printf "0\\n{\\"html_url\\":\\"https://x.pages.github.io/\\",\\"public\\":%s,\\"source\\":{\\"branch\\":\\"ai-docs\\"}}\\n" > "%s/GET_repos_acme_widgets_pages"\n' "$2" "$1" > "$1/POST_repos_acme_widgets_pages.then"; }
GRUN(){ local F="$1" d="$2"; shift 2; FAKE_GH="$F" PATH="$FAKE_BIN:$PATH" bash "$I" --target "$d" --repo acme/widgets "$@"; }
writes(){ grep -cE '^(POST|PUT|DELETE) ' "$1/calls.log"; }

F="$(fake userprivate private User)"; d="$(mkrepo g-userprivate)"; before="$(sum "$d")"
out="$(GRUN "$F" "$d" 2>&1)"; rc=$?
check "user-owned private, auto: exit 3 (decision needed)" eq "$rc" 3
check "user-owned private, auto: plan explains why" grep -q 'DECISION NEEDED' <<<"$out"
check "user-owned private, auto: no GitHub writes" eq "$(writes "$F")" 0
check "user-owned private, auto: no local writes" eq "$before" "$(sum "$d")"
check "user-owned private, auto: no branch pushed" sh -c "! git -C '$d.git' rev-parse -q --verify ai-docs"

F="$(fake pagesoff private User)"; d="$(mkrepo g-pagesoff)"
GRUN "$F" "$d" --pages off >/dev/null 2>&1; rc=$?
check "--pages off: exit 0" eq "$rc" 0
check "--pages off: Pages untouched" sh -c "! grep -q ' repos/acme/widgets/pages' '$F/calls.log' || ! grep -qE '^(POST|PUT|DELETE) repos/acme/widgets/pages' '$F/calls.log'"
check "--pages off: ruleset created" grep -q '^POST repos/acme/widgets/rulesets' "$F/calls.log"
check "--pages off: ruleset blocks deletion + force-push, admins bypass" \
  sh -c "grep '^POST repos/acme/widgets/rulesets' '$F/calls.log' | grep -q '\"deletion\"' && grep '^POST repos/acme/widgets/rulesets' '$F/calls.log' | grep -q '\"non_fast_forward\"' && grep '^POST repos/acme/widgets/rulesets' '$F/calls.log' | grep -q '\"actor_id\":5'"
check "--pages off: ruleset targets refs/heads/ai-docs" grep -q 'refs/heads/ai-docs' "$F/calls.log"
check "--pages off: pagesUrl null" grep -q '"pagesUrl": null' "$d/.ai-docs.json"

F="$(fake pageson private User)"; d="$(mkrepo g-pageson)"; pages_after_post "$F" true
GRUN "$F" "$d" --pages on >/dev/null 2>&1
check "--pages on, user private: Pages created" grep -q '^POST repos/acme/widgets/pages' "$F/calls.log"
check "--pages on, user private: docs marked world-readable" grep -q '"worldReadable": true' "$d/.ai-docs.json"
check "--pages on, user private: SKILL.md warns readers are the internet" grep -q 'Anyone on the internet can read' "$d/.claude/skills/ai-docs/SKILL.md"

F="$(fake enterprise private Organization)"; printf '0\n{"plan":{"name":"enterprise"}}\n' > "$F/GET_orgs_acme"
d="$(mkrepo g-enterprise)"; pages_after_post "$F" false
GRUN "$F" "$d" >/dev/null 2>&1; rc=$?
check "enterprise org private: exit 0" eq "$rc" 0
check "enterprise org private: Pages created" grep -q '^POST repos/acme/widgets/pages' "$F/calls.log"
check "enterprise org private: Pages restricted (public=false)" grep -q '^PUT repos/acme/widgets/pages {"public":false}' "$F/calls.log"
check "enterprise org private: Pages URL recorded" grep -q '"pagesUrl": "https://x.pages.github.io"' "$d/.ai-docs.json"
check "enterprise org private: SKILL.md links Pages" grep -q 'served at https://x.pages.github.io' "$d/.claude/skills/ai-docs/SKILL.md"
check "enterprise org private: not world-readable" grep -q '"worldReadable": false' "$d/.ai-docs.json"

F="$(fake stillpublic private Organization)"; printf '0\n{"plan":{"name":"enterprise"}}\n' > "$F/GET_orgs_acme"
d="$(mkrepo g-stillpublic)"; pages_after_post "$F" true
GRUN "$F" "$d" >/dev/null 2>&1
check "restriction didn't stick: Pages deleted again" grep -q '^DELETE repos/acme/widgets/pages' "$F/calls.log"
check "restriction didn't stick: no Pages URL recorded" grep -q '"pagesUrl": null' "$d/.ai-docs.json"

F="$(fake public public User)"; d="$(mkrepo g-public)"; pages_after_post "$F" true
GRUN "$F" "$d" >/dev/null 2>&1
check "public repo: Pages created without a restriction call" \
  sh -c "grep -q '^POST repos/acme/widgets/pages' '$F/calls.log' && ! grep -q '^PUT repos/acme/widgets/pages' '$F/calls.log'"

F="$(fake norules private User)"; printf '1\n{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}\ngh: Upgrade to GitHub Pro (HTTP 403)\n' > "$F/GET_repos_acme_widgets_rulesets"
d="$(mkrepo g-norules)"
out="$(GRUN "$F" "$d" --pages off 2>&1)"; rc=$?
check "plan without rulesets: exit 0" eq "$rc" 0
check "plan without rulesets: skipped with a reason" grep -q "plan has no rulesets" <<<"$out"
check "plan without rulesets: no ruleset call" sh -c "! grep -q '^POST repos/acme/widgets/rulesets' '$F/calls.log'"

F="$(fake otherpages public User)"
printf '0\n{"html_url":"https://acme.github.io/widgets/","public":true,"source":{"branch":"gh-pages"}}\n' > "$F/GET_repos_acme_widgets_pages"
d="$(mkrepo g-otherpages)"
out="$(GRUN "$F" "$d" 2>&1)"
check "Pages on another branch: left alone" sh -c "! grep -qE '^(POST|PUT|DELETE) repos/acme/widgets/pages' '$F/calls.log'"
check "Pages on another branch: plan says so" grep -q "Pages already serves branch 'gh-pages'" <<<"$out"
check "Pages on another branch: no Pages URL" grep -q '"pagesUrl": null' "$d/.ai-docs.json"

F="$(fake adoptpages private Organization)"
printf '0\n{"html_url":"https://y.pages.github.io/","public":false,"source":{"branch":"ai-docs"}}\n' > "$F/GET_repos_acme_widgets_pages"
printf '0\n[{"id":42,"name":"ai-docs protection"}]\n' > "$F/GET_repos_acme_widgets_rulesets"
printf '0\n{"id":42}\n' > "$F/PUT_repos_acme_widgets_rulesets_42"
d="$(mkrepo g-adoptpages)"
GRUN "$F" "$d" >/dev/null 2>&1
check "existing ai-docs Pages: adopted URL" grep -q '"pagesUrl": "https://y.pages.github.io"' "$d/.ai-docs.json"
check "existing ai-docs Pages: no Pages writes" sh -c "! grep -qE '^(POST|PUT|DELETE) repos/acme/widgets/pages' '$F/calls.log'"
check "existing ruleset: updated in place" grep -q '^PUT repos/acme/widgets/rulesets/42' "$F/calls.log"

sec "F. read-only dry-run against dynasty-nerds-monorepo"
if [[ "${SKIP_LIVE:-0}" == 1 ]]; then
  echo "  skipped (SKIP_LIVE=1)"
elif [[ ! -d "$MONOREPO/.git" && ! -f "$MONOREPO/.git" ]]; then
  fail "monorepo not found at $MONOREPO (set MONOREPO or SKIP_LIVE=1)"
else
  before="$(git -C "$MONOREPO" status --porcelain | shasum)"
  out="$(bash "$I" --target "$MONOREPO" --dry-run 2>&1)"; rc=$?
  check "monorepo dry-run: exit 0" eq "$rc" 0
  check "monorepo dry-run: working tree unchanged" eq "$before" "$(git -C "$MONOREPO" status --porcelain | shasum)"
  check "monorepo dry-run: adopts the existing ai-docs branch" grep -q 'exists on origin; adopt it' <<<"$out"
  check "monorepo dry-run: adopts the existing private Pages site" grep -q 'pages        adopt existing site .*public=false' <<<"$out"
  check "monorepo dry-run: says nothing was changed" grep -q 'Dry run: nothing was changed.' <<<"$out"
fi

sec "RESULT"
if ((fails == 0)); then printf '\033[32mALL CHECKS PASSED\033[0m\n'; exit 0; else printf '\033[31m%d CHECK(S) FAILED\033[0m\n' "$fails"; exit 1; fi
