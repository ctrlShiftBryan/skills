# manual-chrome-review

Verify a running web app feature in a real Chrome session by combining the user's keyboard/mouse/eyes with Claude-driven inspection of DOM, network, WebSocket frames, and server-side state. Runs a `propose → execute → inspect` loop: Claude proposes a concrete test, the user performs the action in their tab, and Claude immediately checks the resulting state via `evaluate_script`, network logs, WebSocket frames, and file reads — confirming or falsifying the invariant. Earns its keep on UI-affecting changes where human perception or human-speed input matters.

## Components

- **`manual-chrome-review`** (skill) — Workflow for live-browser feature verification: prerequisites, session setup, Claude/user split of labor, inspection recipes (DOM state, computed style, key-event timing, bundle-served checks, network requests), mid-cycle GitHub issue capture, pitfalls, and cleanup.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install manual-chrome-review@ctrlshiftbryan-skills
```

## Usage

Trigger by natural language while a web feature is ready to verify by hand:

- "manual chrome review"
- "verify in browser" / "let's manually test this"
- "walk through my app in chrome"
- "live browser review" / "review the new feature"

## Requirements

- Chrome launched with remote debugging: `open -a "Google Chrome" --args --remote-debugging-port=9222` (verify with `curl -sf http://127.0.0.1:9222/json/version`).
- `chrome-devtools` CLI on PATH (`npm install -g chrome-devtools-mcp`).
- The `monitor-active-chrome` skill installed — provides the three-layer capture stack (WebSocket frames to `.chrome-monitor/ws-frames.jsonl`, console buffer at `window.__consoleLogs`, network requests).
- `gh` authenticated, for filing issues when real bugs surface mid-cycle.

## When not to use

- Pure unit-testable invariants → write a unit test.
- Pure server-side concerns → `curl` + filesystem inspection.
- Headless-reproducible scenarios → port to a Playwright/Cypress test in CI.
