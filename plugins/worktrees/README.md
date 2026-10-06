# worktrees

Bryan's git worktree conventions (the `gw` / `gwct` / `gwb` / `gwl` zsh aliases) as a skill, so Claude creates, navigates, and cleans up worktrees the same way the shell tooling does.

## Conventions captured

- Every worktree lives in a sibling folder: `/path/to/<repo>-worktrees/<branch-name>` — never inside the repo or in `/tmp`.
- Worktrees are created from the main repo while it stays on `main`/`master`.
- `gwct <branch>` = new branch + worktree; `gw <branch>` = existing local or remote branch into a worktree (with tracking).
- `gwb` = back to the main repo (first entry of `git worktree list`).
- `gwl` → `c` cleanup = remove only **merged** worktrees (PR state via `gh`, fallback `git branch --merged`), then delete the branch. Never force-remove dirty worktrees.

The aliases themselves are interactive shell functions, so the skill tells Claude to run the equivalent git commands rather than invoke them — but to use the alias names when telling Bryan what to type.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install worktrees@ctrlshiftbryan-skills
```

## Components

| Component | Name | Purpose |
|---|---|---|
| skill | `worktrees` | Layout convention, create/checkout/navigate/cleanup rules, merged-only cleanup policy |
