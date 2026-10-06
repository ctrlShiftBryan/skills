# ctrlshiftbryan-skills

Bryan's personal agent skills.

## Skills

Install with [skills.sh](https://skills.sh):

```
npx skills add ctrlShiftBryan/skills -g          # pick from a list
npx skills add ctrlShiftBryan/skills -g --all    # everything
```

| Folder | Skills | Description |
|---|---|---|
| [`review-address`](plugins/review-address) | skill | Reply to every PR review comment (GitHub Copilot, bots, humans) with code fixes or reasoned push-backs, committing and posting an inline reply to each. |
| [`pr-explainer`](plugins/pr-explainer) | skill | Install the AI PR-explainer GitHub Action into a repo — nag workflow + check/publish scripts, an orphan `ai-docs` branch, GitHub Pages, and a sticky 🔴/🟡/🟢 'explainer' comment + status gate linking an AI HTML walkthrough. |
| [`post-review-as-bot`](plugins/post-review-as-bot) | skill | Post a code review to a GitHub PR as inline comments attributed to a GitHub App `[bot]` account — mints an installation token, validates comments against the diff, submits one atomic review. |
| [`codex-delegation`](plugins/codex-delegation) | skills ×3 | Delegate work to Codex CLI (gpt-5.5) — `codex-implementation` (scoped changes via `codex exec`), `codex-review` (independent diff review), `codex-computer-use` (browser/simulator/screenshot verification). |
| [`questionnaire`](plugins/questionnaire) | skill | Batch 3+ clarifying questions into a local HTML form — recommended answers pre-checked, per-question comments, and a "Copy prompt" button that serializes everything into one paste-back prompt. |
| [`batch-grill-me-html`](plugins/batch-grill-me-html) | skill | Conduct a manual, dependency-aware design interview in HTML rounds — each form contains the complete current decision frontier, recommended answers, optional sandboxed HTML mockups for visual choices, and a paste-back prompt. |
| [`pre-batch-grill-me-html`](plugins/pre-batch-grill-me-html) | skill | Pre-generate a whole dependency-aware design interview as one all-rounds HTML form, with deviations locking downstream questions live. |
| [`worktrees`](plugins/worktrees) | skill | Bryan's git worktree conventions (`gw`/`gwct`/`gwb`/`gwl`) — sibling `<repo>-worktrees/<branch>` layout, create from main repo on main, remote-branch checkout with tracking, merged-only cleanup that also deletes the branch. |
| [`zoom-out`](plugins/zoom-out) | skill | Manually zoom out one abstraction level and map the relevant modules and callers using the project's domain glossary vocabulary. |
| [`copilot`](plugins/copilot) | skills ×3 | Delegate work to GitHub Copilot CLI (gpt-5.6-sol) — `copilot-implementation` (scoped changes via `copilot -p`), `copilot-review` (independent diff review), `copilot-adversarial-review` (challenge review attacking approach, design, and assumptions). |
| [`adversarial-review`](plugins/adversarial-review) | skill | Review the current branch against `main`, retrieve any open pull request with `gh`, and challenge the change's approach, design, tradeoffs, and assumptions. |

## Plugins (subagents only)

`npx skills` can't install subagents, so these ship as Claude Code plugins.

| Plugin | Components | Description |
|---|---|---|
| [`datadog-fetcher`](plugins/datadog-fetcher) | agent | Auto-delegating Haiku sub-agent that offloads Datadog MCP read calls (logs, metrics, monitors, traces, incidents, dashboards…) out of the main conversation, saving raw payloads to `tmp/datadog/` and returning a capped summary. Read-only. |

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install datadog-fetcher@ctrlshiftbryan-skills
```

## Layout

```
ctrlshiftbryan-skills/
├── .claude-plugin/
│   └── marketplace.json     ← plugin listing (subagents only)
├── claude/
│   ├── CLAUDE.md            ← versioned copy of my global ~/.claude/CLAUDE.md
│   ├── statusline.sh        ← custom status bar script (setup in claude/README.md)
│   └── README.md
└── plugins/
    ├── <name>/skills/<skill>/SKILL.md            ← skills (npx skills)
    └── datadog-fetcher/.claude-plugin/plugin.json ← the one plugin
```

## Adding a skill

1. Add `plugins/<name>/skills/<skill>/SKILL.md` (plus a short `plugins/<name>/README.md`).
2. Add a row to the Skills table above.
3. Check `npx skills@latest add ctrlShiftBryan/skills --list` finds it.

**Public skills only.** A skill that needs a specific app installed — its CLIs,
its server, its repo layout — belongs in that app's own repo, not here. Example:
the `bm-*` browser-mux skills live in the private `ctrlShiftBryan/browser-mux`
repo under `skills/` and install with `npx skills add` from there.
