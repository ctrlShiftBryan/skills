# pr-explainer

Installs the AI PR-explainer GitHub Action into a target repository. Every PR gets a sticky bot comment and a `pr-explainer` commit-status check that stays 🔴 red until an AI-generated HTML walkthrough of the PR's diff is published to GitHub Pages, then turns 🟢 green and links it. The setup is manual and user-invoked — it never auto-triggers from general PR, CI, or code-review chatter.

## Components

- `install-pr-explainer` — skill that copies the workflow + check/publish scripts + docs, bootstraps the orphan docs branch, enables GitHub Pages, and fills in the repo-specific config. Installer flags: `--target`, `--base`, `--ai-branch`, `--explainer-dir`, `--publish-cmd`, `--no-bootstrap`, `--no-pages`, `--force`.

## Install

```
npx skills add ctrlShiftBryan/skills -g --skill install-pr-explainer
```

## Usage

Ask Claude to "install / set up / add the pr-explainer action" from inside the target repo. Default `--target` is the current directory; pass it explicitly to install elsewhere. The installer is idempotent — re-running is safe; existing files are skipped unless `--force`.

It sets up:

1. `.github/workflows/pr-explainer.yml` + `.github/scripts/pr-explainer-check.sh` — the nag/gate. On PR events it computes the diff's stable `git patch-id` (`DIFF_ID`), checks the docs branch for a matching explainer, and upserts one sticky comment + one `pr-explainer` commit status: 🔴 none / 🟡 stale / 🟢 ready.
2. `scripts/explainer-publish.sh` (wired as the `explainer:publish` package script when a `package.json` exists) — pushes the generated HTML to the orphan `ai-docs` branch and re-runs the workflow from there so the PR flips green with no new commit.
3. `.github/prompts/explainer-generation.md` + `docs/pr-explainer.md`, an `<explainer-dir>/` entry in `.gitignore` (explainers live only on the docs branch), the bootstrapped orphan **ai-docs** branch (`.nojekyll`, landing page, empty explainer dir), and **GitHub Pages** (deploy-from-branch on `ai-docs`) with the resolved Pages URL substituted into `PAGES_BASE`.

The loop after install: commit + push on the base branch and open/refresh a PR → bot posts a 🔴 comment carrying the generation prompt + a failing status → run that prompt in Claude Code (writes `<explainer-dir>/<PR#>-<DIFF_ID>-explainer.html`) → run the publish command → ~30–60s later the comment flips 🟢.

## Requirements

- A git repo with a GitHub `origin` remote you can push to.
- `gh` CLI installed and authenticated (`gh auth status`) — needed to enable Pages and read its URL. Without it, pass `--no-pages --no-bootstrap` to degrade to a files-only install.
- GitHub Actions enabled with **read/write workflow permissions** (Settings → Actions → General). The workflow requests `pull-requests: write` + `statuses: write`; a read-only default makes the status post fail.
- GitHub Pages available on the repo's plan (private repos need a plan that supports Pages).
- `jq` (optional) — to add the `explainer:publish` script to an existing `package.json`.

If the Pages URL isn't live yet when the installer runs, `PAGES_BASE` is left unset — re-run the installer once Pages finishes provisioning, or set it from `gh api repos/:owner/:repo/pages --jq .html_url`.
