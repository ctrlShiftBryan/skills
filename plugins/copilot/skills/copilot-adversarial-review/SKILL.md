---
name: copilot-adversarial-review
description: Ask GitHub Copilot CLI (gpt-5.6-sol) for an adversarial review that challenges the implementation approach, design choices, tradeoffs, and assumptions of uncommitted changes, a branch diff, or a commit. Use when the user wants a challenge review, a skeptical second opinion, a "try to break this" pass, or asks whether a change should ship — not just a defect scan. For a normal independent review, use the copilot-review skill instead.
---

# Copilot Adversarial Review

Run GitHub Copilot CLI as an adversarial reviewer whose job is to break confidence in a
change, not validate it. This challenges the chosen approach, design choices, and
assumptions — it is not just a stricter pass over implementation defects.

This skill is review-only. Do not fix issues, apply patches, or suggest you are about to
make changes. Run the review, verify what you can, and report.

## Preconditions

- `copilot` must be on `PATH` and logged in (`copilot --version` succeeds).
- Copilot has **no review subcommand**: the diff is named in the prompt as a git command
  Copilot runs itself.
- Non-interactive mode **requires** `--allow-all-tools`; denial rules take precedence over
  it, which is how the review stays read-only.

## Workflow

1. Identify the review target: uncommitted changes, a base branch, a commit SHA, a PR
   checkout, or specific files. Capture any user focus text.
2. Create a temporary artifact directory for the prompt and report.
3. Write the adversarial prompt (template below), naming the exact diff command.
4. Run `copilot -p` with writes denied.
5. Read the report, verify findings against the code, and present the result.

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-adversarial-review.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
SESSION_ID="$(uuidgen)"

# ... write the adversarial prompt to "$PROMPT" first ...

copilot -p "$(cat "$PROMPT")" \
  -C "$PWD" \
  --model gpt-5.6-sol \
  --session-id "$SESSION_ID" \
  --allow-all-tools \
  --deny-tool 'write' \
  --no-ask-user \
  -s > "$REPORT"
```

- `--deny-tool 'write'` blocks file-creating and file-modifying tools; denials beat
  `--allow-all-tools`. It does not block shell redirection, so the prompt must also say
  not to write files.
- `--no-ask-user` stops Copilot parking on a clarifying question with nobody there.
- `-s` prints only the agent's answer, which is the report.
- `--session-id` keeps the transcript findable at
  `~/.copilot/session-state/$SESSION_ID/events.jsonl`.

## Review targets

Name the diff explicitly — Copilot will not guess:

| Target | Command to name in the prompt |
| --- | --- |
| Staged + unstaged | `git diff HEAD` |
| Branch vs base | `git diff $(git merge-base main HEAD)...HEAD` |
| A single commit | `git show <sha>` |
| Specific files | `git diff HEAD -- <paths>` |

Untracked files do not appear in `git diff`; when they matter, list them in the prompt
(`git status --short`) and ask Copilot to read them.

## Adversarial prompt

Substitute the target command, a one-line target label, and the user's focus text (or
"none"). Do not weaken the adversarial framing or rewrite the user's focus.

```text
You are performing an adversarial software review. Your job is to break confidence in
this change, not to validate it.

Target: <target label>. Run `<diff command>` yourself and read the surrounding code for
context. User focus: <focus text or "none">.

Operating stance:
- Default to skepticism. Assume the change can fail in subtle, high-cost, or
  user-visible ways until the evidence says otherwise.
- Challenge the chosen approach and design, not just the code: is this the right way to
  do it, what assumptions does it depend on, and where does the design fail under
  real-world conditions?
- Give no credit for good intent, partial fixes, or likely follow-up work. If something
  only works on the happy path, that is a real weakness.

Attack surface — prioritize failures that are expensive, dangerous, or hard to detect:
- auth, permissions, tenant isolation, and trust boundaries
- data loss, corruption, duplication, and irreversible state changes
- rollback safety, retries, partial failure, and idempotency gaps
- race conditions, ordering assumptions, stale state, and re-entrancy
- empty-state, null, timeout, and degraded dependency behavior
- version skew, schema drift, migration hazards, and compatibility regressions
- observability gaps that would hide failure or make recovery harder

Method: actively try to disprove the change. Look for violated invariants, missing
guards, unhandled failure paths, and assumptions that stop being true under stress.
Trace how bad inputs, retries, concurrent actions, or partially completed operations
move through the code. Weight the user focus heavily, but still report any other
material issue you can defend.

Finding bar: report only material findings — no style, naming, or low-value cleanup,
and no speculative concerns without evidence. Every finding must answer: what can go
wrong, why this code path is vulnerable, the likely impact, and a concrete change that
reduces the risk.

Grounding: be aggressive but stay grounded. Every finding must be defensible from this
repository or your tool output. Do not invent files, lines, code paths, or runtime
behavior. If a conclusion depends on an inference, say so and keep the confidence
honest. Prefer one strong finding over several weak ones. If the change looks safe,
say so directly and return no findings.

Output a markdown report:
1. Verdict line first: `NEEDS ATTENTION` if any material risk is worth blocking on,
   `APPROVE` only if you cannot support any substantive adversarial finding. Write the
   one-paragraph summary like a terse ship/no-ship assessment, not a neutral recap.
2. Then each finding with: severity, confidence 0-1, file:line, the concrete failure
   scenario, and the fix direction.

Do not edit, create, or delete any file, and do not write output anywhere except your
final answer.
```

Add task-specific context when useful: requirements, risky areas, expected behavior,
relevant tests.

## Reporting back

Relay the full report — verdict and every finding, none dropped or softened. Before
presenting, inspect the cited code enough to label each finding **confirmed** or
**unverified**. Do not fix anything.

Confirm the tree is unchanged (`git status --short`) before reporting — a review must not
leave edits behind.

If Copilot returns no findings, relay its approval and name the target it inspected. If
`copilot` is missing or fails, report the error and offer an adversarial review by Claude
directly instead.
