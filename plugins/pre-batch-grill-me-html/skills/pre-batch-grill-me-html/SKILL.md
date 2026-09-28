---
name: pre-batch-grill-me-html
description: Pre-generate an entire dependency-aware design interview and deliver it as one all-rounds HTML form. Walks the recommended-answer path to full depth up-front (research included), embeds the dependency graph so deviations lock their downstream questions live in the page, and loops rebuild passes until a clean pass auto-confirms and opens a GitHub planning issue with a branch name. Use only when the user explicitly invokes `pre-batch-grill-me-html`, says "pre-batch grill me", or clearly asks for this exact pre-generated HTML grilling workflow; do not start it during ordinary planning or clarification.
disable-model-invocation: true
---

# Pre-Batch Grill Me HTML

Reach a genuinely shared understanding by treating the problem as a decision tree — but instead of interviewing one frontier per turn, pre-generate the **whole interview** by assuming the recommended answer at every step, and deliver all rounds as one HTML form. The form knows the dependency graph: when the user deviates from a recommendation, every question that assumed it locks itself, and the returned prompt tells you exactly what to rebuild.

This skill is a **planner only**. Never implement, code, refactor, open PRs with implementation, or otherwise build the resulting design. The only write action after a clean pass is creating a GitHub planning issue (with a branch name) in the working repo.

## 1. Frame the design tree

Read the conversation and inspect the in-scope environment before generating anything. Separate:

- **Facts**: discoverable from files, documentation, tools, or external systems. Finding these is your job.
- **Decisions**: choices that depend on the user's goals, preferences, authority, or appetite for tradeoffs. Put these to the user.
- **Assumptions**: beliefs that are neither verified facts nor explicit decisions. Turn each material assumption into research or a decision.

Map the decisions as a tree. Every node has a stable short ID (`scope-1`, `auth-2`), the decision to settle, its prerequisites, the branches each plausible answer may unlock, and its state: `blocked`, `frontier`, or `settled`.

## 2. Research everything up-front

All research the recommended path needs runs **before** the form opens. Use read-only inspection and available tools; delegate independent fact-finding to sub-agents when available. Never ask the user for a fact you can discover safely yourself.

Because later rounds are generated ahead of time, a fact that would normally be looked up between rounds must be looked up now, under the assumption that earlier recommendations hold.

## 3. Pre-generate all rounds

Walk the recommended path to full depth:

1. Compute the current frontier: every unresolved decision whose prerequisites are settled.
2. Write the frontier's questions (format below), each with exactly one recommended answer per single-choice question (one or more for multi).
3. **Assume every recommendation is accepted.** Mark those decisions provisionally settled, add newly exposed branches, prune branches the assumed answers make irrelevant.
4. Repeat until the frontier is empty. No depth cap.

Each iteration becomes one **round** in the form. Later rounds are written in the context of the assumed answers — that assumption is exactly what the form's deviation-locking protects, so record `prerequisites` accurately: they are the dependency graph the page enforces. If any plausible non-recommended answer to A would remove B, reword B, change B's options, or change B's recommendation, then A belongs in B's prerequisites and B belongs in a later round.

Audit before rendering: no question may share a round with one of its prerequisites, and no prerequisite may appear in a later round than its dependent. Never satisfy this by erasing a real dependency.

## 4. Question format

Every question needs:

- `id`: stable across passes
- `prerequisites`: decision IDs settled before this pass **or asked in an earlier round of this same form**; `[]` only for true roots
- `question`: the decision in plain language
- `context`: why it matters and what downstream choice it affects
- `type`: `single` or `multi`
- `options`: concrete choices, each with `label`, `detail` (the tradeoff), and boolean `recommended`

The template adds an `Other` option and an **Additional comments** box to every question automatically, renders an "affects …" chip from the dependency graph, and preselects recommendations. Do not create freeform-only questions: research the option space and present concrete choices. Do not hide behind "it depends" — recommend, expose the tradeoff, let the user decide.

For visual or spatial decisions (layouts, widgets, navigation), attach an optional `mockup` — `{ "html": "...", "height": 220, "caption": "..." }` — on the question or on individual options. Mockup HTML must be fully self-contained (inline CSS/JS, no network); it renders in a sandboxed iframe. Every option label must still stand alone in the text-only prompt.

## 5. Build and open the all-rounds form

Read `assets/allrounds.html` from this skill's directory and replace every placeholder:

- `__TITLE__`: short topic title (plain text; appears twice)
- `__PASS__`: pass number, starting at 1 (a number; appears several times)
- `__TOPIC__`: one sentence describing what the interview settles, **as a JSON string including quotes** (it is assigned to a JS const)
- `__SETTLED_JSON__`: JSON array of concise settled-decision strings, or `[]`
- `__SETTLED_IDS_JSON__`: JSON array of decision IDs settled before this pass, or `[]`
- `__ROUNDS_JSON__`: the whole interview as a JSON **array of rounds**, each an array of question objects
- `__TARGET_PANE_JSON__`: the value of `$BMUX_PANE_ID` as a JSON string when set, else the literal `null`

Keep the template's validation: it rejects duplicate IDs, unknown prerequisites, same-round prerequisites, and forward references — do not bypass it.

JSON-encode all substituted values, and serialize `__ROUNDS_JSON__` (and `__TOPIC__`) with `&`, `<`, `>` escaped as `\u0026`, `\u003c`, `\u003e` so no `</script>` can terminate the inline script (mockup HTML makes this easy to violate). Example: `json.dumps(rounds).replace('&','\\u0026').replace('<','\\u003c').replace('>','\\u003e')`.

Write the result to `/tmp/pre-batch-grill-me-html-<topic-slug>-pass-<n>.html` and open it (prefer `bm-open` / the `bm-open-html` skill when inside browser-mux; otherwise the platform opener). After generating, verify the inline script parses — e.g. extract it and run `node --check` — before opening.

End the turn with:

> Pass `<n>` is open — all `<r>` rounds pre-generated on the recommended path. Change anything you disagree with; dependent questions will lock themselves. Then **Send to agent** (or **Copy prompt** and paste it back into this chat).

Do not ask more questions while the form is pending.

## 6. What the form does (behavior contract)

The page enforces the design so the returned prompt is trustworthy:

- **Deviation** = selecting a non-recommended option or `Other`. Comments never count as deviations.
- A deviation locks the **full transitive closure** of its dependents: grayed, inputs disabled, labeled "Impacted by your answer to `<id>` — needs revisiting", comment box still editable. Re-selecting the recommendation unlocks them.
- A deviated question that is itself downstream of another deviation counts as impacted, not deviated.
- Clean pass prompt: every answer by round, plus an instruction to present the final synthesis.
- Deviated pass prompt: three sections — DEVIATIONS, IMPACTED (with assumed-now-invalid answers and comments), CONFIRMED — plus a rebuild instruction.

## 7. Process the returned pass

Treat comments as authoritative when they conflict with a selection; a conflicting comment on a confirmed answer can reopen its subtree even though the form did not lock it.

**Clean pass** (no deviations, no impacted):

1. Present a concise final synthesis — goal and boundaries, decisions and consequences, exclusions and deferred work, remaining risks.
2. **Auto-confirm** the shared understanding. Do **not** ask the user to confirm, and do **not** wait for a confirmation turn.
3. Immediately create a **GitHub issue** in the repository this grilling was working in (detect from the in-scope project: `git remote get-url origin`, the open workspace, or conversation context). If the repo cannot be determined confidently, say so and stop — do not post to a guessed repo.
4. Choose a **branch name** for the planned work (kebab-case from the topic/goal, e.g. `feat/short-topic-slug`). Put it in the issue body under a clear heading such as `## Branch` so implementers know which branch to use.
5. Issue contents (via `gh issue create` unless the environment already has an equivalent GitHub write path):
   - **Title**: short planning title from the topic (e.g. `Plan: <topic>`).
   - **Body**: the final synthesis, plus the branch name, plus enough settled-decision context that someone can implement from the issue alone.
6. End by linking the created issue. Do **not** implement anything after posting.

**Deviated pass**:

1. Move CONFIRMED and DEVIATIONS decisions to settled (deviations settle with their new answers).
2. Rebuild the invalidated part of the tree: re-run steps 2–3 for the impacted and still-open branches, honoring every comment left on locked questions.
3. Open pass `n+1` as a new all-rounds form. Settled decisions go in the settled panel and do not reappear as editable questions.
4. Repeat until a pass comes back clean, then close as above.
