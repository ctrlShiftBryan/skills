# Repository Rules

## Adding Skills

Skills install with `npx skills`, not the Claude Code plugin system. When adding a skill:

- Put it at `plugins/<name>/skills/<skill>/SKILL.md`. Give it a distinctive `name` (installs flat into `~/.claude/skills/`, so avoid generic names like `review`).
- Add or update the row in the root `README.md` Skills table.
- Verify `npx skills@latest add ctrlShiftBryan/skills --list` discovers the new skill without `--full-depth`.

Do not add `.claude-plugin/plugin.json` or a `marketplace.json` entry for skills. Plugins are only for things `npx skills` can't install (subagents, e.g. `datadog-fetcher`).
