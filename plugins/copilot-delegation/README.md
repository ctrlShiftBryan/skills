# copilot-delegation

Delegate work from Claude Code to GitHub Copilot CLI. Two skills: `copilot-implementation` (a scoped change, which Claude then inspects and verifies) and `copilot-review` (an independent review of a diff, branch or commit).

## Install

```
npx skills add ctrlShiftBryan/skills -g --skill copilot-implementation copilot-review
```

## Requirements

The `copilot` CLI, installed and signed in.
