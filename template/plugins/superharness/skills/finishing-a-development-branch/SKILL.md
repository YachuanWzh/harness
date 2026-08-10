---
name: finishing-a-development-branch
description: Use when work done in an isolated worktree or branch is complete, verified, and reviewed - merge the branch back, remove the worktree, delete the branch, and report. The closing half of using-git-worktrees (go Phase 5)
---

# Finishing a Development Branch

## Overview

Close out a task that was developed in an isolated worktree or branch: merge the
verified, reviewed work back into the main branch, remove the disposable
worktree, delete the merged branch, and leave the repository clean. This is the
counterpart of `superharness:using-git-worktrees` — that skill isolates the
work, this skill closes it out.

**Announce at start:** "Closing out the isolated workspace
(finishing-a-development-branch)."

**Preconditions — do NOT finish until all of these hold:**

1. The full test suite passed in the worktree (`verification-before-completion`).
2. The review pass is done and Critical/Important issues were fixed
   (`requesting-code-review`).
3. All work is committed on the feature branch (no uncommitted changes).

If any precondition is missing, go back and complete it first. Finishing is not
a way to skip verification.

## Step 1 — Confirm where you are

```bash
git rev-parse --is-inside-work-tree 2>/dev/null || { echo "Not a git repo - nothing to finish. Report and stop."; exit 0; }
git status --short
git branch --show-current
```

- Not a git repo (or `go` worked in place, no branch was created): there is
  nothing to merge or clean up. Skip straight to Step 5.
- `git status --short` shows uncommitted changes: commit them first (they went
  through TDD already) or stop and ask — never merge a dirty worktree.
- `git rev-parse --show-superproject-working-tree` prints a path: you are in a
  submodule; treat it as a normal repo.

## Step 2 — Merge the branch back

Return to the main workspace and merge the feature branch. A fast-forward merge
is the normal case because the worktree branched off the current main and no
parallel work happened there:

```bash
# from the MAIN workspace (git worktree list shows its path), not the worktree
git switch <main-branch>
git merge --ff-only <feature-branch>
```

If `--ff-only` fails because main moved on, do a regular merge and resolve the
conflicts properly (this is a real engineering task — use
`superharness:systematic-debugging` if anything is unclear, never "just pick
ours"):

```bash
git merge <feature-branch>
# resolve conflicts, then verify: run the FULL test suite again in the main workspace
```

**After any merge, run the full test suite in the main workspace and paste the
real output.** The merge can change the result even when the branch was green.

## Step 3 — Remove the worktree and branch

Once merged (fast-forward or resolved), clean up the disposable workspace:

```bash
git worktree remove <worktree-path>
git branch -d <feature-branch>   # -d only deletes merged branches; if it refuses, the branch was NOT merged - stop
```

- If `git worktree remove` refuses because of uncommitted changes, deal with
  those changes first. Do not `--force` unless the human explicitly confirms the
  work there is disposable.
- If `git branch -d` refuses, the branch is not fully merged — investigate
  before discarding. Never `-D` a branch with unreviewed work.
- Only remove the `.worktrees/` entry from `.gitignore` if the directory is now
  gone (add/remove is optional; leaving the ignore line is harmless).

## Step 4 — Leave the repo clean

```bash
git worktree list   # should show only the main workspace
git status --short  # should be clean (or only expected files)
```

## Step 5 — Report

Report concisely:

- What was merged and into which branch (`<feature-branch>` -> `<main-branch>`)
- Merge method (fast-forward or merge commit) and whether any conflict resolution
  happened
- Test command run in the main workspace after the merge and its real output
- Worktree/branch cleanup performed (or "worked in place — nothing to clean up")
- Push status: **you did not push** unless the human asked

## Red Flags

| Thought | Reality |
|---------|---------|
| "It passed in the worktree, no need to re-run tests here" | The merge changes the tree. Run the full suite in the main workspace and show the output. |
| "The worktree has leftover changes, I'll just --force remove it" | Handle the changes first, or ask. --force discards work that may be unreviewed. |
| "git branch -d refused, but I know it's merged" | Then prove it — check `git log <main-branch>..<feature-branch>`. If it's really empty, -d succeeds. Refusal means it is not merged. |
| "I'll push to origin as part of finishing" | No. Pushing is a shared/external action — report the branch and let the human push. |
| "This repo isn't git, but I'll clean up anyway" | Nothing to clean up. Worked in place leaves no branch/worktree. Report and stop. |
