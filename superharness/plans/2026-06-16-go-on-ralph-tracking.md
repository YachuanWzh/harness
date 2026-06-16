# Go-on-Ralph Task Tracking Implementation Plan

> **For agentic workers:** Execute this plan task-by-task under the superharness:go workflow, Phase 2 (strict TDD per task). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `go` workflow's old hook-based task trace (`superharness/trace/<slug>.json` + outcome markers + `resume` skill) entirely with the ralph state mechanism (`.current-task`, ralph `task.json`, `trace.jsonl`, `.ralph-state.json`), including in-run automatic retry capped at 5.

**Architecture:** The ralph library (`scripts/ralph-lib.ps1`, already shipped & tested) becomes the single source of truth for go task tracking. Recording is hybrid: the `go` skill writes rich execution events via `Add-RalphTrace` at phase/task boundaries (primary), and the `Stop` hook appends a fallback `round` heartbeat event each time control returns to the user (guaranteeing every round is recorded). `UserPromptSubmit` stashes the pending prompt under `superharness/ralph/.pending-prompt.json`. Verification failures auto-retry in the same run via `Add-RalphRetry`/`Test-RalphRetryExhausted` (cap 5). The old `trace-lib.ps1`, `superharness/trace/` deliverable, outcome markers, and the `resume` skill are deleted.

**Tech Stack:** Windows PowerShell 5.1, zero-dependency. Tests in `tests/run-tests.ps1` (custom `Assert-True` harness). Hooks are PowerShell scripts invoked by Claude Code with JSON on stdin.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `template/plugins/superharness/hooks/user-prompt-submit.ps1` | Rewrite | Stash `{ts,query}` to `superharness/ralph/.pending-prompt.json` via ralph-lib |
| `template/plugins/superharness/hooks/stop.ps1` | Rewrite | If `.current-task` exists, append a `round` heartbeat to `trace.jsonl`; consume pending prompt; no-op otherwise |
| `template/plugins/superharness/hooks/trace-lib.ps1` | **Delete** | Old shared trace helpers — superseded by ralph-lib |
| `template/plugins/superharness/hooks/hooks.json` | Keep | Still registers SessionStart + UserPromptSubmit + Stop (paths unchanged) |
| `template/plugins/superharness/skills/go/SKILL.md` | Modify (trace sections) | Drive ralph: `.current-task`, ralph `task.json`, `trace.jsonl`, auto-retry cap 5 |
| `template/plugins/superharness/skills/resume/SKILL.md` | **Delete** | Manual resume replaced by in-run auto-retry |
| `template/plugins/superharness/HARNESS.md` | Modify | Drop `resume` from skill table if listed |
| `lib/install.ps1` | Modify | Ensure target `.gitignore` ignores `superharness/ralph/` |
| `tests/run-tests.ps1` | Modify | Replace test groups 11a/11b/12/13/14/15/16/17 with ralph-hook + ralph-go-doc + gitignore tests; keep 17a–17f, 18 |
| `README.md` / `技术方案文档.md` | Modify (light) | Describe go-on-ralph; remove stale old-trace description |

Notes that apply to every hook rewrite:
- Hooks dot-source ralph-lib via `Join-Path $PSScriptRoot '..\scripts\ralph-lib.ps1'` (hooks/ and scripts/ are siblings under the plugin root).
- Hooks read stdin inline (no trace-lib), wrap in try/catch, and **always `exit 0`**.
- ralph-lib exports used: `Get-RalphDir`, `Get-RalphIso`, `Write-RalphJson`, `Read-RalphJson`, `Get-RalphCurrentTask`, `Get-RalphTasks`, `Add-RalphTrace`, `Get-RalphTraceTail`.

---

## Task 1: UserPromptSubmit → ralph pending prompt

**Files:**
- Modify: `template/plugins/superharness/hooks/user-prompt-submit.ps1`
- Test: `tests/run-tests.ps1` (replace group 12)

- [ ] **Step 1: Replace test group 12 with the ralph pending-prompt test**

Replace the block headed `# ----- ... Test group 12: UserPromptSubmit behavior` (currently lines ~404–414) with:

```powershell
# ---------------------------------------------------------------- Test group 12: UserPromptSubmit behavior
Write-Host "`n[12] user-prompt-submit.ps1 stashes the pending round under superharness/ralph/"
$cwd12 = New-TempProject
$ex12 = Invoke-HookJson (Join-Path $plugin 'hooks\user-prompt-submit.ps1') @{ cwd = $cwd12; session_id = 's1'; prompt = 'hello world' }
Assert-True ($ex12 -eq 0) "user-prompt-submit exits 0"
$pf12 = Join-Path $cwd12 'superharness\ralph\.pending-prompt.json'
Assert-True (Test-Path $pf12) "writes superharness/ralph/.pending-prompt.json"
$pj12 = $null; try { $pj12 = Get-Content $pf12 -Raw | ConvertFrom-Json } catch {}
Assert-True ($null -ne $pj12 -and $pj12.query -eq 'hello world') "pending-prompt captures the user query"
Assert-True ($null -ne $pj12 -and $pj12.ts -match '^\d{4}-\d{2}-\d{2}T') "pending-prompt captures an ISO timestamp"
Remove-Item $cwd12 -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run group 12 to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: FAIL on "writes superharness/ralph/.pending-prompt.json" (old hook writes to `superharness/trace/.state/`).

- [ ] **Step 3: Rewrite the hook**

Full new contents of `user-prompt-submit.ps1`:

```powershell
# UserPromptSubmit hook: stash the pending round's user query + timestamp under
# superharness/ralph/ so the Stop hook can record a round even if the go skill
# wrote no execution event. Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\scripts\ralph-lib.ps1')
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $in = $raw | ConvertFrom-Json
    $cwd = $in.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }
    $pending = [ordered]@{ ts = (Get-RalphIso); query = [string]$in.prompt }
    Write-RalphJson (Join-Path (Get-RalphDir $cwd) '.pending-prompt.json') $pending
} catch { }
exit 0
```

- [ ] **Step 4: Run group 12 to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: group 12 PASS. (Other old-hook groups still fail — fixed in later tasks.)

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/hooks/user-prompt-submit.ps1 tests/run-tests.ps1
git commit -m "feat(go): UserPromptSubmit stashes pending prompt under superharness/ralph/"
```

---

## Task 2: Stop hook → trace.jsonl round heartbeat

**Files:**
- Modify: `template/plugins/superharness/hooks/stop.ps1`
- Test: `tests/run-tests.ps1` (replace groups 11a, 11b, 13, 14)

- [ ] **Step 1: Add a pending-prompt test helper**

After the `New-TraceState` helper (lines ~43–51), the old helper becomes unused; replace `New-TraceState` with:

```powershell
function Set-RalphPendingPrompt {
    param([string]$Cwd, [string]$Query, [string]$Ts = '2026-06-16T10:00:00+08:00')
    $dir = Join-Path $Cwd 'superharness\ralph'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $u = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $dir '.pending-prompt.json'), (ConvertTo-Json @{ ts = $Ts; query = $Query } -Compress), $u)
}
```

- [ ] **Step 2: Replace groups 11a, 11b, 13, 14 with ralph-hook tests**

Replace everything from `# ----- ... Test group 11a` through the end of group 14 (lines ~396–514, EXCLUDING the group 12 block already rewritten in Task 1 — keep group 12 where it is) with the consolidated block below. Practically: delete old 11a; delete old 11b/13/14; keep the new group 12 from Task 1; then insert this after group 12.

```powershell
# ---------------------------------------------------------------- Test group 11: trace hooks install
Write-Host "`n[11] Installer registers SessionStart + UserPromptSubmit + Stop and ships ralph-lib"
$hk = Get-Content (Join-Path $plugin 'hooks\hooks.json') -Raw | ConvertFrom-Json
Assert-True ($null -ne $hk.hooks.SessionStart) "hooks.json still registers SessionStart"
Assert-True ($null -ne $hk.hooks.UserPromptSubmit) "hooks.json registers a UserPromptSubmit hook"
Assert-True ($null -ne $hk.hooks.Stop) "hooks.json registers a Stop hook"
Assert-True (Test-Path (Join-Path $plugin 'hooks\user-prompt-submit.ps1')) "ships hooks/user-prompt-submit.ps1"
Assert-True (Test-Path (Join-Path $plugin 'hooks\stop.ps1')) "ships hooks/stop.ps1"
Assert-True (Test-Path (Join-Path $plugin 'scripts\ralph-lib.ps1')) "ships scripts/ralph-lib.ps1 for the hooks"
Assert-True (-not (Test-Path (Join-Path $plugin 'hooks\trace-lib.ps1'))) "old hooks/trace-lib.ps1 is gone"

# dot-source ralph-lib so the test process can assert on ralph state
. (Join-Path $plugin 'scripts\ralph-lib.ps1')

# ---------------------------------------------------------------- Test group 13: Stop hook records a round heartbeat
Write-Host "`n[13] stop.ps1 appends a round event to trace.jsonl when a go task is active"
$stop = Join-Path $plugin 'hooks\stop.ps1'

# 13a. active task -> round heartbeat appended, pending prompt consumed
$c1 = New-TempProject
Set-RalphCurrentTask -Root $c1 -TaskId '2026-06-16-x'
Initialize-RalphTasks -Root $c1 -Tasks @(@{ id = 1; name = 'a' }) -Phase 'implement'
Set-RalphPendingPrompt -Cwd $c1 -Query 'do the thing'
$e1 = Invoke-HookJson $stop @{ cwd = $c1; session_id = 's1' }
Assert-True ($e1 -eq 0) "stop exits 0 on an active task"
$tr1 = Join-Path $c1 'superharness\ralph\trace.jsonl'
Assert-True (Test-Path $tr1) "stop creates/append superharness/ralph/trace.jsonl"
$tail1 = @(Get-RalphTraceTail -Root $c1 -Count 1)
Assert-True ($tail1.Count -eq 1 -and $tail1[0].event -eq 'round') "appends a 'round' event"
Assert-True ($tail1[0].detail -eq 'do the thing') "round detail carries the user query"
Assert-True ($tail1[0].phase -eq 'implement') "round phase comes from task.json"
Assert-True (-not (Test-Path (Join-Path $c1 'superharness\ralph\.pending-prompt.json'))) "pending-prompt consumed"

# 13b. second round appends a second line (append-only)
Set-RalphPendingPrompt -Cwd $c1 -Query 'round two'
Invoke-HookJson $stop @{ cwd = $c1; session_id = 's1' } | Out-Null
$lines1 = @((Get-Content $tr1) | Where-Object { $_.Trim() -ne '' })
Assert-True ($lines1.Count -eq 2) "second round is appended (append-only ledger)"

# 13c. active task but no pending prompt -> still records a round (empty detail)
$c2 = New-TempProject
Set-RalphCurrentTask -Root $c2 -TaskId '2026-06-16-y'
$e2 = Invoke-HookJson $stop @{ cwd = $c2; session_id = 's2' }
Assert-True ($e2 -eq 0) "stop exits 0 with no pending prompt"
$tail2 = @(Get-RalphTraceTail -Root $c2 -Count 1)
Assert-True ($tail2.Count -eq 1 -and $tail2[0].event -eq 'round') "records a round even without a pending prompt"
Assert-True ($tail2[0].phase -eq 'go') "phase defaults to 'go' when no task.json"

# 13d. no .current-task -> no-op (no ledger, stray pending cleaned)
$c3 = New-TempProject
Set-RalphPendingPrompt -Cwd $c3 -Query 'stray'
$e3 = Invoke-HookJson $stop @{ cwd = $c3; session_id = 's3' }
Assert-True ($e3 -eq 0) "stop exits 0 when no task is active"
Assert-True (-not (Test-Path (Join-Path $c3 'superharness\ralph\trace.jsonl'))) "no trace.jsonl created without a task"
Assert-True (-not (Test-Path (Join-Path $c3 'superharness\ralph\.pending-prompt.json'))) "stray pending-prompt cleaned when no task"

# 13e. malformed / empty stdin -> exit 0, no throw
$e4a = '' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4a = $LASTEXITCODE
$e4b = 'not json' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4b = $LASTEXITCODE
Assert-True ($e4a -eq 0) "stop exits 0 on empty stdin"
Assert-True ($e4b -eq 0) "stop exits 0 on malformed stdin"

Remove-Item $c1, $c2, $c3 -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 3: Run groups 11/13 to verify they fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: FAIL — old `stop.ps1` writes `superharness/trace/<slug>.json`, not `trace.jsonl`; `trace-lib.ps1` still present.

- [ ] **Step 4: Rewrite the Stop hook**

Full new contents of `stop.ps1`:

```powershell
# Stop hook: when a go task is active (superharness/ralph/.current-task present),
# append a 'round' heartbeat to trace.jsonl so every user-facing round is recorded
# even if the go skill wrote no execution event this round. No-op otherwise.
# Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\scripts\ralph-lib.ps1')
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $in = $raw | ConvertFrom-Json
    $cwd = $in.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }

    $pendingPath = Join-Path (Get-RalphDir $cwd) '.pending-prompt.json'
    $ct = Get-RalphCurrentTask -Root $cwd
    if (-not $ct) {
        # Not tracking a go task — drop any stray pending prompt and bail.
        Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $pending = Read-RalphJson $pendingPath
    $query = if ($pending -and $pending.query) { [string]$pending.query } else { '' }
    $tasks = Get-RalphTasks -Root $cwd
    $phase = if ($tasks -and $tasks.phase) { [string]$tasks.phase } else { 'go' }

    Add-RalphTrace -Root $cwd -Phase $phase -Event 'round' -Detail $query
    Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
} catch { }
exit 0
```

- [ ] **Step 5: Run groups 11/13 to verify they pass**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: groups 11 and 13 PASS. (Group 15/16/17 still fail until later tasks; that's expected.)

- [ ] **Step 6: Commit**

```bash
git add template/plugins/superharness/hooks/stop.ps1 tests/run-tests.ps1
git commit -m "feat(go): Stop hook appends round heartbeat to ralph trace.jsonl"
```

---

## Task 3: Delete trace-lib.ps1

**Files:**
- Delete: `template/plugins/superharness/hooks/trace-lib.ps1`

(The "old trace-lib is gone" assertion was already added in Task 2 group 11. This task makes it pass and confirms no hook references trace-lib.)

- [ ] **Step 1: Confirm the failing assertion**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: "old hooks/trace-lib.ps1 is gone" FAILs (file still shipped).

- [ ] **Step 2: Delete the file and verify no references remain**

```bash
git rm template/plugins/superharness/hooks/trace-lib.ps1
grep -rn "trace-lib" template/ || echo "no trace-lib references"
```
Expected: no references in `template/` (hooks now dot-source `../scripts/ralph-lib.ps1`).

- [ ] **Step 3: Run the assertion to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: "old hooks/trace-lib.ps1 is gone" PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(go): delete trace-lib.ps1 (hooks now use ralph-lib)"
```

---

## Task 4: Rewrite the go skill's tracking sections to ralph + auto-retry

**Files:**
- Modify: `template/plugins/superharness/skills/go/SKILL.md`
- Test: `tests/run-tests.ps1` (replace group 15; drop the resume parts of group 17)

- [ ] **Step 1: Replace group 15 and the go part of group 17 with ralph-doc tests**

Replace group 15 (`# ----- ... Test group 15: go skill documents the trace markers`, lines ~516–521) with:

```powershell
# ---------------------------------------------------------------- Test group 15: go skill drives ralph tracking
Write-Host "`n[15] go skill drives the ralph state mechanism with in-run auto-retry"
$goMd = Get-Content (Join-Path $plugin 'skills\go\SKILL.md') -Raw
Assert-True ($goMd -match 'superharness/ralph') "go skill documents the superharness/ralph/ location"
Assert-True ($goMd -match 'Set-RalphCurrentTask' -and $goMd -match '\.current-task') "go skill sets the .current-task pointer"
Assert-True ($goMd -match 'Initialize-RalphTasks') "go skill seeds the ralph task list"
Assert-True ($goMd -match 'Add-RalphTrace' -and $goMd -match 'trace\.jsonl') "go skill records execution events to trace.jsonl"
Assert-True ($goMd -match 'Set-RalphTaskStatus') "go skill flips per-task status as work completes"
Assert-True ($goMd -match 'Add-RalphRetry' -and $goMd -match 'Test-RalphRetryExhausted') "go skill drives the retry counter"
Assert-True ($goMd -match '(?i)auto(matic)?[- ]?retr' -and $goMd -match '5') "go skill documents in-run auto-retry capped at 5"
Assert-True ($goMd -match '(?i)one active') "go skill documents one active go task per project"
Assert-True ($goMd -notmatch 'superharness/trace') "go skill no longer references the old superharness/trace/ mechanism"
Assert-True ($goMd -notmatch 'outcome\.json') "go skill no longer references outcome.json markers"
Assert-True ($goMd -match 'using-git-worktrees') "go skill still delegates isolation to using-git-worktrees"
Assert-True ($goMd -match 'subagent-driven-development') "go skill still delegates Phase 2 to subagent-driven-development"
```

Then delete the now-obsolete group 16 (resume) and group 17 entirely (lines ~523–541) — resume coverage is removed in Task 5; the "one active" assertion moved into group 15 above. (Group 18 and 17a–17f remain untouched.)

- [ ] **Step 2: Run group 15 to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: FAIL — go SKILL.md still documents `superharness/trace`, `outcome.json`, `task_status`.

- [ ] **Step 3: Rewrite the go SKILL.md tracking sections**

In `skills/go/SKILL.md`, replace the Phase 1 "Trace bootstrap" bullet, the Phase 3 "Outcome marker" bullet, and the Phase 5 "Close the trace" paragraph with ralph equivalents. Concretely:

Phase 1 — replace the trace bootstrap bullet with:

```markdown
- **Ralph tracking bootstrap.** At task start, dot-source `.claude/superharness/plugins/superharness/scripts/ralph-lib.ps1` and:
  - `Set-RalphCurrentTask -Root <project> -TaskId "<YYYY-MM-DD-slug>"` — writes the
    `superharness/ralph/.current-task` pointer (the single active-task marker).
  - `Initialize-RalphTasks -Root <project> -Tasks @(<one entry per plan task>) -Phase 'plan' -SprintTotal <N>`
    — seeds `superharness/ralph/task.json` with the plan's task list (each `pending`).
  - `Add-RalphTrace -Root <project> -Phase 'plan' -Event 'plan:done' -Detail '<one-line plan summary>'`.
  This activates tracking — the Stop hook records a `round` heartbeat each round only
  while `.current-task` exists. Track **one active go task per project** at a time:
  `.current-task` is the single active-task marker, so do not run concurrent `go` tasks
  in the same project (a new task overwrites the pointer).
```

Phase 2 — add a "Ralph trace note" replacing the old one:

```markdown
> Ralph trace note: at each task boundary, record execution events with
> `Add-RalphTrace -Root <project> -Phase 'implement' -Event '<task-id>:<red|green|commit>' -Detail '<short>'`,
> and flip status with `Set-RalphTaskStatus -Root <project> -Id <task-id> -Status in_progress|done`.
> Implementer subagents do not write trace markers; the main agent records them.
```

Phase 3 — replace the "Outcome marker" bullet with an auto-retry block:

```markdown
- **Record the verification + auto-retry (cap 5).** After running the FULL suite:
  - All green → `Add-RalphTrace -Root <project> -Phase 'verify' -Event 'verify:success' -Detail '<test cmd>'`,
    `Set-RalphTaskStatus` the task to `done`, then `Reset-RalphRetry -Root <project>`.
  - One or more failing → `Add-RalphTrace -Root <project> -Phase 'verify' -Event 'verify:failure' -Detail '<failing test + assertion>'`,
    then `Add-RalphRetry -Root <project>`. If `Test-RalphRetryExhausted -Root <project>`
    returns true (counter hit the cap of 5), **stop and report** — do not loop forever.
    Otherwise **automatically retry in this same run**: go back to Phase 2 via
    `superharness:systematic-debugging` (reproduce → root cause → fix → re-verify).
    This is an autonomous retry loop, not a blind re-run, and it does not pause to ask.
```

Phase 5 — replace the "Close the trace" paragraph with:

```markdown
**Close the trace.** On final completion, record the terminal event and status:
`Add-RalphTrace -Root <project> -Phase 'done' -Event 'task:completed' -Detail '<summary>'`
(or `task:failed` / `task:abandoned`), mark the remaining tasks `done` via
`Set-RalphTaskStatus`, and clear the active marker by removing
`superharness/ralph/.current-task`. The full execution history stays in
`superharness/ralph/trace.jsonl` (plus the per-round Stop-hook heartbeats) for cold-start
resume via `Get-RalphResumeContext`.
```

Also update the Red Flags table row and any prose that still says "Stop hook" / "task.json" in the old sense so the file no longer contains the strings `superharness/trace` or `outcome.json`.

- [ ] **Step 4: Run group 15 to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: group 15 PASS. (Group 16/resume removed; group 18 still PASS.)

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/skills/go/SKILL.md tests/run-tests.ps1
git commit -m "feat(go): drive ralph tracking + in-run auto-retry from the go skill"
```

---

## Task 5: Delete the resume skill

**Files:**
- Delete: `template/plugins/superharness/skills/resume/SKILL.md` (and the `resume` dir)
- Modify: `template/plugins/superharness/HARNESS.md` (drop the `resume` row if present)

- [ ] **Step 1: Add an installer assertion that resume is gone**

Append to test group 11 (after the trace-lib assertion):

```powershell
Assert-True (-not (Test-Path (Join-Path $plugin 'skills\resume\SKILL.md'))) "resume skill is removed (auto-retry replaces manual resume)"
```

- [ ] **Step 2: Run to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: FAIL — resume skill still shipped.

- [ ] **Step 3: Delete the skill and de-list it**

```bash
git rm -r template/plugins/superharness/skills/resume
grep -rn "resume" template/plugins/superharness/HARNESS.md template/plugins/superharness/skills/go/SKILL.md
```
Remove any `superharness:resume` / `/superharness:resume` row or reference found in `HARNESS.md` and `go/SKILL.md`.

- [ ] **Step 4: Run to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: the resume assertion PASS; no group references a deleted skill.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(go): remove resume skill (superseded by in-run auto-retry)"
```

---

## Task 6: Installer ignores superharness/ralph/ in the target project

**Files:**
- Modify: `lib/install.ps1`
- Test: `tests/run-tests.ps1` (new group 11g near the installer tests)

- [ ] **Step 1: Add the gitignore test**

Add after group 11 (uses the already-installed `$proj`):

```powershell
# ---------------------------------------------------------------- Test group 11g: installer ignores ralph runtime state
Write-Host "`n[11g] Installer ensures the target ignores superharness/ralph/ runtime state"
$giPath = Join-Path $proj '.gitignore'
Assert-True (Test-Path $giPath) "installer creates/updates .gitignore"
$giTxt = if (Test-Path $giPath) { Get-Content $giPath -Raw } else { '' }
Assert-True ($giTxt -match 'superharness/ralph/') ".gitignore ignores superharness/ralph/"
# idempotent: a second install must not duplicate the entry
Invoke-Installer -TargetDir $proj | Out-Null
$giTxt2 = Get-Content $giPath -Raw
$count = ([regex]::Matches($giTxt2, 'superharness/ralph/')).Count
Assert-True ($count -eq 1) "ralph ignore entry is not duplicated on re-install"
```

- [ ] **Step 2: Run to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: FAIL — installer does not touch `.gitignore`.

- [ ] **Step 3: Add gitignore management to install.ps1**

Before the final `Write-Host ""` / "installed" summary (after the CLAUDE.md block), add:

```powershell
# --- 5. Ensure the target ignores ralph runtime state (idempotent) ---
$GitignorePath = Join-Path $TargetDir '.gitignore'
$ignoreLine = 'superharness/ralph/'
$giExisting = if (Test-Path $GitignorePath) { [IO.File]::ReadAllText($GitignorePath, $utf8) } else { '' }
if ($giExisting -notmatch [regex]::Escape($ignoreLine)) {
    $prefix = if ($giExisting -and -not $giExisting.EndsWith("`n")) { "`r`n" } else { '' }
    $block = "$prefix# superharness ralph runtime state (per-task tracking + retry)`r`n$ignoreLine`r`n"
    [IO.File]::WriteAllText($GitignorePath, $giExisting + $block, $utf8)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: group 11g PASS (created + idempotent).

- [ ] **Step 5: Commit**

```bash
git add lib/install.ps1 tests/run-tests.ps1
git commit -m "feat(install): ignore superharness/ralph/ runtime state in target .gitignore"
```

---

## Task 7: Update README / 技术方案文档 to describe go-on-ralph

**Files:**
- Modify: `README.md`, `技术方案文档.md` (docs only; group 17f README ralph asserts must stay green)

- [ ] **Step 1: Update the docs**

In `README.md`, in the ralph section, add one paragraph that the `go` workflow now uses
the ralph files (`.current-task`, `task.json`, `trace.jsonl`, `.ralph-state.json`) for
task tracking and in-run auto-retry (cap 5), replacing the old `superharness/trace/`
mechanism and the `resume` skill. Remove/rewrite any paragraph that still describes the
old `superharness/trace/<slug>.json` go trace or the `resume` skill. Do the same trim in
`技术方案文档.md`. Keep every string that group 17f asserts (`superharness/ralph/`,
`.current-task`, `trace.jsonl`, `.ralph-state.json`, `Get-RalphResumeContext`).

- [ ] **Step 2: Run the full suite to verify docs tests stay green**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
Expected: group 17f PASS; full suite green.

- [ ] **Step 3: Commit**

```bash
git add README.md 技术方案文档.md
git commit -m "docs: describe go-on-ralph task tracking and retire the old trace mechanism"
```

---

## Final verification

- [ ] Run the FULL suite: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1` → **0 failed**, and paste the `=== Results: N passed, 0 failed ===` line.
- [ ] `grep -rn "superharness/trace\|trace-lib\|outcome.json\|skills/resume" template/ lib/` → no stale references (docs may mention them only as "retired").
- [ ] Code review (Phase 4) over base SHA → head SHA.
