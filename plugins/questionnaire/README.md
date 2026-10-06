# questionnaire

Batch 3+ clarifying questions into a local HTML questionnaire instead of grilling serially in chat.

## Why

Bundled chat questions force tracking multiple decision threads at once ("hard to do four things at once"), but long one-question-per-turn rounds are slow. A local form lets you answer the whole batch in bulk, annotate each answer, and paste everything back as one prompt.

## Behavior

- **1–2 questions** → asked in chat, one per turn, with options + a recommendation.
- **3+ questions** → Claude fills `assets/questionnaire.html` with the questions, writes it to `/tmp/`, and opens it in the browser.

The form has:

- Radio buttons (single-choice) / checkboxes (multi-choice), **recommended answers pre-checked** — agree with everything and it's one click.
- An "Other" free-text option and an optional comment box per question.
- Freeform text questions.
- An answered-count indicator and a sticky **Copy prompt** button that serializes all answers + comments into one prompt to paste back into the session.

Self-contained single file — no network, dark-mode aware, clipboard fallback for `file://` pages.

## Install

```
npx skills add ctrlShiftBryan/skills -g --skill questionnaire
```

## Components

| Component | Name | Purpose |
|---|---|---|
| skill | `questionnaire` | The decision rule (chat vs form), question JSON schema, template fill + open, paste-back handling |
| asset | `assets/questionnaire.html` | Self-contained form template with `__TITLE__` / `__QUESTIONS_JSON__` placeholders |
