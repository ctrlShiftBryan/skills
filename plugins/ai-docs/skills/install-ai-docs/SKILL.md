---
name: install-ai-docs
description: Set up a GitHub repo with an ai-docs knowledge-base branch. It creates or adopts an orphan ai-docs branch, protects it with a ruleset, turns on GitHub Pages when the site can stay private, and vendors a repo-local ai-docs skill that publishes generated plans, explainers, incident write-ups, investigations, research and prototypes there without asking. It also adds the generated-docs rule to AGENTS.md/CLAUDE.md and Copilot review. Manual only - use it only when the user asks to install, set up or add ai-docs in a repo.
---

# Install ai-docs

This skill changes the user's GitHub repo: it pushes a branch, changes Pages settings and adds a ruleset. Run it only when the user asks for it.

`<skill-dir>` below is this skill's base directory, the folder that holds this SKILL.md. The installer finds its templates relative to itself.

## 1. Dry run

```bash
bash "<skill-dir>/scripts/install.sh" --target <repo> --dry-run
```

The dry run makes GET calls only and writes nothing. It prints the plan:

- **branch:** create the orphan branch, or adopt one that already exists (`install-pr-explainer` makes the same branch).
- **pages:** adopt, create (private or public), skip, or `DECISION NEEDED`.
- **ruleset:** create or update `ai-docs protection`, or skip with a reason.
- **files:** each file it would create or update.
- **scan:** tracked `.md`/`.html` files outside the allowed doc paths, grouped by directory.

Prerequisites: git, node, and an authenticated `gh` with push access. Pages and the ruleset also need repo admin; without it, the installer skips them and says why.

## 2. Settle the plan with the user

Show the user the plan. Get a decision on each of these:

- **Remote changes:** the branch push, Pages and the ruleset. Get an explicit yes.
- **Pages, when the plan says `DECISION NEEDED`:** a Pages site for this private repo would be public on the internet. Access-controlled Pages needs an org on GitHub Enterprise Cloud. Recommend `--pages off`, which keeps the docs on GitHub with no site. `--pages on` publishes the site publicly.
- **Allowed paths:** go through each directory in the scan. If it holds real repo docs, such as runbooks or an app's `docs/` folder, add it with `--allow-path <dir>/`. Otherwise it holds generated docs and becomes a migration candidate (step 4).

This step is done when the user has approved the remote changes and has a decision for Pages and for every directory in the scan.

## 3. Install

```bash
bash "<skill-dir>/scripts/install.sh" --target <repo> [--pages on|off] [--allow-path <dir>/ ...]
```

Exit code 3 means Pages needs a decision and nothing was changed: go back to step 2. Re-running is safe. Settings live in `.ai-docs.json`, and each run regenerates the vendored `.claude/skills/ai-docs/` folder and the marked instruction sections from that file.

`--branch <name>` installs onto a branch other than `ai-docs`. `--no-github` skips every GitHub API call.

## 4. Migrate the generated docs the user picked

For each file the user chose to move:

1. Copy it to `ai-docs/<type>/<YYYY-MM-DD>-<slug>.<html|md>`. The type comes from the types table in the vendored SKILL.md. The date is the file's first commit date (`git log --diff-filter=A --format=%as -1 -- <file>`).
2. Publish all the copies in one run with the publish command the installer printed.
3. `git rm` the originals. Point any link or code comment that referenced a moved file at its new URL.

This step is done when every chosen file is on the branch and `git rm`'d.

## 5. Hand over

The installer leaves its files uncommitted. Tell the user:

- which files it created or changed, and that they still need committing;
- the Pages URL, or that links go to GitHub;
- the ruleset result, or why it was skipped;
- which docs moved;
- that agent sessions already running need a restart to load the new skill.
