# ralph

Install and run the [Ralph Wiggum](https://www.aihero.dev/getting-started-with-ralph) agentic loop (`claude` or `codex`) in any project. The install command scaffolds `ralph/once.sh` + `ralph/afk.sh`, `package.json` scripts, and the prompt/state-file files; the loop runs the agent CLI against `PROMPT.md` over and over until it emits `<promise>COMPLETE</promise>`, hits a `--max` cap, or you Ctrl-C — opening a draft PR on clean completion.

## Components

- `/ralph:install` — drop the Ralph scaffolding into the current project (`ralph/` scripts, `PROMPT.md`, `AGENT.md`, `fix_plan.md`, `progress.md`, `specs/README.md`, `.gitignore` + `package.json` script entries). Idempotent; `--force` overwrites.
- `/ralph:once` — run a single Ralph iteration (HITL) against `PROMPT.md`. No looping, branch, or PR. Use it to tune the prompt before going AFK.
- `/ralph:afk` — start the AFK loop. Runs until COMPLETE / `--max N` / Ctrl-C; pushes the branch and opens a draft PR on COMPLETE.
- `install-ralph` (skill) — natural-language trigger for the install ("install ralph", "set up an AFK loop"); invokes the install script.
- `ralph-runner` (agent) — subagent that runs `once.sh`/`afk.sh` on the parent's behalf and returns a terse summary (iterations, items checked, PR URL, blockers) instead of flooding context with the full transcript.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install ralph@ctrlshiftbryan-skills
```

## Usage

```
# 1. Scaffold Ralph into the current project
/ralph:install
/ralph:install --branch ralph/work --base main --force

# 2. Fill in AGENT.md (build/test/lint), fix_plan.md (work items), specs/*.md (definition of done)

# 3. Kick the tires — one iteration, eyeball output, refine PROMPT.md
/ralph:once
bun run ralph:once

# 4. Go AFK
/ralph:afk                          # claude, infinite, Ctrl-C to stop
/ralph:afk --engine codex --max 30  # codex, capped at 30
bun run ralph

# Watch logs (afk tees each loop to ralph/.state/loop-NNN.log)
tail -f ralph/.state/loop-*.log
```

**afk.sh flags:** `--engine claude|codex` (default `claude`), `--max N` (default `0` = unlimited), `--branch` (default `ralph/work`), `--base` (default `main`), `--sleep N` (default `2`).

## Notes / requirements

- **Permission bypass by design** — Ralph runs the agent CLI with `claude --dangerously-skip-permissions` / `codex exec --dangerously-bypass-approvals-and-sandbox`. No Docker sandbox, no `acceptEdits`. This is intentional; if you want the safer mode, follow the article's `docker sandbox run claude` recommendation instead.
- **macOS-oriented** — `ralph/notify.sh` uses `terminal-notifier` (`brew install terminal-notifier`); the bell + notifier are mac-specific.
- **Requires** the `claude` and/or `codex` CLI logged in, and `gh` logged in (`gh auth status`) for the draft-PR step on COMPLETE.
- `/ralph:install` uses `jq` to merge `package.json` scripts; if `jq` is missing on an existing `package.json`, it prints the two lines to add manually.
- After install, fill in `AGENT.md`, `fix_plan.md`, and `specs/*.md` before running — they ship with TODO markers.
