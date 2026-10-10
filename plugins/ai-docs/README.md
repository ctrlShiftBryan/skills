# ai-docs

Turns a GitHub repo's `ai-docs` branch into a team knowledge base for AI-generated docs: plans, explainers, incident write-ups, investigation notes, research and UI prototypes. Generated docs stay out of code branches.

## Components

- `install-ai-docs`: a skill you invoke by hand. Its installer (`scripts/install.sh`) does the following:
  - creates or adopts an orphan `ai-docs` branch;
  - adds an `ai-docs protection` ruleset (no deletion, no force-push; admins bypass);
  - turns on GitHub Pages when the site can stay private (or when the repo is public), and stops to ask otherwise;
  - vendors a repo-local `ai-docs` skill plus its publish script into `.claude/skills/ai-docs/`;
  - writes `.ai-docs.json`, gitignores `/ai-docs/`, and adds a `package.json` alias;
  - adds a "Generated docs" rule to AGENTS.md/CLAUDE.md (CLAUDE.md imports `@AGENTS.md`) and to `.github/copilot-instructions.md`.
- The vendored `ai-docs` skill fires on its own for any generated doc. Its publish script:
  - scans for secrets;
  - pushes from a throwaway worktree, retrying if a teammate pushed first;
  - rebuilds a searchable `index.html`;
  - opens the doc locally and deletes the staged copy.

It works alongside [`pr-explainer`](../pr-explainer): both use the same branch, and whichever is installed second adopts it.

## Install

```
npx skills add ctrlShiftBryan/skills -g --skill install-ai-docs
```

## Usage

From the target repo, ask Claude to "install ai-docs" or "set up ai-docs". It runs `install.sh --dry-run`, agrees on Pages, allowed doc paths and docs to migrate with you, runs the install, and leaves the file changes for you to commit.

## Verify

```
bash scripts/verify-ai-docs.sh            # SKIP_LIVE=1 skips the read-only dry-run against dynasty-nerds-monorepo
```
