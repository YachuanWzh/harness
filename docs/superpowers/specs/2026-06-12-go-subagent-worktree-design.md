# Design: Subagent-Driven Implementation + Worktree Isolation for `go`

Date: 2026-06-12
Status: Approved (ready for implementation plan)

## Problem

`go` currently runs all five phases (Understand → Plan → Implement → Verify →
Review) inside the **main agent's single context**. For long autonomous runs
this causes two problems:

1. **Context bloat.** Code exploration, the plan, every TDD round, and review
   all accumulate in one conversation. The main agent's context degrades over a
   multi-hour run, which is exactly when `go` claims to shine.
2. **No rollback safety.** `go` commits directly on the current branch and works
   in the project's live working tree. A run that goes wrong leaves a trail of
   commits on the working branch with no clean undo.

superpowers solves both with two skills that superharness dropped during the
port: `subagent-driven-development` (fresh subagent per task keeps the
controller's context clean) and `using-git-worktrees` (isolated, disposable
workspace). This design brings adapted versions of both into superharness and
wires them into `go`.

## Goals

- Phase 2 implementation of each independent plan task runs in a **fresh
  subagent**, so the main agent keeps only plan + coordination + review context.
- `go` runs inside an **isolated git worktree/branch by default** (in git
  projects), so changes are rollback-safe.
- Both features **degrade gracefully**: non-git projects and trivial goals keep
  today's behavior; nothing blocks the user.
- The trace/resume core is **unaffected** — round granularity and reliability
  guarantees stay exactly as they are.

## Non-Goals

- Per-task two-stage review (spec-compliance + code-quality reviewer subagents).
  Decided against: quality is gated once by `go`'s existing Phase 4
  (`requesting-code-review`). Per-task review is self-review only.
- Parallel dispatch of multiple implementer subagents (kept sequential to avoid
  working-tree conflicts).
- Porting `executing-plans`, `dispatching-parallel-agents`, or
  `finishing-a-development-branch`. Out of scope for this change.
- Any change to the trace hooks (`stop.ps1`, `user-prompt-submit.ps1`,
  `trace-lib.ps1`) or the installer.

## Decisions (from brainstorming)

| Decision | Choice |
|----------|--------|
| Scope | Subagent-driven Phase 2 **and** git worktree isolation |
| Structure | New `superharness:subagent-driven-development` skill; `go` delegates to it |
| Per-task review | Light: per-task self-review only; final review stays at Phase 4 |
| Worktree default | In a git project, `go` **creates a worktree by default** (no consent prompt); non-git → work in place |

## Components

### 1. New skill: `superharness:using-git-worktrees`

Adapted, slimmed port of superpowers' skill. Path:
`template/plugins/superharness/skills/using-git-worktrees/SKILL.md`.

Behavior:

- **Step 0 — Detect existing isolation.** Compare `git rev-parse --git-dir`
  with `--git-common-dir`; if they differ (and not a submodule, guarded via
  `git rev-parse --show-superproject-working-tree`), already in a worktree —
  skip creation, go to setup.
- **Step 1a — Native tool.** If a native worktree tool exists (e.g.
  `EnterWorktree`), use it and skip the git fallback.
- **Step 1b — Git fallback.** `git worktree add .worktrees/<branch> -b <branch>`.
  Verify `.worktrees` is gitignored first (`git check-ignore`); if not, add it
  to `.gitignore` and commit before creating.
- **Default-create semantics (superharness-specific).** Unlike superpowers
  (which asks consent), in a git project the skill **creates a worktree by
  default** because `go` invokes it for autonomous, auto-committing runs. The
  skill still honors an explicit user preference to work in place.
- **Graceful degradation (critical).** If the project is **not a git repo**, or
  `git worktree add` fails (permission/sandbox), announce it and **work in
  place**. superharness installs into arbitrary project directories — many are
  not git repos — so "no git" is a first-class, non-blocking path.
- **Setup + baseline.** Auto-detect and run project setup (npm/pip/cargo/go),
  then run the test suite to confirm a clean baseline before implementing.
- Namespace is `superharness:`; the skill references only skills that exist in
  this project. No `superpowers:` strings (enforced by the existing dangling
  check in the test suite).

### 2. New skill: `superharness:subagent-driven-development`

Adapted port, simplified per the light-review decision. Path:
`template/plugins/superharness/skills/subagent-driven-development/SKILL.md`.

Behavior:

- **Controller setup.** Read the plan once, extract **all** tasks with full
  text and scene-setting context, create a TodoWrite item per task.
- **Per task (sequential):** dispatch **one fresh implementer subagent** with
  the complete task text + context. The subagent does **not** read the plan
  file — the controller hands it exactly what it needs. The implementer follows
  `superharness:test-driven-development` (RED → GREEN → REFACTOR → commit), runs
  that task's tests, **self-reviews**, and commits.
- **No per-task reviewer subagents.** Self-review is the only per-task gate.
  Whole-change quality is reviewed once by `go` Phase 4.
- **Status handling.** Implementer reports DONE / DONE_WITH_CONCERNS /
  NEEDS_CONTEXT / BLOCKED. Handle each (proceed / read concerns / supply context
  and re-dispatch / assess blocker — more context, stronger model, smaller
  split, or escalate). Never silently retry the same model unchanged.
- **Model selection.** Use the cheapest model that fits each task (mechanical
  1–2 file tasks → fast model; multi-file integration → standard; design/broad
  understanding → most capable).
- **Continuous execution.** Do not check in with the human between tasks. Stop
  only on unresolvable BLOCKED, genuine ambiguity, or all-tasks-complete.
- **Coupling fallback.** If plan tasks are tightly coupled (not independent),
  note it and fall back to inline implementation rather than forcing subagents.
- The implementer dispatch prompt template is **inlined** in the SKILL.md as a
  fenced block the controller fills in (keeps it a single file).

### 3. Edit `go/SKILL.md`

- **New Phase 0.5 — Isolate** (between Understand and Plan): delegate to
  `superharness:using-git-worktrees`. In a git project this creates a worktree
  by default; non-git or declined → work in place. The rest of the run
  (plan, trace, implementation, commits) happens wherever `go` now sits.
- **Phase 2 — Implement** rewritten: for a plan with multiple independent
  tasks, delegate to `superharness:subagent-driven-development`. For trivial
  1–2 step goals, the main agent implements inline with TDD (no subagent
  overhead). The TDD-always rule is unchanged.
- **Preserve existing keyword contracts** so current tests keep passing:
  `task.json`, `outcome.json`, `task_status`, "one active", and the RED/failing
  test language all remain present.

### 4. Edit `HARNESS.md`

Add two rows to the Available Skills table:

- `superharness:using-git-worktrees` — starting feature work that needs an
  isolated workspace, before implementation.
- `superharness:subagent-driven-development` — executing a multi-task plan with
  independent tasks in the current session.

### 5. Tests (`tests/run-tests.ps1`)

This repo is built TDD; add the assertions first (RED), then create the files
(GREEN). New assertions:

- `skills/using-git-worktrees/SKILL.md` exists; mentions the **no-git / work in
  place** degradation and `git worktree`.
- `skills/subagent-driven-development/SKILL.md` exists; mentions a fresh
  subagent per task and delegating to `test-driven-development`.
- `go/SKILL.md` references `using-git-worktrees` (Phase 0.5) and
  `subagent-driven-development` (Phase 2 delegation).
- `HARNESS.md` lists both new skills.
- The existing global "no dangling `superpowers:`" check (skills/**/*.md)
  already covers namespace correctness for the new files.

### 6. Documentation

- **README.md** — add two rows to the skills table; update the repo-structure
  skills line; update the `go` five-phase description to mention the Isolate
  phase and subagent-driven implementation.
- **技术方案文档.md** — update the skill count; add the Isolate + subagent
  stages to the §6 `go` flow diagram; add the two skills to the §9 directory
  tree; add a short subsection describing the subagent/worktree layer and the
  trace interaction.
- **CLAUDE.md** — left unchanged (intentionally terse).

## Data Flow / Trace Interaction

- `go` runs (by default) inside a worktree → the trace hooks' `$in.cwd` is the
  worktree path → `superharness/trace/` and `superharness/plans/` are written
  there, and travel with the branch when it merges back.
- Phase 2 implementer subagents work in the **same worktree** (shared cwd); they
  do TDD and commit there. They do **not** write trace markers.
- `outcome.json` is still written by the **main agent** in Phase 3 after running
  the full suite. The Stop hook (which fires on **main-agent** stop, not
  SubagentStop — that hook is not registered) records the round. Therefore trace
  granularity is unchanged: one round per main-agent turn.
- Incidental benefit: because trace state keys off `cwd`, two worktrees of the
  same project get independent trace state — concurrent `go` runs in separate
  worktrees no longer collide.

## Error Handling / Degradation

| Situation | Behavior |
|-----------|----------|
| Not a git repo | Work in place; announce; no worktree |
| `git worktree add` fails (sandbox/permission) | Work in place; announce |
| Already in a linked worktree | Reuse it; skip creation |
| Trivial 1–2 step goal | Main agent implements inline (no subagent) |
| Tightly-coupled plan tasks | Inline implementation fallback |
| Implementer BLOCKED | Controller: add context / stronger model / split / escalate — never blind retry |

## Testing Strategy

- PowerShell suite (`tests/run-tests.ps1`): presence + keyword assertions above.
- No Node changes (brainstorm server untouched).
- Evidence of done: `powershell -NoProfile -ExecutionPolicy Bypass -File
  tests\run-tests.ps1` passes fully, with real output pasted.

## Out of Scope / Follow-ups

- Hook-side mechanical outcome detection (parsing real test output instead of
  trusting the model-written `outcome.json`) — separate hardening item.
- Cross-platform (Node) rewrite of installer/hooks — separate strategic item.
- `finishing-a-development-branch` merge/PR gate — a natural next addition once
  worktrees exist, but not part of this change.
