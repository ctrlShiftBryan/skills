# codex-delegation

Delegate work from Claude Code to the Codex CLI (gpt-5.5). Three skills cover the delegation surface — implementation, review, and computer-use verification — each running Codex non-interactively with a self-contained prompt and reading back a report, with Claude staying responsible for scoping, verifying, and presenting the result.

## Components

- **`codex-implementation`** (skill) — Hand a bounded code change to `codex exec` with repo write access, then inspect the resulting diff and run verification before reporting done.
- **`codex-review`** (skill) — Get an independent review of uncommitted changes, a branch diff, or a commit via `codex review`; Claude verifies findings against the code before relaying them.
- **`codex-computer-use`** (skill) — Have Codex verify runtime behavior that needs real UI interaction — browsers, iOS simulators, app launching, screenshots — via `codex exec -s danger-full-access`, returning pass/fail plus screenshot paths.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install codex-delegation@ctrlshiftbryan-skills
```

## Usage

Triggers on natural-language phrases such as:

- "use codex to implement X" / "delegate this to gpt-5.5"
- "have codex review my changes" / "get a gpt-5.5 review of this branch"
- "have codex test the login flow in the simulator" / "verify this in the browser"

## Notes / Requirements

- Requires the `codex` CLI installed and authenticated (`~/.codex/config.toml` sets the model; mine defaults to gpt-5.5).
- All three skills run Codex **non-interactively** with a self-contained prompt written to a temp artifact dir; the report is read back from a file.
- Sandbox levels: review is read-only, implementation uses `-s workspace-write`, computer-use escalates to `-s danger-full-access` only when GUI/simulator/off-repo access is genuinely needed.
- Codex is never allowed to commit, push, deploy, or edit global config unless explicitly requested.
- Claude treats Codex output as evidence, not authority — diffs are inspected and review findings verified before being reported to the user.
