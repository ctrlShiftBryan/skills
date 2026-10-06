# batch-grill-me-html

Turn an unresolved plan or design into a dependency-aware interview, with each round delivered as a local HTML form.

## How it works

The skill models the work as a decision tree. A round contains the complete current **frontier**: every unresolved decision whose prerequisites are already settled. Questions that depend on answers from the current round wait for the next one.

Each form includes:

- A recommended answer for every question, preselected with concise tradeoffs
- Radio buttons for single-choice questions and checkboxes for multi-choice questions
- An `Other` answer and freeform additional-comment box for every question
- Optional HTML mockups — question-level frames or per-option candidates — rendered in sandboxed iframes so screen/widget designs are chosen visually, with their CSS/JS isolated from the form
- The decisions already settled, so the round has context
- Runtime prerequisite validation that rejects same-round and otherwise unsettled dependencies
- An answered counter and a top-level **Copy prompt** button that copies all answers and additional comments as one paste-back prompt
- A visible instruction to paste the copied prompt back into the chat session
- A clipboard fallback for local `file://` pages

After the answers are pasted back, the agent updates the tree and opens the next frontier. When no branches remain, it presents the shared understanding and waits for explicit confirmation before acting.

## Install

```text
npx skills add ctrlShiftBryan/skills -g --skill batch-grill-me-html
```

## Invoke

```text
/batch-grill-me-html Stress-test the design for our account recovery flow.
```

This skill is manual-only: a relentless interview should begin because you asked for one, not because ordinary planning happened to contain a few open questions.

## Components

| Component | Name | Purpose |
|---|---|---|
| skill | `batch-grill-me-html` | Builds the decision tree, researches facts, manages the frontier, and controls the confirmation gate |
| asset | `assets/round.html` | Single-file form template used for each interview round |

## Attribution

Inspired by Matt Pocock's [`batch-grill-me`](https://github.com/mattpocock/skills/blob/9603c1cc8118d08bc1b3bf34cf714f62178dea3b/skills/in-progress/batch-grill-me/SKILL.md) design-tree and frontier model.
