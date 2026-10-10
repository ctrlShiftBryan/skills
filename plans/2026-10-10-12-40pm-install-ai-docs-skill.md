# Plan: install-ai-docs skill

## Goal

A reusable, manual-only installer skill that sets up any GitHub repo with an `ai-docs` branch. That branch is a knowledge base for generated docs (plans, explainers, incident write-ups, investigations, research and prototypes). The installer also sets up the branch's protections, optional GitHub Pages, and a repo-local `ai-docs` skill that publishes to the branch without asking. The dynasty-nerds-monorepo version (PR #734) is the reference implementation, made generic.

## Context and assumptions

- Lives in `ctrlShiftBryan/skills` at `plugins/ai-docs/skills/install-ai-docs/`. Installed with `npx skills`, with no plugin manifest.
- Lands straight on `main` once `scripts/verify-ai-docs.sh` passes (trunk rule).
- Separate from `install-pr-explainer`. Each one adopts an `ai-docs` branch or Pages site the other already created. PR explainers keep their own flow and folder.
- Node is a prerequisite in target repos.

## Steps

1. **Scaffold the skill.** Add `plugins/ai-docs/README.md`, `SKILL.md` (manual-only trigger), `scripts/install.sh`, and the templates under `assets/`.
2. **Vendored repo skill (`assets/ai-docs/`).** Generalize the monorepo SKILL.md, `ai-docs-publish.sh` and `ai-docs.mjs`:
   - The scripts read `.ai-docs.json` (branch, repo slug, Pages URL or none, types, allowed paths) instead of hardcoded constants.
   - Keep these features: publish from a throwaway worktree with a retry when a push loses a race, the secret scan with `--allow-secrets`, the index rebuild, opening the doc locally (bm-open, else the system opener), deleting the staged copy (`--keep` to retain it), and `--rm`.
   - Remove dynasty-specific wording such as Key Vault.
   - Without Pages, the reply links docs to GitHub's file view.
   - Default types: plans, incidents, investigations, research, explainers, prototypes.
3. **Installer (`install.sh`).** Idempotent, with `--dry-run`, `--target` and `--force`.
   - Preflight: git repo, GitHub origin, push access, `gh auth`, node, repo visibility and plan.
   - Show a summary of the remote changes and ask for confirmation before making them.
   - Copy `assets/ai-docs/` to `.claude/skills/ai-docs/` and write `.ai-docs.json`. Add a `package.json` script alias if the repo has a `package.json`.
   - Add `/ai-docs/` to `.gitignore`.
   - Create the orphan `ai-docs` branch (`.nojekyll`, index, empty type folders), or adopt the existing one.
   - Pages: enable it from the `ai-docs` branch. If the repo is private and Pages would be public, stop and ask, with no Pages as the default.
   - Ruleset on `ai-docs`: block deletion and force-push, admins can bypass. Skip it with a warning when the plan doesn't support rulesets.
4. **Agent instructions.** Add a marker-delimited "Generated docs" section, updated in place on re-runs:
   - Write it to AGENTS.md if that exists, else to CLAUDE.md. If neither exists, create AGENTS.md plus a CLAUDE.md containing `@AGENTS.md`.
   - When AGENTS.md is used, make sure CLAUDE.md imports `@AGENTS.md`, creating CLAUDE.md or adding the line if needed.
   - Also add the review rule to `.github/copilot-instructions.md`.
5. **Allowed paths and migration (done by the agent, guided by SKILL.md).**
   - Scan the repo and propose an allowed-paths list built from the generic baseline. The user confirms it, and it goes into `.ai-docs.json` and the rule text.
   - List stray generated docs. Move only the ones the user confirms: publish each one, then `git rm` it.
6. **Finish.** Leave all target-repo file changes uncommitted, and print next steps.
7. **Verify (`scripts/verify-ai-docs.sh`).**
   - shellcheck and frontmatter checks.
   - An installer matrix against throwaway repos with a local bare remote. It covers fresh install, re-run, adopting an existing branch, the AGENTS/CLAUDE combinations, no `package.json`, and publish, race, `--rm` and secret-scan cases.
   - A read-only `--dry-run` against dynasty-nerds-monorepo.
8. **Docs and land.** Add a README row, check `npx skills@latest add ctrlShiftBryan/skills --list`, then commit and push to `main`.

## Out of scope

- No CI or pre-commit guard.
- dynasty-nerds-monorepo is not migrated; it only gets the dry-run.
- No changes to install-pr-explainer.
- No live run on a real GitHub repo.

## Expected outcome

Running `install-ai-docs` in a new repo gives it a protected `ai-docs` branch, optional private Pages, and a repo skill. Agents then publish generated docs to that branch automatically. Code review flags stray docs on code branches.
