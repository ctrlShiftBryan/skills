# review-address

Replies to **every** PR review comment — GitHub Copilot, other review bots, and human reviewers — with a code fix or a reasoned push-back. It fetches all comments via the GitHub API (inline review comments, top-level issue comments, and reviews), triages each one, makes minimal KISS code fixes, commits and pushes them as a single conventional commit, then posts an inline reply to every comment. The replies are the deliverable: the skill is not complete until every non-author comment has a response posted.

## Components

- **`review-address`** (skill) — Detect the PR on the current branch, fetch all reviewer comments, triage (address vs. push-back), fix code, commit/push, and reply inline to every comment. Optionally requests re-review from humans whose feedback was addressed.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install review-address@ctrlshiftbryan-skills
```

## Usage

Run it from a branch with an open PR. Triggers on natural-language phrases such as:

- "address the review"
- "reply to the comments"
- "handle the PR feedback"
- "address Copilot's review"
- "respond to review comments"
- "clear out the reviewer comments"

It fires even when no specific reviewer is named.

## Notes / Requirements

- Requires the `gh` CLI authenticated against the repo; all fetching and replying goes through `gh api`.
- Must be run on a branch with an **open** PR — it stops with a message if there's no PR, no review comments, or all comments are from the PR author.
- Comments from the PR author are discarded; every other comment gets a reply regardless of whether the author already responded in the thread.
- GitHub Copilot's comments (login `copilot-pull-request-reviewer[bot]`) are treated as just another bot reviewer.
- Code fixes are squashed into a single conventional commit whose message describes the actual changes; the commit step is skipped if all comments are push-backs.
- **Re-runnable / safe to repeat** — already-handled comments still get a follow-up reply rather than being skipped.
- **Plan mode:** does not act — instead produces a reviewer-grouped triage table (each comment, address/push-back decision, proposed change or reasoning).
- After replying, if any human reviewers' comments were addressed, it offers to request re-review from those reviewers.
