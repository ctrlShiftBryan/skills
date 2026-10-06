# Drop plugin packaging, go npx-skills-only

## Context
- Bryan installs almost everything via `npx skills add ctrlShiftBryan/skills`.
- Plugin method currently used on this machine only for: `codex-delegation`, `copilot`, `datadog-fetcher`.
- `npx skills` only installs skills (SKILL.md folders). It can't install subagents or slash commands.
- `datadog-fetcher` is a subagent only (no skill) → can't move to npx skills as-is.
- `pr-explainer` has a `/pr-explainer:install` command, but its `install-pr-explainer` skill does the same job.

## Steps
1. Delete every `plugins/*/.claude-plugin/plugin.json` and `commands/` dir, except `datadog-fetcher`.
2. Trim `.claude-plugin/marketplace.json` to just `datadog-fetcher`.
3. Rewrite README: install = `npx skills add ctrlShiftBryan/skills`; datadog-fetcher = the one plugin exception.
4. Rewrite AGENTS.md "Adding Skills" rules: no plugin.json / marketplace entry needed for skills.
5. Verify `npx skills@latest add ctrlShiftBryan/skills --list` still finds every skill.
6. On each machine: `/plugin uninstall codex-delegation@ctrlshiftbryan-skills` and `copilot@…`, then `npx skills add` those skills.

## Optional follow-up
- Flatten `plugins/<name>/skills/<skill>/` → `skills/<skill>/`. Simpler tree; not required.

## Expected outcome
- One install method for skills. Plugin system kept only for the single subagent.
