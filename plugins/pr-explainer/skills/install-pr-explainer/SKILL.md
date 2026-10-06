---
name: install-pr-explainer
description: Install the AI PR-explainer GitHub Action into a repository — a sticky-comment nag bot + commit-status gate that wants an AI-generated HTML "explainer" for every PR, plus the publish path that serves it from GitHub Pages. The installer copies the workflow + check/publish scripts + docs, bootstraps an orphan ai-docs branch, enables GitHub Pages, and fills in the repo-specific config. This is a MANUAL, user-invoked setup skill — use it ONLY when the user explicitly asks to install / set up / add the pr-explainer action. Do NOT trigger it automatically from general talk about PRs, CI, code review, or explainers.
---

# Install pr-explainer

Install the PR-explainer GitHub Action into the user's repository. It gives
every PR a sticky bot comment + a `pr-explainer` commit-status check that stays
red until an AI-generated HTML walkthrough of the PR is published to GitHub
Pages, then turns green and links it.

## When to trigger

Explicit, manual invocation only:

- "install the pr-explainer action" / "set up pr-explainer" / "add the PR
  explainer bot to this repo"

This skill mutates the user's GitHub repo (creates a branch, enables Pages,
posts a status check), so it should never fire on its own. If the user is just
discussing PRs, explainers, or CI without asking to install it, do nothing.

## What it is

A two-part system (see `references/architecture.md` for the full design):

1. **Nag + gate** — `.github/workflows/pr-explainer.yml` runs
   `.github/scripts/pr-explainer-check.sh` on PR events. It computes the PR's
   net-diff identity (`DIFF_ID`, a stable `git patch-id`), checks whether a
   matching explainer file exists on the docs branch, and upserts one sticky
   comment + one commit status: 🔴 none / 🟡 stale / 🟢 ready.
2. **Publish** — `scripts/explainer-publish.sh` (wrapped as
   `explainer:publish`) pushes the generated HTML to an orphan **ai-docs**
   branch served by **GitHub Pages**, and re-runs the workflow from that branch
   so the just-published PR flips green without a new commit.

## Approach

The installer and all template files are bundled **inside this skill
directory** (`scripts/install.sh` + `assets/`), so the skill is self-contained.
Run the bundled
script by its absolute path — use this skill's own base directory (shown to you
when the skill loads), not a hardcoded path:

```
Tell the user what you're about to do, then run:
  bash "<this-skill-dir>/scripts/install.sh" --target <repo>
```

`<this-skill-dir>` is the directory containing this SKILL.md. The script
resolves its templates relative to itself. Default `--target` is the current
directory; pass it explicitly to install elsewhere.

Before running, sanity-check the prerequisites below and tell the user what the
install will do to their GitHub repo (branch + Pages are real, outward-facing
changes). If anything looks off — wrong repo, no push access, Pages restricted
on their plan — surface it rather than pushing ahead.

## Prerequisites

- A git repo with a GitHub `origin` remote the user can push to.
- `gh` CLI installed and authenticated (`gh auth status`). Needed to enable
  Pages and read the Pages URL. Without it, pass `--no-pages --no-bootstrap`
  and the install degrades to copying files only.
- GitHub Actions enabled, with **read/write workflow permissions** (Settings →
  Actions → General → Workflow permissions). The workflow's own `permissions:`
  block requests `pull-requests: write` + `statuses: write`; if the repo
  default is read-only the status post can fail. If the check never appears,
  this is the first thing to check.
- GitHub Pages available on the repo's plan (private repos need a plan that
  supports Pages; they get a randomized `*.pages.github.io` URL).

## What the install does

Idempotent — re-running is safe; existing files are skipped unless `--force`.

1. Copies `.github/workflows/pr-explainer.yml`,
   `.github/scripts/pr-explainer-check.sh`, `scripts/explainer-publish.sh`,
   and `docs/pr-explainer.md`. `chmod +x` the two scripts.
2. Fills in the repo-specific config (base branch, ai-branch, explainer dir,
   publish command) by substituting `__TOKEN__` placeholders.
3. Adds `<explainer-dir>/` to `.gitignore` on the base branch (explainers live
   only on the docs branch).
4. Adds `"explainer:publish": "bash scripts/explainer-publish.sh"` to
   `package.json` scripts (if a `package.json` exists; needs `jq`).
5. Bootstraps the orphan **ai-docs** branch (`.nojekyll`, a tiny landing page,
   its own `.gitignore`, an empty explainer dir) and pushes it — skipped if it
   already exists on origin.
6. Enables **GitHub Pages** (deploy-from-branch on ai-docs), polls for the
   Pages URL, and substitutes it into `PAGES_BASE`.
7. Prints next steps.

The publish command is auto-detected: `pnpm` / `yarn` / `bun` / `npm run`
`explainer:publish` if a lockfile is present, else
`bash scripts/explainer-publish.sh` directly.

## Flags

- `--target DIR` — repo to install into (default: current dir).
- `--base NAME` — base branch PRs target / diffs measure against (default: the
  repo's detected default branch).
- `--ai-branch NAME` — orphan docs branch (default `ai-docs`).
- `--explainer-dir NAME` — folder holding explainers (default `html-explainers`).
- `--publish-cmd CMD` — override the auto-detected publish command.
- `--no-bootstrap` — don't create the ai-docs branch.
- `--no-pages` — don't enable GitHub Pages (leaves `PAGES_BASE` unset).
- `--force` — overwrite existing files.

If `PAGES_BASE` can't be resolved (Pages not live yet, or `--no-pages`), the
installer leaves the token in place and tells the user to re-run the installer
once Pages is provisioned, or set it from
`gh api repos/:owner/:repo/pages --jq .html_url`.

## After install

Tell the user the loop:

1. Commit + push the new files on the base branch and open/refresh a PR.
2. The bot posts a 🔴 sticky comment with a ready-to-paste generation prompt
   and a failing `pr-explainer` status.
3. In Claude Code, run that prompt (it writes
   `<explainer-dir>/<PR#>-<DIFF_ID>-explainer.html`).
4. Run the publish command shown in the comment.
5. ~30–60s later the comment flips 🟢 and the status passes.

For the full design, the three states, the diff-id keying, and troubleshooting,
read `references/architecture.md`.
