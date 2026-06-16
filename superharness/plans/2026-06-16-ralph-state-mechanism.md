# Ralph State Mechanism — Implementation Plan

> Execute under superharness:go Phase 2 (strict TDD per task). Steps use checkbox tracking.

**Goal:** Implement a Ralph-style resumable autonomous-task mechanism built on four
runtime files, plus a cold-start recovery flow, as a tested zero-dependency PowerShell
state library shipped with the superharness plugin.

**The four files (created at runtime under `<project>/superharness/ralph/`):**

| File | Role | Write rule |
|---|---|---|
| `.current-task` | one-line pointer to the active task | switching a task rewrites only this line |
| `task.json` | the task-list snapshot (status / phase / sprint / tasks[] / updated_at) | atomic overwrite; `updated_at` refreshed on every write |
| `trace.jsonl` | append-only ledger, one `{ts,phase,event,detail}` per line | append-only — never rewrite earlier lines |
| `.ralph-state.json` | retry counter `{retries,max,updated_at}`, cap 5 | atomic overwrite |

**`task.json` shape:**
```json
{"status":"planning","phase":"implement","sprint":{"current":0,"total":7},
 "tasks":[{"id":1,"name":"...","status":"pending"}],"updated_at":"2026-06-16T..."}
```
Each task carries an independent status (`pending`/`in_progress`/`done`) — the key to
idempotent resume: skip `done`, pick up the first not-`done`.

**Cold-start recovery flow (the flowchart):** a fresh agent →
read `.current-task` → read `task.json` (which tasks aren't done) →
read tail of `trace.jsonl` (what happened last) → check `git diff` (did code actually
change) → reconcile records vs. reality (**code wins**: fix `task.json`) →
resume from the first not-`done` task. Every work step: update `task.json` + append
`trace.jsonl`. The deterministic file-reading half is `Get-RalphResumeContext`; the
git reconciliation + status fix is the agent's judgment, using `Set-RalphTaskStatus`.

**Tech stack:** Windows PowerShell 5.1, zero-dependency. Library
`template/plugins/superharness/scripts/ralph-lib.ps1` (dot-sourceable). Tests in the
existing `tests/run-tests.ps1` assert harness — dot-source the installed copy into a
temp project root and call functions directly. `lib/install.ps1` copies the whole
`template/` tree, so the new script ships automatically.

**Conventions reused from `hooks/trace-lib.ps1`:** UTF-8-no-BOM writes, atomic
temp-then-move for JSON snapshots, `Read-JsonFile` returns `$null` on missing/malformed,
ISO-8601 timestamp `yyyy-MM-ddTHH:mm:sszzz`.

---

## File Structure

| File | Responsibility |
|---|---|
| `template/plugins/superharness/scripts/ralph-lib.ps1` | **Create.** All state functions. |
| `tests/run-tests.ps1` | **Modify.** Add test group 17 (ships + behavior) incrementally. |
| `.gitignore` | **Modify.** Ignore `superharness/ralph/` runtime state. |
| `README.md` | **Modify.** Document the mechanism + recovery flow. |

**Function inventory (`ralph-lib.ps1`):**
- Paths: `Get-RalphDir`
- `.current-task`: `Set-RalphCurrentTask`, `Get-RalphCurrentTask`
- `task.json`: `Initialize-RalphTasks`, `Get-RalphTasks`, `Get-RalphNextTask`, `Set-RalphTaskStatus`
- `trace.jsonl`: `Add-RalphTrace`, `Get-RalphTraceTail`
- `.ralph-state.json`: `Get-RalphRetryState`, `Add-RalphRetry`, `Test-RalphRetryExhausted`, `Reset-RalphRetry`
- recovery: `Get-RalphResumeContext`

---

## Task 1: Library scaffold + `.current-task` pointer

**Files:** Create `template/plugins/superharness/scripts/ralph-lib.ps1`; modify `tests/run-tests.ps1`.

- [ ] **RED** — In `tests/run-tests.ps1` before the cleanup block, add a `Ralph-Project`
  helper (temp dir) and test group 17a: assert the installer ships
  `scripts/ralph-lib.ps1`; dot-source it; assert `Set-RalphCurrentTask`/`Get-RalphCurrentTask`
  round-trip a single line, that the file is exactly one line (no extra newlines), and that
  re-setting overwrites (not appends).
- [ ] Run suite → RED (script missing).
- [ ] **GREEN** — Create `ralph-lib.ps1` with `Get-RalphDir`, internal path helpers, UTF8-no-BOM
  write/atomic helpers, `Set-RalphCurrentTask` (overwrite single line, ensure dir),
  `Get-RalphCurrentTask` (trimmed line or `$null`).
- [ ] Run suite → GREEN.
- [ ] Commit: `feat(ralph): .current-task pointer + library scaffold`.

## Task 2: `task.json` task list (init / get / next / set-status)

- [ ] **RED** — Test group 17b: `Initialize-RalphTasks` writes the documented shape
  (status/phase/sprint/tasks[]/updated_at), defaulting each task status to `pending`;
  `Get-RalphTasks` round-trips; `Get-RalphNextTask` returns the first not-`done` task and
  `$null` when all done; `Set-RalphTaskStatus` flips one task's status idempotently and
  refreshes `updated_at`; setting an already-`done` task is a no-op on order. Assert the
  written file is a single minified line.
- [ ] Run suite → RED.
- [ ] **GREEN** — Implement the four functions (validate status in the allowed set; atomic write).
- [ ] Run suite → GREEN.
- [ ] Commit: `feat(ralph): task.json task list with idempotent per-task status`.

## Task 3: `trace.jsonl` append-only ledger

- [ ] **RED** — Test group 17c: `Add-RalphTrace` appends one minified JSON line per call
  (`{ts,phase,event,detail}`); two calls produce exactly two lines; earlier line is byte-for-byte
  unchanged after the second append (append-only proof); `Get-RalphTraceTail -Count N` returns
  the last N parsed events in order.
- [ ] Run suite → RED.
- [ ] **GREEN** — Implement `Add-RalphTrace` (AppendAllText, UTF8-no-BOM, ensure file) and
  `Get-RalphTraceTail` (Get-Content -Tail, parse each line).
- [ ] Run suite → GREEN.
- [ ] Commit: `feat(ralph): append-only trace.jsonl ledger`.

## Task 4: `.ralph-state.json` retry counter (cap 5)

- [ ] **RED** — Test group 17d: `Get-RalphRetryState` defaults to `{retries:0,max:5}` when
  absent; `Add-RalphRetry` increments and persists; `Test-RalphRetryExhausted` is false below 5
  and true at 5; retries never exceed `max` (clamp); `Reset-RalphRetry` returns to 0.
- [ ] Run suite → RED.
- [ ] **GREEN** — Implement the four retry functions (atomic write, clamp at max).
- [ ] Run suite → GREEN.
- [ ] Commit: `feat(ralph): .ralph-state.json retry counter with cap 5`.

## Task 5: cold-start recovery context

- [ ] **RED** — Test group 17e: seed a project (current-task, task.json with a done + a pending
  task, two trace lines); `Get-RalphResumeContext` returns `current_task`, the `tasks` snapshot,
  `next_task` = first not-done, `last_trace` = last event, and `all_done` flag; with all tasks
  done it returns `all_done=$true` and `next_task=$null`; on an empty project it returns a
  well-formed object with `$null` fields (no throw).
- [ ] Run suite → RED.
- [ ] **GREEN** — Implement `Get-RalphResumeContext` assembling the file-based facts the agent
  needs to reconcile against `git diff`.
- [ ] Run suite → GREEN.
- [ ] Commit: `feat(ralph): cold-start resume context assembler`.

## Task 6: gitignore, docs, dogfood refresh

- [ ] Add `superharness/ralph/` to `.gitignore` (runtime state).
- [ ] Document the mechanism + recovery flow in `README.md` (match its mixed zh/en style):
  the four files, write rules, the function inventory, and the recovery flowchart with which
  function backs each step.
- [ ] Run the dogfood installer into the repo so `.claude/superharness/` picks up the new script.
- [ ] Run the FULL suite one last time → all green; `git status --short` shows no
  `superharness/ralph/` litter staged.
- [ ] Commit: `docs(ralph): document state mechanism & recovery; ignore runtime state`.

---

## Self-Review

- **Spec coverage:** `.current-task` rewrite-one-line → Task 1; `task.json` per-task status +
  updated_at refresh → Task 2; `trace.jsonl` append-only (earlier lines provably untouched) →
  Task 3; `.ralph-state.json` cap-5 retry → Task 4; recovery flowchart → Task 5 (`Get-RalphResumeContext`)
  + documented agent reconciliation → Task 6.
- **Idempotent resume:** `Get-RalphNextTask` skips `done`; `Set-RalphTaskStatus` is order-stable
  and idempotent — re-running a completed task is a no-op.
- **Single active marker:** `.current-task` holds exactly one task id; switching rewrites only it.
- **Placeholder scan:** no TBD/TODO; every function is specified with its test obligation.
