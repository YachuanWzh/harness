---
name: converge
description: Use when a go run has passed tests and code review but not yet finished - audits the implementation against the spec and plan, appends unconverged work as new tasks, and sinks the current-behavior spec so intent accumulates instead of evaporating with the session
---

# Converge — Spec Convergence Audit

## Overview

Tests passing does not mean you built the right thing. Converge closes the loop
between **what was asked** (spec / goal) and **what exists** (the diff), and then
makes that reconciliation durable: the verified behavior is written back as a
living spec so the next session, the next task, and the next person inherit
intent, not just code.

**Announce at start:** "Running the convergence audit (superharness:converge)."

**Core principle:** A run is finished only when every requirement is verifiably
`done` in the code, or the leftovers are explicitly appended as tasks. Never
silently pass.

## Inputs

1. **Spec** — in priority order:
   - a brainstorm design doc at `<state-root>/superharness/specs/YYYY-MM-DD-<topic>.md` for this feature, if one exists;
   - otherwise the go goal statement + the plan's Goal/Architecture header + Phase 0 assumptions.
2. **Plan** — `<state-root>/superharness/plans/YYYY-MM-DD-<slug>.md` including its Analysis Findings block.
3. **Implementation** — `git diff <base>...<head>` (or working tree if not a git repo) and the test suite names.

## Audit Procedure

```
FOR each requirement (or goal bullet / plan task intent):
  Locate the implementing code AND its tests in the diff.
  Classify exactly one of:
    done       - implemented and covered by a test you can name
    partial    - implemented but a stated scenario/edge from the spec has no code or test
    missing    - no implementation at all
    divergent  - implemented, but behavior differs from what the spec says
                 (check tests too: a green suite over the WRONG behavior is divergent)
```

Evidence rules: a requirement counts as `done` only if you can cite file/test
names — not because the task checkbox is ticked. "It was discussed" is not
evidence. Cite, or classify as partial/missing.

## Verdict

- All requirements `done` → verdict **CONVERGED**.
- Any partial/missing/divergent → verdict **NOT CONVERGED** with the itemized list.

### When NOT CONVERGED

1. Append each leftover as a **new task** — both to the plan file (new
   `Task N:` sections following the plan format) and to ralph via
   `Set-RalphTaskStatus`/`Initialize-RalphTasks` semantics (add the entries as
   `pending`). Record `converge:gap` in the trace with the item count.
2. Return to go Phase 2 and implement the appended tasks (strict TDD; divergent
   items get a failing test that captures the spec's stated behavior first).
3. Re-run this audit after the full suite is green again.
4. **Bounded loop:** converge retries share the ralph retry counter
   (`Add-RalphRetry` / `Test-RalphRetryExhausted`, cap 5). When exhausted, stop
   and report the open items honestly — do not loop forever and do not declare
   CONVERGED.

## Living Spec Sink (run only on CONVERGED)

Convergence is worth keeping. Before go Phase 5 finishes, sink a spec of **how
the system now behaves** for this slice of functionality:

- Path: `<state-root>/superharness/specs/YYYY-MM-DD-<slug>.md` (same slug as the
  plan). If a brainstorm design doc for this feature already exists, UPDATE it
  to match what was actually built instead of writing a second file.
- Format (requirements with concrete scenarios — readable by the next agent run):

```markdown
# <Feature> — Living Spec
<!-- SUPERHARNESS:CONVERGED plan=<plan-file> date=<YYYY-MM-DD> -->

## Requirement: <name>
The system SHALL <behavior>.

### Scenario: <name>
- WHEN <trigger>
- THEN <observable outcome, covered by test <test name>>
```

- One requirement per audited spec bullet; every scenario cites the test that
  pins it. This file is the cold-start truth for the next change to the area:
  `Get-RalphResumeContext` plus this spec beats archaeology through chat history.

## Report

Produce a compact audit table for the user / go final report:

| Requirement | Verdict | Evidence (files/tests) |
|-------------|---------|------------------------|
| ... | done/partial/missing/divergent | ... |

Plus: overall verdict, appended task IDs (if any), and the living-spec path (if
written).

## Red Flags

| Thought | Reality |
|---------|---------|
| "All tests green, obviously converged" | Green tests can pin the wrong behavior. Audit against the spec, not the suite. |
| "Close enough, we'll catch the rest later" | Later never comes. Append it as tasks NOW or say it is done and correct. |
| "The spec was just a chat message" | Then distill it — that is what the living spec file is for. |
| "Divergent is subjective" | If code and spec disagree, that is divergent; decide which is right with your human partner before sink-and-forget. |
