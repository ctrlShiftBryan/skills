---
name: codex-computer-use
description: Ask the Codex CLI to run local app verification that needs computer use, browser automation, simulators, screenshots, app launching, or independent runtime inspection. This is how Codex is invoked for computer-use work. The model Codex runs is named in the `picking-models` skill, where installed, else `~/.codex/config.toml`. Use when the user asks Claude to test a flow, verify UI behavior, inspect a running app, capture screenshots, or report confirmation and feedback about implemented behavior that benefits from computer use functionality.
---

# Codex Computer Use

Use Codex as a separate local verification agent when the task needs real UI interaction,
screenshots, simulator/browser/device state, or an independent runtime check outside Claude's
current context.

Do not use this for ordinary code reading, typechecking, linting, or tests Claude can run
directly. Launching apps, simulators, or browsers to verify the requested work is fine
without asking; ask first only if the run could disrupt the user's environment beyond that
(closing their apps, changing system settings, acting on real accounts or data).

## Workflow

1. Create a temporary artifact directory.
2. Give Codex a self-contained prompt with the repo path, exact flow, constraints, artifact
   directory, and report format.
3. Run `codex exec` non-interactively.
4. Read Codex's report, inspect or reference screenshot paths, and summarize the result for
   the user.

Use this command shape:

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-computer-use.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Write a self-contained prompt to $PROMPT, then run:
codex exec \
  -C "$PWD" \
  --add-dir "$ARTIFACT_DIR" \
  -s danger-full-access \
  -o "$REPORT" \
  "$(cat "$PROMPT")"
```

Use `-s danger-full-access` for GUI automation, iOS simulators, desktop app launching,
screenshots, or access outside the repo. For non-GUI checks that only need the repo and
artifact directory, prefer `-s workspace-write`. Add `--skip-git-repo-check` when the working
directory is not a git repository.

## Web Pages on macOS: Google Chrome Through getApp

Where Google Chrome.app is kept for computer use (no person uses it, and no other tool starts it), its Default profile is the agent's browser. Drive it as an app, not through the ChatGPT browser extension.

1. Stray check, before every run: `ps -axo pid,ppid,command | grep "Google Chrome.app/Contents/MacOS/Google Chrome"`. Every Google Chrome shares the app id `com.google.Chrome`, and a headless copy makes `getApp` hang (`-10005 timeoutReached`). Kill a Google Chrome only when it has `--headless` and its parent is gone (ppid 1). Never kill the Default-profile Chrome. Name any other Google Chrome with its own `--user-data-dir` in the report, and leave it running: a tool may own it.
   Also check `ls -d /Volumes/*/"Google Chrome.app"`: a still-mounted Chrome installer makes `getApp` fail with "Ambiguous app identifier". Eject it (`diskutil eject "/Volumes/Google Chrome"`) when nothing runs from it.
2. Open Chrome: `open -a "Google Chrome" --args --profile-directory=Default`.
3. Tell Codex, in the prompt:
   - Drive Chrome only through `getApp('com.google.Chrome')`. Do not use `getBrowser`, the extension, CDP, Playwright, AppleScript or a remote-debugging port.
   - Open the page in a new window (Cmd+N, then the URL), and close only that window at the end.
   - If `getApp` fails or times out, retry once after 10 seconds. Then fall back to Safari (`open -a Safari`, `getApp('com.apple.Safari')`) and say so at the top of the report.
4. Say in your summary which browser the run used.

Computer use sends clicks, single key presses, scrolling and a left-button drag. It cannot hold a key or a mouse button, so checks that need held input (WASD movement, right-drag, hold-to-fly) come back blocked. Check those another way, or by hand.

## Prompt Requirements

Tell Codex:

- The exact behavior to verify.
- The platform and app type, such as iOS, web, Electron, CLI, or desktop.
- Known launch commands, test credentials, seed data, deep links, or fixtures.
- Whether source edits are allowed. Default to no edits.
- Where screenshots, logs, and the final report should be saved.
- To return pass, fail, or blocked, plus steps performed, observed behavior, screenshot paths,
  and actionable feedback.

Keep the prompt specific enough that Codex does not need the surrounding Claude conversation.
