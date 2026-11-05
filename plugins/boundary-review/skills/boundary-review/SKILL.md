---
name: boundary-review
description: Review a diff for module-boundary violations — cross-feature imports, reversed layer dependencies (features importing app/, ui importing features/, tests included), shotgun surgery from a concept with no ownership seam, and hollow modules whose name no longer matches what they export. Use when the user asks to check a branch or PR for architecture / import-boundary / layering problems, or says "boundary review".
---

Review the diff between `HEAD` and a fixed point for **dependency-direction and ownership** problems only. Bugs, spec fit, and style are out of scope — other reviews cover those.

## 1. Pin the diff

Fixed point = whatever the user gave (`main`, a SHA, a tag). If none, ask. Confirm it resolves and the diff is non-empty:

```bash
git rev-parse <fixed-point>
git diff <fixed-point>...HEAD --stat
```

## 2. Load the repo's layer rules

Read the repo's architecture docs (`CLAUDE.md`, `ARCHITECTURE.md`, `docs/adr/`). Extract the **allowed import graph**: which top-level dirs may import which. Write it down before reading code — every finding below cites one of these rules. If the repo documents nothing, fall back to the default graph:

```
app/ → features/, components/, hooks/, shared/
features/<x>/ → components/ui/, shared/, features/<x>/ (itself only)
components/ui/ → shared/
hooks/ → shared/
shared/ → nothing framework-specific (no React, no backend SDK)
```

Tests obey the same graph as the code they sit next to. A `features/a/**/*.test.ts` importing `app/` or `features/b/` is a real violation, not a test convenience.

## 3. Mechanical scan: every import line the diff adds

Pull the added import lines and classify each:

```bash
git diff <fixed-point>...HEAD -U0 | grep -E '^\+\+\+ |^\+.*(import .* from|require\()' 
```

For each added import, record `(importing file's layer) → (imported path's layer)` and check it against the graph from step 2. Flag:

- **Cross-feature** — `features/a/**` importing `@/features/b/**`. Hard violation. Count the distinct importing features; the count is the severity.
- **Reversed layer** — `features/**` → `app/**`; `components/ui/**` → `features/**` or `convex/**`; `shared/**` → React / backend SDK; `hooks/**` → `features/**`. Hard violation.
- **Re-export laundering** — a `shared/` or barrel file that only re-exports from a feature, used to dodge the rule above. Hard violation; cite both files.

Do not reason about intent here. A line either crosses the graph or it does not.

## 4. Judgement scan: ownership

Now read the diff as a whole and look for two shapes.

**Shotgun surgery / missing seam.** One concept moved or renamed, and the diff touches many unrelated features to follow it. Tell:

- `git diff --stat` shows edits across ≥3 feature dirs for one logical change.
- The same one-line import swap repeats across them.

Ask: what is the concept, and who should own it? If unrelated features all need it, it belongs in `shared/` (pure) or a store slice with a documented owner — not in one feature that everyone else imports. Name the concept, list the files, propose the seam.

**Hollow module / mysterious name.** A file whose name promises one thing but whose exports now say another — e.g. `FooScreen.tsx` that exports only `screenMeta` because the real screen moved elsewhere; `use-foo.ts` that only re-exports. Tell: the diff deletes most of a file's body and leaves a stub with the old name. Propose rename or deletion.

## 5. Report

Under 400 words. Structure:

```
## Hard violations
- <rule cited: file:line of the doc> — <importing file:line> → <imported path>
  (one bullet per importing file; group by rule)

## Ownership
- Possible Shotgun Surgery: <concept>. Touches <n> features: <list>. Seam: <proposal>.
- Possible Hollow Module: <file> now exports only <x>. <rename / delete>.

## Verdict
<one line: N hard violations across M features, K ownership smells; mergeable as-is? yes/no>
```

Hard violations are pass/fail against a documented rule — do not soften them. Ownership findings are always labelled "Possible" and are judgement calls. Skip anything a linter in the repo already rejects.
