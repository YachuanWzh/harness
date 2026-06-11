<!-- SUPERHARNESS:BEGIN -->
## Superharness

This project uses **superharness** (loaded from `.claude/skills/superharness/` as the
`superharness@skills-dir` plugin). Its SessionStart hook injects `HARNESS.md` into every
session. If that context is missing, read `.claude/skills/superharness/HARNESS.md` now
and follow it for all engineering work.

- Run a task end-to-end: `/superharness:go <task goal>`
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
<!-- SUPERHARNESS:END -->