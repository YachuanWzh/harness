---
name: resume
description: Manual-only. Resume a superharness:go task from its trace file - reproduce the recorded failure, find the root cause in the offending code, fix it under TDD, and verify. ONLY invoke when the user explicitly runs /superharness:resume; never self-invoke.
disable-model-invocation: true
argument-hint: [slug or trace file path]
---

# Superharness Resume — 复现并修复失败的任务

**Target:** $ARGUMENTS

## Phase 0 — Load the trace

1. If `$ARGUMENTS` names a slug or a path, use `superharness/trace/<slug>.json`
   (or the given path). Otherwise pick the most recently updated file under
   `superharness/trace/` whose `status` is not `completed`.
2. If no such trace exists, tell your human partner there is nothing to resume and stop.
3. Read it. Summarize for your partner, then **stop and wait for confirmation**:
   - the original `goal`
   - the round history (n / outcome / query)
   - the last `failure` round's `failing_tests` (name, file, message) and `test_command`

**Do not change any code until your human partner confirms.** This is a hard gate —
resume never auto-retries.

## Phase 1 — Reproduce (RED)

Re-run the recorded `test_command` (or the specific `failing_tests`). Confirm they
still fail for the recorded reason. If they now pass, report that the failure no
longer reproduces and ask whether to continue the original goal instead.

## Phase 2 — Root cause

**REQUIRED SUB-SKILL:** `superharness:systematic-debugging`

Find the **root cause** in the offending code — the failing test is your reproduction.
No guess-and-patch fixes; follow the 4-phase debugging process to a verified cause.

## Phase 3 — Fix (TDD)

**REQUIRED SUB-SKILL:** `superharness:test-driven-development`

The recorded failing test is already your RED. Make the minimal change that turns it
GREEN. If the bug revealed a missing case, add the failing test for it first.

## Phase 4 — Verify

**REQUIRED SUB-SKILL:** `superharness:verification-before-completion`

Run the FULL test suite and paste the actual output. Update the outcome marker
(`superharness/trace/.state/outcome.json`) so the trace records this attempt:
`"task_status":"completed"` once green, or another `failure` round if still red.

## Phase 5 — Report

Summarize: the root cause found, the fix and where, the verification output, and the
updated trace status.
