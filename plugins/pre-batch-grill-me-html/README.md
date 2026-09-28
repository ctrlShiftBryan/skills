# pre-batch-grill-me-html

`batch-grill-me-html`, but the whole interview at once.

Instead of one decision frontier per turn, the skill walks the recommended-answer
path to full depth up-front — research included — and opens **every round in one
HTML form**, with recommended answers preselected and rounds stacked as labeled
sections.

The page embeds the dependency graph:

- Every question with dependents shows an **"affects …"** chip (its blast radius).
- Picking a non-recommended option or **Other** is a **deviation**: the full
  transitive closure of dependent questions locks read-only — "Impacted by your
  answer to X — needs revisiting" — with only a comment box left editable.
  Comments never lock anything. Re-picking the recommendation unlocks.
- A **clean pass** returns one prompt with every answer; the agent then presents
  a final synthesis, **auto-confirms** (no confirmation ask), and opens a
  **GitHub planning issue** in the working repo that includes a **branch name**
  for the work. This skill never implements — planner only.
- A **deviated pass** returns DEVIATIONS / IMPACTED / CONFIRMED sections; the
  agent settles what survived, re-runs pre-generation on the invalidated part of
  the tree, and opens the next pass. Repeat until clean.

Invoke explicitly with `/pre-batch-grill-me-html` (or "pre-batch grill me").

Forked from `batch-grill-me-html`; self-contained (own template at
`skills/pre-batch-grill-me-html/assets/allrounds.html`).
