# copilot

Delegate work from Claude Code to GitHub Copilot CLI (gpt-5.6-sol). This repo holds the adversarial-review skill, which runs Copilot non-interactively (`copilot -p`) with a self-contained prompt and reads back a report, with Claude staying responsible for scoping, verifying, and presenting the result.

## Components

- **`copilot-adversarial-review`** (skill) — A challenge review that attacks the approach, design choices, tradeoffs, and assumptions, returning a ship/no-ship markdown verdict with severity, confidence, and file:line findings.

`copilot-implementation` and `copilot-review` live in `ctrlShiftBryan/browser-mux` (`npx skills add ctrlShiftBryan/browser-mux -g --skill copilot-implementation copilot-review`).

## Install

```
npx skills add ctrlShiftBryan/skills -g --skill copilot-adversarial-review
```

## Usage

Triggers on natural-language phrases such as:

- "copilot adversarial review" / "have copilot try to break this" / "should this ship?"

## Notes / Requirements

- Requires the `copilot` CLI installed and logged in (`copilot --version` succeeds).
- Runs Copilot **non-interactively** with `--allow-all-tools`; `--deny-tool write` keeps the review read-only.
- Copilot has no review subcommand — the review target is a git command named in the prompt (`git diff HEAD`, merge-base triple-dot, `git show <sha>`, or specific paths).
- Pins `--model gpt-5.6-sol` and `--session-id` so transcripts stay findable under `~/.copilot/session-state/`.
- Claude treats Copilot output as evidence, not authority — findings are labeled confirmed vs unverified before being reported.
