---
name: go
description: Use when the user gives a task goal to complete end-to-end under superharness discipline - drives the full autonomous workflow from goal to verified, reviewed, committed result
argument-hint: [task goal]
---

# Superharness Go — Autonomous Task Workflow

**Task goal:** $ARGUMENTS

If the goal above is empty, ask your human partner for the task goal and stop.

**Announce at start:** "Superharness engaged. Working on: <goal>."

You will now drive this goal to completion under the constraints in `HARNESS.md`
(in this plugin's root directory — read it now if it is not already in your context).
Work autonomously: only stop to ask when a decision genuinely belongs to your human
partner (destructive actions, ambiguous product choices). Everything else, decide and proceed.

## Phase 0 — Understand

1. Restate the goal in one sentence.
2. Explore the relevant code (Glob/Grep/Read) until you can name the files involved.
3. If the goal is ambiguous in a way that changes the architecture, ask ONE round of
   clarifying questions. Otherwise proceed with the most reasonable interpretation and
   note your assumptions in the plan.

## Phase 1 — Plan

**REQUIRED SUB-SKILL:** `superharness:writing-plans`

- For any goal needing 3+ steps, write the plan to `superharness/plans/YYYY-MM-DD-<slug>.md`
  in the project root (create the folder if missing).
- Bite-sized tasks, 2–5 minutes each. Every code step shows the actual code.
  Every task follows the TDD step sequence: failing test → verify RED → minimal
  implementation → verify GREEN → commit.
- Trivial goals (1–2 steps) may skip the plan file but NOT the TDD cycle.
- Create one TodoWrite/Task item per plan task and keep statuses current.
- **Trace bootstrap.** At task start, write `superharness/trace/.state/task.json`
  (single-line JSON) with `{"task_id":"<YYYY-MM-DD-slug>","slug":"<YYYY-MM-DD-slug>","goal":"<one-line goal>","started_at":"<ISO8601>"}`.
  This activates per-round tracking — the Stop hook is a no-op until it exists.
  Track **one active go task per project** at a time: this file is the single
  active-task marker, so do not run concurrent `go` tasks in the same project
  (a new task overwrites it and rounds would be appended to the wrong trace).

## Phase 2 — Implement (TDD, no exceptions)

**REQUIRED SUB-SKILL:** `superharness:test-driven-development`

For each task in the plan:

1. **RED** — write the failing test first. Run it. Confirm it fails for the expected reason.
2. **GREEN** — write the minimal implementation. Run the test. Confirm it passes.
3. **REFACTOR** — clean up while keeping tests green.
4. **Commit** with a descriptive message.

If you wrote implementation code before its test: delete it, write the test, start over.
If anything behaves unexpectedly, switch to `superharness:systematic-debugging` —
no guess-and-patch fixes.

## Phase 3 — Verify

**REQUIRED SUB-SKILL:** `superharness:verification-before-completion`

- Run the FULL test suite, not just the new tests. Paste actual output.
- **Outcome marker.** Each time you run the test suite, before yielding control,
  write `superharness/trace/.state/outcome.json` (single-line JSON) describing the latest result:
  - all green → `{"outcome":"success","test_command":"<cmd>"}`
  - one or more failing → `{"outcome":"failure","test_command":"<cmd>","failing_tests":[{"name":"<test>","file":"<path>","message":"<assertion>"}],"notes":"<short>"}`
  - no tests this round (e.g. a clarifying question) → omit the marker; the round is recorded as `in_progress`.
  The Stop hook consumes this marker each round.
- Run linters/builds the project defines.
- Any failure → back to Phase 2 (or systematic-debugging). Never report partial success
  as success.

## Phase 4 — Review

**REQUIRED SUB-SKILL:** `superharness:requesting-code-review`

- Dispatch a code-reviewer subagent over the change (base SHA → head SHA) using the
  template in `superharness:requesting-code-review`.
- Fix Critical and Important issues (each fix goes through the TDD cycle again).
  Note Minor issues in the final report.

## Phase 5 — Report

Deliver a final summary containing:

- What was built/changed and where (file paths)
- Evidence: test commands run and their actual results
- Review outcome and what was fixed
- Assumptions made and any noted Minor issues / follow-ups

**Close the trace.** On final completion, write `superharness/trace/.state/outcome.json`
with `"task_status":"completed"` (or `"failed"` / `"abandoned"`) alongside the usual
outcome fields. The Stop hook records the final round, sets the trace `status`, and
removes `task.json`.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The goal is simple, skip the plan" | Fine — but never skip TDD or verification. |
| "Tests after coding just this once" | No. RED first, always. |
| "Full suite takes too long" | Run it anyway. That's the evidence. |
| "Review is overkill here" | Multi-file or behavior-changing work gets reviewed. |
