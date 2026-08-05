---
name: light
description: Use when the user gives a small, focused task goal that needs discipline without the full go machinery - quick fixes, small features, config or docs tweaks, prototypes, or when go feels too heavy. Keeps TDD (with explicit exemptions), real-output verification, and root-cause debugging while dropping worktrees, plan files, parallel dispatch, formal code review, and ralph tracking. For heavy multi-file work use superharness:go instead.
argument-hint: [task goal]
---

# Superharness Light — lightweight autonomous tasks

**Task goal:** $ARGUMENTS

If the goal above is empty, ask your human partner for the task goal and stop.

**Announce at start:** "Superharness light engaged. Working on: <goal>."

`light` is the lightweight tier of `/superharness:go`. Core discipline is kept (TDD, real-output verification, root-cause debugging); the heavy machinery is dropped. If the task turns out bigger than expected (touches multiple subsystems, needs formal review), proactively switch back to `/superharness:go` and explain why.

## When to use which

| Scenario | Command |
|----------|---------|
| Small bug fixes, small features, config/copy tweaks, prototype validation, when go feels too heavy | `/superharness:light` |
| Multi-file work, behavior changes, needs an isolated workspace / resumable runs / formal code review | `/superharness:go` |

## What light does NOT do

- No worktree/branch — works in place by default
- No plan file — the task list is managed with TodoWrite, nothing is written to disk
- No subagent dispatch for implementation or review — everything is done inline in the current session, closed out with a self-check list
- No ralph tracking — no `.current-task` / `task.json` / `trace.jsonl` are written, the Stop hook automatically no-ops, zero bookkeeping overhead; if interrupted, just re-run

> Note: if the project already has an active go task (`.claude/superharness/ralph/.current-task` exists — `.flavor/superharness/ralph/.current-task` under flavor-code), tell the user first — light will not take over or finish that task. Recommend closing out the go task before running light, to avoid the two flows crossing.

## Phase 1 — Understand

1. Restate the goal in one sentence.
2. Quickly locate the relevant files (Glob/Grep/Read) until you can say which files need to change.
3. Ask one round of clarifying questions if there is ambiguity; otherwise proceed with the most reasonable interpretation and record the assumptions in the final report.

## Phase 2 — Implement (TDD with explicit exemptions)

**Strict TDD by default**, see `superharness:test-driven-development`: failing test first (RED) → minimal implementation (GREEN) → refactor → commit.

**TDD Exemptions (no need to ask, but Phase 3 verification is still required):**
- Pure config: dependency manifests, build config, environment variables
- Pure copy/docs/comments
- Generated code / scaffolding
- One-off prototypes (not entering the main code path)

Exemptions still require: minimal, explainable changes, and verification after completion.

**Branch strategy:** work in place by default. Only create a one-off branch (no worktree) when the change heavily modifies existing code and the project is a git repo; merge or discard it when done.

**Commits:** one commit per cohesive unit; not every TDD cycle needs its own commit.

## Phase 3 — Verification (non-negotiable)

- Run the affected tests plus the project's test command (if the project defines one, run the full suite), and paste the real output.
- On failure → follow the `superharness:systematic-debugging` root-cause flow: reproduce → locate root cause → fix (with a regression test) → re-verify.
- "Should be fine" is not an acceptable way to close out.

## Phase 4 — Self-check list (replaces formal review)

Go through this once the change is complete:

- [ ] No debug leftovers in the diff (console.log / debugger / temp code)
- [ ] No dead code / unused imports
- [ ] Naming consistent with existing code
- [ ] Tests actually failed (RED evidence), or the change falls under an exemption category
- [ ] Edge cases quickly reviewed

Does the change touch multiple modules or a public API? Proactively suggest running `/superharness:go` afterwards for the full flow.

## Phase 5 — Report

Report concisely: what changed (file paths), what commands were run, real results, assumptions.
No trace, no `.current-task` — light leaves no runtime footprint.

## Red Flags

| Thought | Reality |
|---------|---------|
| "This change is too simple, no need to verify" | Verification is non-negotiable: run tests, paste output. |
| "Change the code first, add tests later" | TDD by default: failing test first. Exemptions only cover config/copy/scaffolding. |
| "It failed, just try a different approach" | Follow root-cause debugging; no guess-and-patch. |
| "The task is bigger than expected, keep pushing through" | Switch back to `/superharness:go`. |
