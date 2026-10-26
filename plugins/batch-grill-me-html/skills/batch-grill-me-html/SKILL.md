---
name: batch-grill-me-html
description: Run a relentless, dependency-aware interview as a sequence of local HTML forms. Build a design tree, research factual prerequisites yourself, ask the complete currently-unblocked frontier in each round with recommended answers preselected, and continue until every branch is settled. Use only when the user explicitly invokes `batch-grill-me-html`, says "batch grill me in HTML", or clearly asks for this exact HTML grilling workflow; do not start a relentless interview during ordinary planning or clarification.
disable-model-invocation: true
---

# Batch Grill Me HTML

Reach a genuinely shared understanding by treating the problem as a decision tree and interviewing the user one dependency-valid frontier at a time. Deliver each frontier as a single-file HTML form so the user can answer the whole round without juggling parallel chat threads.

Do not implement, publish, or otherwise act on the resulting design until the frontier is empty and the user explicitly confirms the final shared understanding.

## 1. Frame the design tree

Read the conversation and inspect the in-scope environment before asking anything. Separate:

- **Facts**: discoverable from files, documentation, tools, or external systems. Finding these is your job.
- **Decisions**: choices that depend on the user's goals, preferences, authority, or appetite for tradeoffs. Put these to the user.
- **Assumptions**: beliefs that are neither verified facts nor explicit decisions. Turn each material assumption into research or a decision.

Map the decisions as a tree. Every node has:

- A stable short ID such as `scope-1` or `auth-2`
- The decision to settle
- Its prerequisites
- The branches or follow-up decisions each plausible answer may unlock
- Its state: `blocked`, `frontier`, or `settled`

Keep the tree in working memory unless its size or the session length makes a temporary Markdown state file useful. Do not burden the user with the internal tree unless showing a small piece helps explain why a question is deferred.

## 2. Research factual prerequisites

Use read-only inspection and available tools to answer factual questions. Delegate independent fact-finding when sub-agents are available, especially when it can run alongside the user's current round.

Research does not stop the interview globally. Treat an unresolved investigation as an unsettled prerequisite and defer only the decisions downstream of it. Continue with every other unblocked branch.

Never ask the user to locate a file, report a configuration value, summarize documentation, or provide another fact you can discover safely yourself. Ask only when access is genuinely unavailable, and explain what you already checked.

## 3. Compute the frontier

The frontier is the complete set of unresolved decisions whose prerequisites are settled now.

Before every round:

1. Apply all answers and research results to the tree.
2. Add newly exposed branches.
3. Remove choices made irrelevant by earlier answers.
4. Mark as frontier every remaining decision with no unsettled prerequisite.
5. Hold back any question that depends on another question in the same round.

Ask the whole frontier. Do not arbitrarily cap a round or serialize independent decisions across several turns. A large but dependency-valid frontier belongs in one form.

## 4. Design the round

For every frontier decision, write one question. Avoid multipart questions; split them into separate nodes if they can be answered independently.

Each question needs:

- `id`: stable across rounds
- `prerequisites`: stable decision IDs that must already be settled before this question can appear; use `[]` only for true roots
- `question`: the decision in plain language
- `context`: why it matters now and what downstream choice it affects
- `type`: `single` or `multi`
- `options`: concrete choices, with at least one recommended answer

Each option needs a concise `label`, a `detail` describing its tradeoff, and a boolean `recommended`. Recommend the answer you believe best fits the evidence and the user's stated goals. Use exactly one recommendation for a single-choice question and one or more for a multi-choice question.

Render `single` questions as radio buttons and `multi` questions as checkboxes. Every question must also include an `Other` answer and a freeform **Additional comments (optional)** box. Do not create freeform-only questions: when the option space is broad, research it, present the best concrete choices you can identify, and let the user use `Other` plus the additional-comment box for an answer outside them.

Do not hide behind "it depends." State a recommendation, expose the tradeoff, and let the user decide.

### Show visual decisions as mockups

Some decisions are visual or spatial: screen layouts, widget designs, navigation placement, empty states, chart shapes. Text labels underdescribe these — the user ends up choosing between sentences when they should be choosing between pictures. For those decisions, attach an optional `mockup` — `{ "html": "...", "height": 220, "caption": "..." }` — at either level:

- On the **question**, to show the current state or the frame being decided (a wireframe of the settings page whose new widget you're asking about).
- On each **option**, to show that candidate concretely (layout A vs layout B as small rendered mockups the user can compare and, when they include JS, interact with).

Mockup HTML must be completely self-contained: inline CSS and JS only, no external images, fonts, stylesheets, or network requests, because the form opens from `file://` and may be viewed offline. Keep each mockup small and representative — a few dozen elements that communicate the idea, not a pixel-perfect build. `height` is the rendered pixel height (default 180, clamped 60–720).

The template renders mockups in sandboxed iframes, so their styles and scripts cannot interfere with the form — and clicks inside a mockup do not select its option; selection stays on the radio or checkbox. Because the copied prompt is text-only, every option's `label` must still stand on its own without the picture.

Use mockups only where seeing beats reading. A storage-engine choice gains nothing from a drawing; a dashboard-layout choice is barely answerable without one.

### Audit dependencies before rendering

A frontier is valid only when every question's prerequisites were settled before the round began. A prerequisite asked elsewhere in the same round is still unsettled and makes the round invalid.

Perform this audit after drafting the candidate questions:

1. For every pair of candidate questions A and B, ask whether any plausible answer to A could remove B, change B's wording, change B's options, or change the recommendation for B.
2. If yes, add A to B's `prerequisites` and defer B to a later round.
3. Treat a question context that says its answer "determines," "affects," or "unblocks" another candidate as direct evidence that the other candidate cannot remain in this round.
4. Treat questions about exceptions or overrides as downstream of the normal path they override. For example, first settle whether self-service exists; only then ask how support may bypass it.
5. Repeat the pairwise scan until no question in the frontier can change another question in that frontier.

Before building the form, verify this invariant for every question:

```text
question.prerequisites ⊆ decisions settled before this round
```

Never satisfy the invariant by erasing a real dependency or declaring everything a root. The prerequisite list records the actual design tree.

## 5. Build and open the HTML form

Read `assets/round.html` from this skill's directory and replace every placeholder:

- `__TITLE__`: a short topic title; it appears twice
- `__ROUND__`: the round number
- `__TOPIC__`: one sentence describing what this frontier settles
- `__SETTLED_JSON__`: a JSON array of concise settled-decision strings, or `[]`
- `__SETTLED_IDS_JSON__`: a JSON array of decision IDs settled before this round, or `[]`
- `__QUESTIONS_JSON__`: the complete frontier as JSON

The template rejects a question when its prerequisites are missing, unsettled, or present in the same frontier; do not remove or bypass that validation.

Example question data:

```json
[
  {
    "id": "auth-1",
    "prerequisites": [],
    "question": "Where should active sessions be stored?",
    "context": "This determines revocation behavior and unblocks the deployment topology.",
    "type": "single",
    "options": [
      {
        "label": "Server-side session store",
        "detail": "Immediate revocation; adds shared state and operational cost.",
        "recommended": true
      },
      {
        "label": "Signed stateless tokens",
        "detail": "Simpler reads; revocation and rotation are harder.",
        "recommended": false
      }
    ]
  }
]
```

JSON-encode all substituted values. Do not allow the literal string `</script>` in inserted content because it would terminate the template's inline script. Mockup HTML makes this easy to violate accidentally, so serialize `__QUESTIONS_JSON__` with `<`, `>`, and `&` escaped as `\u003c`, `\u003e`, and `\u0026` (for example `json.dumps(questions).replace('<', '\\u003c').replace('>', '\\u003e')` after escaping `&`); the JSON decodes to identical strings at runtime and the HTML parser never sees a closing tag.

Write the result to `/tmp/batch-grill-me-html-<topic-slug>-round-<n>.html`. Keep the `batch-grill-me-html-` prefix: bmux recognizes the form by that name. Open it:

- **In bmux** (the bmux MCP tools are available, or `bmux` is on `PATH`): call `open_file` with the path and `worker: true`, or run `bmux open --worker <path>`. The form opens as a page on your pane's worker, beside your pane, and can hand the answers straight back (below).
- **Anywhere else**: open it with the platform's local file opener (`open` on macOS, `xdg-open` on Linux). If opening is unavailable, give the user the path.

The top of the page must contain a **Copy prompt** button. It must aggregate every selected answer, every `Other` value, and every non-empty additional comment into one prompt and copy that prompt to the clipboard, with a manual-copy fallback when clipboard access is unavailable.

The form must visibly tell the user to complete the round, click **Copy prompt**, and paste the copied prompt back into this chat. Do not rely on the button label or clipboard contents to imply the handoff.

### Direct hand-back in bmux

Opened with `open_file` and `worker: true`, the form is a page on a worker that bmux's `grill-forms` page plugin matches, and the page has `window.bmuxHandBack`. The template then reveals two more buttons: **Send to agent**, which submits the answers as your next turn, and **Prefill composer**, which leaves them in your prompt box for editing. Either one closes the form's pane once it lands. Whoever answers (a person, or another agent driving the page with browser tools) needs no pane id: bmux hands the answers to the pane that opened the form. Anywhere else `window.bmuxHandBack` is undefined, the buttons stay hidden, and **Copy prompt** is the whole handoff.

Keep **Copy prompt** in every form regardless: it is the fallback when delivery fails (a hand-back takes at most 4096 characters).

End every round with this exact response structure, filling in the round number:

> Round `<n>` is open. Complete the form, then **Send to agent** (or **Copy prompt** and paste it back into this chat). I'll use your answers to update the design tree and open the next frontier.

Do not ask more questions while that form is pending.

## 6. Process the returned round

The round arrives as one prompt — sent by the form's own button or pasted by the user — carrying stable question IDs, selected labels, and optional `Additional comment:` lines.

- Treat an additional comment as authoritative when it conflicts with a selected option.
- Treat `(no answer)` as deferred, not settled. Carry that decision into the next frontier and say why it remains open.
- If the answer introduces a new branch, add it to the tree.
- If the answer makes a branch irrelevant, prune it explicitly.
- Ask a chat follow-up only when the returned answer is internally contradictory and cannot be resolved from context.

Then incorporate completed research, recompute the frontier, and open the next HTML round.

## 7. Close on shared understanding

The interview is complete only when:

- No unresolved decision has all prerequisites settled
- No research result is still capable of exposing another material decision
- Every reachable branch has been settled or deliberately pruned
- No material assumption remains silent

When the frontier is empty, present a concise final synthesis containing:

1. The goal and boundaries
2. The decisions made and their important consequences
3. Explicit exclusions and deferred work
4. Remaining risks or facts that could invalidate the design

Ask the user to confirm that this is the shared understanding. Do not begin implementation in the same turn. Once they confirm, return control to the user's requested next workflow.
