---
name: receiving-code-review
description: Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation
---

# Receiving Code Review

## Overview

Code review requires technical evaluation, not emotional performance.

**Core principle:** Verify before implementing. Ask before assuming. Technical
correctness over social comfort.

**Announce at start:** "Processing review feedback under receiving-code-review discipline."

## The Response Pattern

```
WHEN receiving code review feedback:

1. READ: Complete feedback without reacting
2. UNDERSTAND: Restate the requirement in your own words (or ask)
3. VERIFY: Check against codebase reality
4. EVALUATE: Technically sound for THIS codebase?
5. RESPOND: Technical acknowledgment or reasoned pushback
6. IMPLEMENT: One item at a time, test each (TDD cycle per fix)
```

## Forbidden Responses

**NEVER:**
- "You're absolutely right!" (performative agreement)
- "Great point!" / "Excellent feedback!" (performative)
- "Let me implement that now" (before verification)

**INSTEAD:**
- Restate the technical requirement
- Ask clarifying questions
- Push back with technical reasoning if wrong
- Just start working (actions > words)

## Handling Unclear Feedback

```
IF any item is unclear:
  STOP - do not implement anything yet
  ASK for clarification on the unclear items

WHY: Items may be related. Partial understanding = wrong implementation.
```

**Example:**
```
your human partner: "Fix issues 1-6 from the review"
You understand 1, 2, 3, 6. Unclear on 4, 5.

WRONG: Implement 1,2,3,6 now, ask about 4,5 later
RIGHT: "I understand items 1,2,3,6. Need clarification on 4 and 5 before proceeding."
```

## Source-Specific Handling

### From your human partner
- **Trusted** - implement after understanding
- **Still ask** if scope is unclear
- **No performative agreement**
- **Skip to action** or technical acknowledgment

### From a code-reviewer subagent (superharness:requesting-code-review)
```
BEFORE implementing a finding:
  1. Check: Technically correct for THIS codebase?
  2. Check: Breaks existing functionality or tests?
  3. Check: Is there a reason for the current implementation?
  4. Check: Does the reviewer have full context (it sees the diff, not your session)?

IF a finding seems wrong:
  Push back with technical reasoning (in the final report: finding, why it is
  wrong, evidence). For Critical/Important findings, do not skip the fix on a
  hunch — prove it is a false positive first.

IF you can't easily verify:
  Say so: "I can't confirm this without <X>. Should I investigate or proceed?"

IF a finding conflicts with your human partner's prior decisions:
  Stop and raise it with your human partner first.
```

**Rule of thumb:** Be skeptical of external feedback, but check it carefully —
skepticism cuts both ways, including against your own "that's wrong" reflex.

## YAGNI Check for "Professional" Suggestions

```
IF the reviewer suggests "implementing this properly" (more surface, storage, config):
  grep the codebase for actual usage

  IF unused: "This path isn't called anywhere. Remove it (YAGNI)?"
  IF used:   Then implement it properly
```

## Implementation Order

```
FOR multi-item feedback:
  1. Clarify anything unclear FIRST
  2. Then implement in this order:
     - Blocking issues (breaks, security) — Critical
     - Simple fixes (typos, imports, naming)
     - Complex fixes (refactoring, logic changes)
  3. Each fix goes through its own TDD cycle (RED test that captures the issue first)
  4. Re-run the full suite; verify no regressions
```

## When To Push Back

Push back when:
- The suggestion breaks existing functionality
- The reviewer lacks full context
- It violates YAGNI (unused feature)
- It is technically incorrect for this stack
- Legacy/compatibility reasons exist
- It conflicts with your human partner's architectural decisions

**How to push back:**
- Use technical reasoning, not defensiveness
- Ask specific questions
- Reference working tests/code as evidence
- Involve your human partner if the trade-off is architectural

**If you're uncomfortable pushing back:** Name that tension, then tell your
partner about the issue you saw. Honesty beats comfort.

## Acknowledging Correct Feedback

When the feedback IS correct:
```
OK  "Fixed. <what changed, where>"
OK  "Confirmed a real issue in <location> — fixed with a regression test."
OK  [Just fix it and show the result]

NOT "You're absolutely right!"
NOT "Great point!"
NOT Any gratitude expression
```

Just fix it. The code and the test show you heard the feedback.

## Gracefully Correcting Your Pushback

If you pushed back and were wrong:
```
OK  "You were right — I checked <X> and it does <Y>. Implementing now."
OK  "Verified and you're correct. My initial read was wrong because <reason>. Fixing."

NOT A long apology or defense of the original position
```

State the correction factually and move on.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Performative agreement | State the requirement or just act |
| Blind implementation | Verify against the codebase first |
| Batch without testing | One at a time, TDD each fix |
| Assuming the reviewer is right | Check whether it breaks things |
| Avoiding pushback | Technical correctness > comfort |
| Partial implementation | Clarify all items first |
| Can't verify, proceed anyway | State the limitation, ask for direction |

## Red Flags

**Never:**
- Implement review feedback you haven't verified against the code
- Agree performatively to a suggestion that breaks tests
- Skip a Critical finding because "the reviewer may be wrong" without checking
- Batch unrelated fixes under one untested change
