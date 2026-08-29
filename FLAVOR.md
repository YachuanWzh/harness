

<!-- flavor-code:start -->
## Overview

- Project: superharness
- Languages: JavaScript
- Package manager: not detected

## Layout

- `lib`
- `tests`

## Build

No verified build command detected.

## Test

No verified test command detected.

## Quality

No verified lint or format command detected.

## Conventions

- Follow `CLAUDE.md`.

## Cautions

- Do not read or copy secrets from environment files.
- Do not inspect dependency directories or generated output unless explicitly required.
<!-- flavor-code:end -->

<!-- SUPERHARNESS:FLAVOR-BEGIN -->
## Superharness

This project has **superharness** installed as a flavor-code plugin under
`.flavor/plugins/superharness/`. It registers a skill root plus eight session,
planning, and subagent lifecycle hooks. On flavor-code 1.2.20+, SessionStart
injects `HARNESS.md` into the persistent context and the host `Skill` tool
loads required sub-skills during `/go`. Ralph checkpoints live under
`.flavor/superharness/ralph/` and remain resumable across host sessions.

Installed skills: `brainstorm`, `converge`, `finishing-a-development-branch`, `go`, `light`, `onboarding`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `verification-before-completion`, `writing-plans`

Key capabilities:
- **go** -- Drive a task end-to-end under strict TDD + verification + code review discipline.
- **light** -- Lightweight mode for small focused tasks: TDD with exemptions, real-output verification, no worktree/plan-file/ralph overhead.
- **brainstorm** -- Explore requirements with a live browser mind map (manual trigger only).
- **onboarding** -- Deep-analyze the workspace's business logic for newcomers (manual trigger only): ONBOARDING.md + interactive module mind map, astgraph-powered with fallback, incremental via cache.
- **test-driven-development** -- RED-GREEN-REFACTOR cycle. No production code without a failing test first.
- **systematic-debugging** -- Root-cause tracing, defense-in-depth, no guess-and-patch.
- **verification-before-completion** -- Run the full test suite and show real output before claiming done.
- **requesting-code-review** -- Dispatch a reviewer subagent over the diff.
- **receiving-code-review** -- Verify review findings against the code before implementing; no performative agreement, no blind fixes.
- **converge** -- Audit implementation vs spec/plan after review; append leftovers as tasks and sink a living spec (go Phase 4.5).
- **writing-plans** -- Break down multi-step work into bite-sized TDD tasks.
- **using-git-worktrees** -- Isolate work in a disposable workspace.
- **subagent-driven-development** -- Execute multi-task plans with parallel subagents.

Usage in flavor-code: `/<skill-name> <args>`, e.g. `/go refactor login module` or `/brainstorm payment plan`.

### Latest update (v1.1.1)

- `onboarding` is now manual-trigger only: it runs when you explicitly invoke `/onboarding` (or `/superharness:onboarding`) and never starts on its own when you ask to explore or understand a project.
<!-- SUPERHARNESS:FLAVOR-END -->
