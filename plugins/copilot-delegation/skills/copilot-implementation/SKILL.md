---
name: copilot-implementation
description: Ask GitHub Copilot CLI (gpt-5.6-sol) to implement scoped code changes in the current repository, then have Claude inspect the resulting diff and verification. This is how Copilot is invoked for implementation work. Use when the user asks Claude to delegate implementation to Copilot, when a third coding agent's patch is wanted alongside or instead of Codex, or when a bounded task would benefit from another agent producing the change.
---

# Copilot Implementation

Use GitHub Copilot CLI as a separate implementation agent for bounded code changes. Claude
stays responsible for scoping the task, reviewing the diff, running or checking
verification, and explaining the final result.

Use this when the user asks for Copilot or delegation, or when a bounded task would
benefit from a parallel implementation agent producing a patch. Do not let Copilot commit,
push, deploy, or edit global config unless the user explicitly asked for that.

## Preconditions

- `copilot` must be on `PATH` and logged in (`copilot --version` succeeds).
- Non-interactive mode **requires** `--allow-all-tools`; `copilot -p` refuses to run
  without it.
- Copilot will not touch a folder it has not been told to trust. In an interactive session
  it opens a blocking trust modal; give it the working directory with `-C "$PWD"` and run
  from inside the repository.
- File access is confined to the working directory and the system temp directory unless
  `--allow-all-paths` is passed. Leave that off: the confinement is the safety rail.

## Workflow

1. Pin the current state with `git status --short` and note any user changes already
   present.
2. Define the implementation scope: files or behavior to change, files to avoid,
   constraints, and verification commands.
3. Create a temporary artifact directory for the prompt and report.
4. Run `copilot -p` from the repository root.
5. After Copilot exits, inspect `git status` and `git diff`.
6. Run the cheapest reliable verification yourself when practical.
7. Report what Copilot changed, what Claude verified, and any remaining risks.

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-implementation.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
SESSION_ID="$(uuidgen)"

# ... write a self-contained prompt to "$PROMPT" first ...

copilot -p "$(cat "$PROMPT")" \
  -C "$PWD" \
  --model gpt-5.6-sol \
  --session-id "$SESSION_ID" \
  --allow-all-tools \
  --deny-tool 'shell(git commit)' \
  --deny-tool 'shell(git push)' \
  --no-ask-user \
  -s > "$REPORT"
```

- `--deny-tool` denials take precedence over `--allow-all-tools`, so the git guardrails
  hold even in fully permissive mode. Add more (`shell(gh:*)`, `write(/absolute/path)`)
  when a task has specific no-go areas.
- `--no-ask-user` keeps Copilot from parking on a clarifying question nobody is there to
  answer; it will make a decision and say so instead.
- `--session-id` pins the session so its transcript stays findable at
  `~/.copilot/session-state/$SESSION_ID/events.jsonl`, and so a follow-up run can resume it
  with `copilot -r "$SESSION_ID"`.
- Add `--share "$ARTIFACT_DIR/session.md"` for a full markdown session log.

## Prompt requirements

Tell Copilot:

- The exact implementation goal and acceptance criteria.
- The repo path and current branch context if relevant.
- Which existing patterns, files, or tests to inspect first.
- Files or behavior that must not be changed.
- That it must preserve unrelated user changes.
- That it must not commit, push, deploy, or edit global config.
- Which verification commands to run, or to explain why they were skipped.
- To write a concise final report with files changed, verification, and unresolved
  questions.

Keep the task bounded. If the requested work bundles several substantial changes, split it
into separate runs or ask the user to choose the first scope.

## Example prompt

```text
You are implementing a scoped change on behalf of another agent.

Repository: /absolute/path/to/repo
Artifact directory: /tmp/copilot-implementation.XXXXXX

Goal:
- Add keyboard navigation to the command palette.

Acceptance criteria:
- ArrowUp and ArrowDown move the highlighted item.
- Enter selects the highlighted item.
- Escape closes the palette.
- Existing mouse behavior keeps working.

Constraints:
- Preserve unrelated user changes.
- Do not commit, push, deploy, or edit global config.
- Follow the existing component and test patterns in this repository.

Verification:
- Run the focused component tests if available.
- Otherwise run the nearest relevant typecheck or test command and explain the choice.

Report:
- Files changed
- Behavioral summary
- Verification run and result
- Anything blocked or uncertain
```

## Review after Copilot

Always inspect the diff before telling the user the work is done. Revert only
Copilot-created mistakes, and only when you are sure they are not user changes. If Copilot
leaves the repo in a worse state or touches unrelated files, stop and report the issue with
a diff summary.

Copilot reads project instruction files (`AGENTS.md` and friends) unless
`--no-custom-instructions` is passed, and it discovers skills from `.github/skills`,
`.agents/skills`, `.claude/skills`, and `~/.agents/skills`. It therefore inherits
repository conventions — and any Claude-authored personal skills — by default. Say so if a
result looks like it came from an instruction you did not write.

If `copilot` is missing or the command fails, report the error and offer to implement the
change directly instead.
