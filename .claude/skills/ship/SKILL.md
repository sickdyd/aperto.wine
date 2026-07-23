---
name: ship
description: Use when starting any implementation work in this repo (feature, fix, refactor, chore) — and again when its PR is open, to finish the delivery. Not for pure Q&A or analysis tasks.
---

# Ship: aperto.wine delivery pipeline

## Overview

Every change ships end-to-end in one loop, with the review skills as the quality
gate instead of the user's manual review (they are not reviewing code right now —
too much volume). Stopping at "PR opened" is a failure, not a checkpoint.

## The loop

1. **Isolate** — create a new git worktree with a new branch off latest
   `origin/main`. Restore the gitignored Phosphor icons dir (see `docs/ASSETS.md`);
   if schema.rb needs regenerating use a scratch DB, never the shared dev DB.
2. **Implement** — subagent-driven, TDD; every feature gets system/E2E tests on
   top of unit + integration.
3. **Review pipeline** (before the PR, in this order):
   1. `/security-review`
   2. `/postgres-patterns` — skip only if the diff has no DB-related code
   3. `/code-review`
   4. `bin/bundler-audit` — fix flagged gems, even pre-existing ones

   Apply CRITICAL and HIGH fixes always; MEDIUM/LOW when sensible, otherwise
   note them in the PR body with a recommendation.
4. **PR** — `git push -u`, `gh pr create`. Never any Claude/Anthropic
   attribution in commits or PR bodies.
5. **Merge** — `gh pr checks <n> --watch`; when all checks are green:
   `gh pr merge <n> --squash`, pull main in the primary checkout
   (`git -C <main-checkout> pull --ff-only`), and delete the branch remotely
   and locally.

## Stop conditions — the only reasons not to complete the loop

- CI fails → fix and push; never merge red.
- main has in-progress changes that would clash → surface it instead of merging.
- A genuinely destructive or scope-changing decision comes up → ask.

## Red flags — STOP if you catch yourself thinking

| Thought | Reality |
|---------|---------|
| "PR is opened, I'll wait for the user's review" | The user is not reviewing; green CI is the merge signal. |
| "This change is small, skip the review pipeline" | Small diffs review fast; run it anyway. |
| "I'll reuse this existing branch/worktree" | New worktree + branch per task, always off latest origin/main. |
| "I'll merge now and let CI run on main" | Merge only after `gh pr checks` reports all green. |

## Gotchas

- `gh pr merge --delete-branch` fails when `main` is checked out in the primary
  worktree ("'main' is already used by worktree"). Merge without the flag, then
  `git push origin --delete <branch>` and delete the local branch yourself.
- `git stash` is shared across worktrees — never use it bare; prefer a WIP commit.
