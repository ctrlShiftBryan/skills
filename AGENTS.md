# Repository Rules

## Adding Skills

When adding a skill under `plugins/<plugin>/skills/`, always complete the plugin packaging in the same change:

- Create or update `plugins/<plugin>/.claude-plugin/plugin.json`.
- Add or update the plugin entry in `.claude-plugin/marketplace.json`.
- Add or update the plugin in the root `README.md` plugin table.
- Verify `npx skills@latest add ctrlShiftBryan/skills --list` discovers the new skill without `--full-depth`.

Do not consider a new skill complete until all four checks pass.
