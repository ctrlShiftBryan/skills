# pr-review-html

Generate a single self-contained, interactive HTML code-review artifact for a GitHub PR. Claude fetches the diff via the `gh` CLI, performs an honest severity-coded self-review, and renders a portable file with collapsible per-file diffs, colored inline annotations, severity filter chips, per-finding checkboxes, and a "Create feedback prompt" modal that aggregates the checked items into a paste-ready follow-up prompt for the next agent.

## Components

- **`pr-review-html`** (skill) — Drives the workflow: gather the diff + PR metadata, write a `findings.json`, and run the bundled Python build script to produce the HTML artifact. Bundles `references/findings-schema.md` (full JSON schema + severity rubric), `scripts/build_review.py` (Python stdlib only), and `scripts/template.html`.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install pr-review-html@ctrlshiftbryan-skills
```

## Usage

Trigger the skill with natural language naming a PR or asking for a visual/static review. Examples:

- `review PR #54`
- `review this PR`
- `build a PR review for #128`
- `code review artifact for this PR`
- `make an interactive review with color-coded findings`
- `build a feedback prompt for PR #99`

Claude then:

1. Pulls the diff and metadata (`gh pr diff <N>`, `gh pr view <N> --json ...`).
2. Self-reviews each observation, assigning a severity: `critical`, `major`, `minor`, `nit`, or `praise`.
3. Writes a `findings.json` (schema in `references/findings-schema.md`).
4. Runs the build script:

   ```bash
   python skills/pr-review-html/scripts/build_review.py \
     --findings /tmp/pr-<N>-findings.json \
     --output plans/<unix-ts>--<m-d-h:mmam/pm>--pr-<N>-review.html
   ```

5. Reports back the output path and a one-sentence verdict.

Open the resulting HTML in a browser: sticky header with PR metadata and filter chips, two-column per-file diff + finding cards, click-to-scroll between annotated lines and cards, per-finding checkboxes, and a "Create feedback prompt" button that copies a markdown prompt aggregating the checked items.

## Notes

- Requires the `gh` CLI (authenticated) to fetch the diff, and Python 3 to run the build script. The script is stdlib only — no `pip install`.
- The artifact is a single portable file you can share, archive, or revisit. For tiny PRs (1-2 line changes) it's overkill — leave inline comments via `gh pr review` instead.
- `build_review.py` takes `--findings` (required), `--output` (required), and `--template` (optional override; defaults to the sibling `template.html`).
- Annotation `body`/`title` accept inline `<code>` and `<em>`/`<i>`, which translate to markdown backticks/underscores in the aggregated prompt. The aggregated prompt ends with: "Please address this feedback. Address each individual item in its own conventional commit."
