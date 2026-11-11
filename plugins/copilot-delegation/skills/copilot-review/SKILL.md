---
name: copilot-review
description: Ask GitHub Copilot CLI (gpt-5.6-sol) for an independent code review of uncommitted changes, a branch diff, a commit, or a specific implementation. This is how Copilot is invoked for review work. Use when the user asks Claude to have Copilot review work, when a third-model perspective is wanted alongside or instead of Codex, or when Copilot should audit a diff, find bugs or regressions, or compare an implementation against requirements. For a review by Claude itself, use the normal review process instead.
---

# Copilot Review

Use GitHub Copilot CLI as an independent reviewer when the user wants a second-pass
review, or when a change is broad enough that another agent's perspective is useful.

Prefer Claude's normal review process for small local checks. Do not delegate review just
to avoid reading the code yourself. Treat Copilot's output as evidence, not authority.

## Preconditions

- `copilot` must be on `PATH` and logged in (`copilot --version` succeeds).
- Copilot has **no review subcommand**. Unlike `codex review`, there is no
  `--uncommitted` or `--base` flag: the diff has to be put in front of it, either by
  telling it which git command to run or by writing the diff into the prompt.
- Non-interactive mode **requires** `--allow-all-tools`; `copilot -p` refuses to run
  without it. Denial rules take precedence over it, which is how the review stays
  read-only.

## Workflow

1. Identify the review target: uncommitted changes, a base branch, a commit SHA, a PR
   checkout, or specific files.
2. Create a temporary artifact directory for the prompt and report.
3. Write the review prompt, naming the exact diff command Copilot should run.
4. Run `copilot -p` with writes denied.
5. Read the report and verify important claims against the code before presenting them.

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-review.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
SESSION_ID="$(uuidgen)"

# ... write the review prompt to "$PROMPT" first ...

copilot -p "$(cat "$PROMPT")" \
  -C "$PWD" \
  --model gpt-5.6-sol \
  --session-id "$SESSION_ID" \
  --allow-all-tools \
  --deny-tool 'write' \
  --no-ask-user \
  -s > "$REPORT"
```

- `--deny-tool 'write'` blocks every file-creating and file-modifying tool. Denials beat
  `--allow-all-tools`, so the review can read, grep, and run git without being able to
  edit the tree. It does **not** block shell redirection, so the prompt must also say not
  to write files.
- `--no-ask-user` stops Copilot parking on a clarifying question with nobody there to
  answer it.
- `-s` (silent) prints only the agent's answer, which is what belongs in the report.
- `--session-id` pins the session so the transcript is findable afterwards at
  `~/.copilot/session-state/$SESSION_ID/events.jsonl`.
- Add `--share "$ARTIFACT_DIR/session.md"` when a full markdown session log is wanted
  alongside the answer.

## Review prompt

Name the diff explicitly — Copilot will not guess the review target:

```text
Review the changes produced by `git diff HEAD` in this repository.

Run the diff yourself, read the surrounding code for context, and review for bugs,
regressions, missing tests, security issues, and requirement mismatches.

Prioritize findings over summary. For each finding include:
- severity
- file and line reference
- concrete failure mode
- suggested fix direction

Do not edit, create, or delete any file, and do not write output anywhere except your
final answer. If there are no substantive findings, say so and name any residual test
gaps.
```

Swap the diff command for the target:

| Target | Command to name in the prompt |
| --- | --- |
| Staged + unstaged | `git diff HEAD` |
| Branch vs base | `git diff $(git merge-base main HEAD)...HEAD` |
| A single commit | `git show <sha>` |
| Specific files | `git diff HEAD -- <paths>` |

Untracked files do not appear in `git diff`; when they matter, list them in the prompt
(`git status --short`) and ask Copilot to read them.

Add task-specific context when useful: requirements, risky areas, expected behavior,
relevant tests, or files you are unsure about.

## Reporting back

Before relaying a Copilot finding, inspect the cited code or diff enough to decide whether
the finding is real. In the user-facing response, separate confirmed issues from
suggestions you did not verify.

Confirm the tree is unchanged (`git status --short`) before reporting — a review must not
leave edits behind.

If Copilot finds nothing, say so clearly and name the review target it inspected.

If `copilot` is missing or the command fails, report the error and offer to review the
changes directly instead.

## Cost

`gpt-5.6-sol` is the most expensive tier of the 5.6 line. Copilot reports the session's AI
credit spend in the `-s` footer's absence via `~/.copilot/session-state/$SESSION_ID/events.jsonl`
(`session.usage_checkpoint` → `totalNanoAiu`). Mention the cost only if the user asks.
