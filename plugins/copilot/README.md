# copilot

Delegate work from Claude Code to GitHub Copilot CLI (gpt-5.6-sol). Three skills cover the delegation surface — implementation, review, and adversarial review — each running Copilot non-interactively (`copilot -p`) with a self-contained prompt and reading back a report, with Claude staying responsible for scoping, verifying, and presenting the result.

## Components

- **`implementation`** (skill) — Hand a bounded code change to `copilot -p` with commit/push denied, then inspect the resulting diff and run verification before reporting done.
- **`review`** (skill) — Get an independent review of uncommitted changes, a branch diff, or a commit; writes denied so the review stays read-only. Claude verifies findings against the code before relaying them.
- **`copilot-adversarial-review`** (skill) — A challenge review that attacks the approach, design choices, tradeoffs, and assumptions, returning a ship/no-ship markdown verdict with severity, confidence, and file:line findings.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install copilot@ctrlshiftbryan-skills
```

## Usage

Triggers on natural-language phrases such as:

- "use copilot to implement X" / "delegate this to copilot"
- "have copilot review my changes" / "get a copilot review of this branch"
- "copilot adversarial review" / "have copilot try to break this" / "should this ship?"

## Notes / Requirements

- Requires the `copilot` CLI installed and logged in (`copilot --version` succeeds).
- All skills run Copilot **non-interactively** with `--allow-all-tools`; `--deny-tool` rules take precedence and provide the guardrails (reviews deny `write`; implementation denies `git commit`/`git push`).
- Copilot has no review subcommand — the review target is a git command named in the prompt (`git diff HEAD`, merge-base triple-dot, `git show <sha>`, or specific paths).
- All skills pin `--model gpt-5.6-sol` and `--session-id` so transcripts stay findable under `~/.copilot/session-state/`.
- Claude treats Copilot output as evidence, not authority — diffs are inspected and review findings verified (adversarial findings labeled confirmed vs unverified) before being reported.
