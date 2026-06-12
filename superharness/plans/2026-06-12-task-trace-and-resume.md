# Task-Execution Trace & Resume Implementation Plan

> **For agentic workers:** Execute this plan task-by-task under the superharness:go workflow, Phase 2 (strict TDD per task). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every `superharness:go` round that yields control to the user as a per-task single-line minified JSON trace, and add `/superharness:resume` that drives a recorded failure through reproduce → root-cause → fix → verify.

**Architecture:** Two PowerShell hooks own the record: `UserPromptSubmit` stashes each round's `{ts, query}` unconditionally; `Stop` composes the round and appends it to `superharness/trace/<slug>.json`. The `go` skill writes a small `outcome.json` marker after running tests; the `Stop` hook reads it to decide success/failure (defaulting to `in_progress` when absent, so requirement 1 holds even if the marker is never written). Resume is a manual-only skill.

**Tech Stack:** Windows PowerShell 5.1, zero-dependency. Tests live in `tests/run-tests.ps1` (existing in-house assert harness). Plugin source in `template/plugins/superharness/`; `lib/install.ps1` copies the whole template tree, so new files flow through automatically.

---

## File Structure

| File | Responsibility |
|---|---|
| `template/plugins/superharness/hooks/trace-lib.ps1` | **Create.** Shared helpers: stdin read, path builders, ISO timestamp, atomic minified JSON write, safe JSON read. |
| `template/plugins/superharness/hooks/user-prompt-submit.ps1` | **Create.** UserPromptSubmit hook — writes `.state/pending-prompt.json`. |
| `template/plugins/superharness/hooks/stop.ps1` | **Create.** Stop hook — composes a round, appends to the trace file, consumes markers. |
| `template/plugins/superharness/hooks/hooks.json` | **Modify.** Register `UserPromptSubmit` and `Stop` alongside `SessionStart`. |
| `template/plugins/superharness/skills/go/SKILL.md` | **Modify.** Add trace bootstrap + outcome-marker + close instructions. |
| `template/plugins/superharness/skills/resume/SKILL.md` | **Create.** `/superharness:resume` skill (manual-only). |
| `tests/run-tests.ps1` | **Modify.** Add helpers + new installer/behavioral test groups. |
| `.gitignore` | **Modify.** Ignore `superharness/trace/.state/`. |
| `README.md` | **Modify.** Document the feature. |

**State files (created at runtime in the target project, under `cwd` from the hook input):**
```
superharness/trace/<slug>.json              # deliverable: per-task single-line minified JSON
superharness/trace/.state/pending-prompt.json   # hook writes: {ts, query}
superharness/trace/.state/task.json             # go writes at task start: {task_id, slug, goal, started_at}
superharness/trace/.state/outcome.json          # go writes after tests: {outcome, summary, failing_tests, test_command, notes, task_status?}
```

---

## Task 1: Shared lib + UserPromptSubmit hook

**Files:**
- Create: `template/plugins/superharness/hooks/trace-lib.ps1`
- Create: `template/plugins/superharness/hooks/user-prompt-submit.ps1`
- Modify: `template/plugins/superharness/hooks/hooks.json`
- Modify: `tests/run-tests.ps1` (add helpers + test groups 11a, 12)

- [ ] **Step 1: Write the failing tests**

In `tests/run-tests.ps1`, add these two helper functions immediately after the `Get-PluginDir` function (≈ line 41):

```powershell
function New-TraceState {
    param([string]$Cwd, $Task, $Prompt, $Outcome)
    $sd = Join-Path $Cwd 'superharness\trace\.state'
    New-Item -ItemType Directory -Force $sd | Out-Null
    $u = New-Object System.Text.UTF8Encoding($false)
    if ($Task)    { [IO.File]::WriteAllText((Join-Path $sd 'task.json'),           (ConvertTo-Json -InputObject $Task    -Depth 12 -Compress), $u) }
    if ($Prompt)  { [IO.File]::WriteAllText((Join-Path $sd 'pending-prompt.json'), (ConvertTo-Json -InputObject $Prompt  -Depth 12 -Compress), $u) }
    if ($Outcome) { [IO.File]::WriteAllText((Join-Path $sd 'outcome.json'),        (ConvertTo-Json -InputObject $Outcome -Depth 12 -Compress), $u) }
}

function Invoke-HookJson {
    param([string]$ScriptPath, $InputObj)
    $json = ConvertTo-Json -InputObject $InputObj -Depth 12 -Compress
    $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath | Out-Null
    return $LASTEXITCODE
}
```

Then insert these test groups in `tests/run-tests.ps1` immediately before the `# ---- cleanup + summary` block (≈ line 379):

```powershell
# ---------------------------------------------------------------- Test group 11a: trace hook install (UserPromptSubmit)
Write-Host "`n[11a] Installer registers UserPromptSubmit + ships trace-lib and the prompt hook"
$hk = Get-Content (Join-Path $plugin 'hooks\hooks.json') -Raw | ConvertFrom-Json
Assert-True ($null -ne $hk.hooks.UserPromptSubmit) "hooks.json registers a UserPromptSubmit hook"
Assert-True ($null -ne $hk.hooks.SessionStart) "hooks.json still registers SessionStart"
Assert-True (Test-Path (Join-Path $plugin 'hooks\trace-lib.ps1')) "ships hooks/trace-lib.ps1"
Assert-True (Test-Path (Join-Path $plugin 'hooks\user-prompt-submit.ps1')) "ships hooks/user-prompt-submit.ps1"

# ---------------------------------------------------------------- Test group 12: UserPromptSubmit behavior
Write-Host "`n[12] user-prompt-submit.ps1 stashes the pending round"
$cwd12 = New-TempProject
$ex12 = Invoke-HookJson (Join-Path $plugin 'hooks\user-prompt-submit.ps1') @{ cwd = $cwd12; session_id = 's1'; prompt = 'hello world' }
Assert-True ($ex12 -eq 0) "user-prompt-submit exits 0"
$pf12 = Join-Path $cwd12 'superharness\trace\.state\pending-prompt.json'
Assert-True (Test-Path $pf12) "writes .state/pending-prompt.json"
$pj12 = $null; try { $pj12 = Get-Content $pf12 -Raw | ConvertFrom-Json } catch {}
Assert-True ($null -ne $pj12 -and $pj12.query -eq 'hello world') "pending-prompt captures the user query"
Assert-True ($null -ne $pj12 -and $pj12.ts -match '^\d{4}-\d{2}-\d{2}T') "pending-prompt captures an ISO timestamp"
Remove-Item $cwd12 -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run the suite to verify the new asserts fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — `hooks.json registers a UserPromptSubmit hook` and the group 12 asserts fail (files don't exist yet).

- [ ] **Step 3: Create `template/plugins/superharness/hooks/trace-lib.ps1`**

```powershell
# Shared helpers for the trace hooks (user-prompt-submit.ps1, stop.ps1).
# Consumers wrap their work in try/catch and always exit 0 — a broken trace
# hook must never block a Claude Code session.

function Read-HookInput {
    # Reads stdin and parses JSON. Returns $null on empty/malformed input.
    try {
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json
    } catch { return $null }
}

function Get-TraceDir { param([string]$Cwd) Join-Path $Cwd 'superharness\trace' }
function Get-StateDir { param([string]$Cwd) Join-Path (Get-TraceDir $Cwd) '.state' }
function Now-Iso { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-MinifiedJson {
    # Atomic single-line write: temp file then move-replace.
    param([string]$Path, $Object)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $json = ConvertTo-Json -InputObject $Object -Depth 12 -Compress
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $Path -Force
}
```

- [ ] **Step 4: Create `template/plugins/superharness/hooks/user-prompt-submit.ps1`**

```powershell
# UserPromptSubmit hook: stash the pending round's user query + timestamp so
# that "every round is recorded" holds unconditionally — independent of whether
# Claude later writes an outcome marker. Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'trace-lib.ps1')
try {
    $in = Read-HookInput
    if (-not $in) { exit 0 }
    $cwd = $in.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }
    $pending = @{ ts = (Now-Iso); query = [string]$in.prompt }
    Write-MinifiedJson (Join-Path (Get-StateDir $cwd) 'pending-prompt.json') $pending
} catch { }
exit 0
```

- [ ] **Step 5: Register the hook in `template/plugins/superharness/hooks/hooks.json`**

Replace the entire file with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.ps1\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-submit.ps1\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Run the suite to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`. (The installer reinstalls into temp projects from `template/`, picking up the new files.)

- [ ] **Step 7: Commit**

```bash
git add template/plugins/superharness/hooks/trace-lib.ps1 template/plugins/superharness/hooks/user-prompt-submit.ps1 template/plugins/superharness/hooks/hooks.json tests/run-tests.ps1
git commit -m "feat: UserPromptSubmit trace hook captures each round's query"
```

---

## Task 2: Stop hook — core (success / in_progress / no-op / resilience)

**Files:**
- Create: `template/plugins/superharness/hooks/stop.ps1`
- Modify: `template/plugins/superharness/hooks/hooks.json` (add `Stop`)
- Modify: `tests/run-tests.ps1` (add test groups 11b, 13)

- [ ] **Step 1: Write the failing tests**

Insert in `tests/run-tests.ps1` before the `# ---- cleanup + summary` block (after group 12):

```powershell
# ---------------------------------------------------------------- Test group 11b: Stop hook install
Write-Host "`n[11b] Installer registers Stop + ships stop.ps1"
$hk2 = Get-Content (Join-Path $plugin 'hooks\hooks.json') -Raw | ConvertFrom-Json
Assert-True ($null -ne $hk2.hooks.Stop) "hooks.json registers a Stop hook"
Assert-True (Test-Path (Join-Path $plugin 'hooks\stop.ps1')) "ships hooks/stop.ps1"

# ---------------------------------------------------------------- Test group 13: Stop hook core behavior
Write-Host "`n[13] stop.ps1 composes and persists a round"
$stop = Join-Path $plugin 'hooks\stop.ps1'

# 13a. success round -> "task completed"
$c1 = New-TempProject
New-TraceState -Cwd $c1 `
    -Task @{ task_id='2026-06-12-x'; slug='2026-06-12-x'; goal='G'; started_at='2026-06-12T10:00:00+08:00' } `
    -Prompt @{ ts='2026-06-12T10:01:00+08:00'; query='do the thing' } `
    -Outcome @{ outcome='success'; test_command='npm test' }
$e1 = Invoke-HookJson $stop @{ cwd=$c1; session_id='s1' }
$tf1 = Join-Path $c1 'superharness\trace\2026-06-12-x.json'
Assert-True ($e1 -eq 0) "stop exits 0 on a success round"
Assert-True (Test-Path $tf1) "stop writes the per-task trace file"
$raw1 = if (Test-Path $tf1) { Get-Content $tf1 -Raw } else { '' }
Assert-True ($raw1 -notmatch "`n") "trace file is a single minified line"
$t1 = $null; try { $t1 = $raw1 | ConvertFrom-Json } catch {}
Assert-True ($null -ne $t1 -and @($t1.rounds).Count -eq 1) "trace has one round"
Assert-True ($null -ne $t1 -and @($t1.rounds)[0].outcome -eq 'success') "success round outcome is success"
Assert-True ($null -ne $t1 -and @($t1.rounds)[0].summary -eq 'task completed') "success round records 'task completed'"
Assert-True ($null -ne $t1 -and @($t1.rounds)[0].query -eq 'do the thing') "round carries the user query"
Assert-True (-not (Test-Path (Join-Path $c1 'superharness\trace\.state\pending-prompt.json'))) "pending-prompt consumed"
Assert-True (-not (Test-Path (Join-Path $c1 'superharness\trace\.state\outcome.json'))) "outcome marker consumed"

# 13b. missing outcome marker -> in_progress (requirement 1 holds without the marker)
$c2 = New-TempProject
New-TraceState -Cwd $c2 `
    -Task @{ task_id='t2'; slug='t2'; goal='G2'; started_at='2026-06-12T10:00:00+08:00' } `
    -Prompt @{ ts='2026-06-12T10:05:00+08:00'; query='clarify please' }
Invoke-HookJson $stop @{ cwd=$c2; session_id='s2' } | Out-Null
$t2 = Get-Content (Join-Path $c2 'superharness\trace\t2.json') -Raw | ConvertFrom-Json
Assert-True (@($t2.rounds)[0].outcome -eq 'in_progress') "round with no marker is logged as in_progress"
Assert-True (@($t2.rounds)[0].query -eq 'clarify please') "in_progress round still records the query"

# 13c. no task.json -> no-op (no trace file, stray prompt cleaned)
$c3 = New-TempProject
New-TraceState -Cwd $c3 -Prompt @{ ts='2026-06-12T10:00:00+08:00'; query='stray' }
$e3 = Invoke-HookJson $stop @{ cwd=$c3; session_id='s3' }
Assert-True ($e3 -eq 0) "stop exits 0 when no task is active"
Assert-True (-not (Test-Path (Join-Path $c3 'superharness\trace\.state\pending-prompt.json'))) "stray pending-prompt cleaned when no task"
Assert-True ((Get-ChildItem (Join-Path $c3 'superharness\trace') -Filter *.json -ErrorAction SilentlyContinue).Count -eq 0) "no trace file created without a task"

# 13d. malformed / empty stdin -> exit 0, no throw
$c4 = New-TempProject
$e4a = '' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4a = $LASTEXITCODE
$e4b = 'not json' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4b = $LASTEXITCODE
Assert-True ($e4a -eq 0) "stop exits 0 on empty stdin"
Assert-True ($e4b -eq 0) "stop exits 0 on malformed stdin"

# 13e. second round appends with incrementing round number
New-TraceState -Cwd $c1 `
    -Prompt @{ ts='2026-06-12T10:10:00+08:00'; query='round two' } `
    -Outcome @{ outcome='success'; test_command='npm test' }
Invoke-HookJson $stop @{ cwd=$c1; session_id='s1' } | Out-Null
$t1b = Get-Content $tf1 -Raw | ConvertFrom-Json
Assert-True (@($t1b.rounds).Count -eq 2) "second round is appended"
Assert-True (@($t1b.rounds)[1].n -eq 2) "second round is numbered 2"

Remove-Item $c1, $c2, $c3, $c4 -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run the suite to verify the new asserts fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — `hooks.json registers a Stop hook` and group 13 asserts fail (stop.ps1 missing).

- [ ] **Step 3: Create `template/plugins/superharness/hooks/stop.ps1`**

```powershell
# Stop hook: compose the round that just ended and append it to the per-task
# trace file. No-op unless a go task is active (.state/task.json present).
# Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'trace-lib.ps1')
try {
    $in = Read-HookInput
    if (-not $in) { exit 0 }
    $cwd = $in.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }

    $stateDir   = Get-StateDir $cwd
    $taskFile   = Join-Path $stateDir 'task.json'
    $promptFile = Join-Path $stateDir 'pending-prompt.json'
    $outcomeFile = Join-Path $stateDir 'outcome.json'

    $task = Read-JsonFile $taskFile
    if (-not $task) {
        # Not tracking a go task — clean any stray pending prompt and bail.
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $prompt = Read-JsonFile $promptFile
    $ts    = if ($prompt -and $prompt.ts) { $prompt.ts } else { Now-Iso }
    $query = if ($prompt) { $prompt.query } else { $null }

    $od = Read-JsonFile $outcomeFile
    $outcome = if ($od -and $od.outcome) { [string]$od.outcome } else { 'in_progress' }

    $traceFile = Join-Path (Get-TraceDir $cwd) ("{0}.json" -f $task.slug)
    $existing = Read-JsonFile $traceFile
    if ($existing) { $rounds = @($existing.rounds); $started = $existing.started_at }
    else           { $rounds = @();                 $started = $task.started_at }
    $n = $rounds.Count + 1

    if ($outcome -eq 'success') {
        $round = [ordered]@{ n=$n; ts=$ts; query=$query; outcome='success'; summary='task completed' }
        if ($od.test_command) { $round.test_command = [string]$od.test_command }
    } else {
        $round = [ordered]@{ n=$n; ts=$ts; query=$query; outcome='in_progress' }
        if ($od -and $od.summary) { $round.summary = [string]$od.summary }
    }

    $rounds = @($rounds) + $round
    $trace = [ordered]@{
        task_id    = $task.task_id
        goal       = $task.goal
        started_at = $started
        updated_at = (Now-Iso)
        status     = 'in_progress'
        rounds     = $rounds
    }
    Write-MinifiedJson $traceFile $trace

    Remove-Item $promptFile, $outcomeFile -Force -ErrorAction SilentlyContinue
} catch { }
exit 0
```

- [ ] **Step 4: Register the Stop hook in `template/plugins/superharness/hooks/hooks.json`**

Add a `Stop` entry after the `UserPromptSubmit` block (inside `hooks`). Full file:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.ps1\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-submit.ps1\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/stop.ps1\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Run the suite to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`.

- [ ] **Step 6: Commit**

```bash
git add template/plugins/superharness/hooks/stop.ps1 template/plugins/superharness/hooks/hooks.json tests/run-tests.ps1
git commit -m "feat: Stop trace hook records each round (success/in_progress)"
```

---

## Task 3: Stop hook — failure branch + task close

**Files:**
- Modify: `template/plugins/superharness/hooks/stop.ps1`
- Modify: `tests/run-tests.ps1` (add test group 14)

- [ ] **Step 1: Write the failing tests**

Insert in `tests/run-tests.ps1` before the `# ---- cleanup + summary` block (after group 13):

```powershell
# ---------------------------------------------------------------- Test group 14: Stop hook failure + close
Write-Host "`n[14] stop.ps1 records failures and closes the task"
$stopF = Join-Path $plugin 'hooks\stop.ps1'

# 14a. failure round -> failing_tests + query only, no full-dialogue blob
$cf = New-TempProject
New-TraceState -Cwd $cf `
    -Task @{ task_id='f1'; slug='f1'; goal='G'; started_at='2026-06-12T10:00:00+08:00' } `
    -Prompt @{ ts='2026-06-12T10:02:00+08:00'; query='make it pass' } `
    -Outcome @{ outcome='failure'; test_command='npm test';
                failing_tests=@(@{ name='adds two numbers'; file='sum.test.js'; message='expected 3 got 5' });
                notes='off-by-two' }
Invoke-HookJson $stopF @{ cwd=$cf; session_id='sf' } | Out-Null
$tF = Get-Content (Join-Path $cf 'superharness\trace\f1.json') -Raw | ConvertFrom-Json
$rF = @($tF.rounds)[0]
Assert-True ($rF.outcome -eq 'failure') "failure round outcome is failure"
Assert-True (@($rF.failing_tests)[0].name -eq 'adds two numbers') "failure round records the failing test name"
Assert-True (@($rF.failing_tests)[0].message -eq 'expected 3 got 5') "failure round records the failing test message"
Assert-True ($rF.query -eq 'make it pass') "failure round records the user query"
$rNames = $rF.PSObject.Properties.Name
Assert-True ($rNames -notcontains 'dialogue' -and $rNames -notcontains 'transcript') "failure round does not store full dialogue"

# 14b. task_status closes the trace and removes task.json
$cc = New-TempProject
New-TraceState -Cwd $cc `
    -Task @{ task_id='d1'; slug='d1'; goal='G'; started_at='2026-06-12T10:00:00+08:00' } `
    -Prompt @{ ts='2026-06-12T10:09:00+08:00'; query='ship it' } `
    -Outcome @{ outcome='success'; test_command='npm test'; task_status='completed' }
Invoke-HookJson $stopF @{ cwd=$cc; session_id='sc' } | Out-Null
$tC = Get-Content (Join-Path $cc 'superharness\trace\d1.json') -Raw | ConvertFrom-Json
Assert-True ($tC.status -eq 'completed') "task_status promotes trace status to completed"
Assert-True (-not (Test-Path (Join-Path $cc 'superharness\trace\.state\task.json'))) "task.json removed when task closes"

Remove-Item $cf, $cc -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run the suite to verify the new asserts fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — failure round is logged as `in_progress` (no `failing_tests`) and `status` stays `in_progress`.

- [ ] **Step 3: Update `template/plugins/superharness/hooks/stop.ps1`**

Replace the whole file with the final version (adds the `failure` branch and the `task_status` close):

```powershell
# Stop hook: compose the round that just ended and append it to the per-task
# trace file. No-op unless a go task is active (.state/task.json present).
# Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'trace-lib.ps1')
try {
    $in = Read-HookInput
    if (-not $in) { exit 0 }
    $cwd = $in.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }

    $stateDir   = Get-StateDir $cwd
    $taskFile   = Join-Path $stateDir 'task.json'
    $promptFile = Join-Path $stateDir 'pending-prompt.json'
    $outcomeFile = Join-Path $stateDir 'outcome.json'

    $task = Read-JsonFile $taskFile
    if (-not $task) {
        # Not tracking a go task — clean any stray pending prompt and bail.
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $prompt = Read-JsonFile $promptFile
    $ts    = if ($prompt -and $prompt.ts) { $prompt.ts } else { Now-Iso }
    $query = if ($prompt) { $prompt.query } else { $null }

    $od = Read-JsonFile $outcomeFile
    $outcome = if ($od -and $od.outcome) { [string]$od.outcome } else { 'in_progress' }

    $traceFile = Join-Path (Get-TraceDir $cwd) ("{0}.json" -f $task.slug)
    $existing = Read-JsonFile $traceFile
    if ($existing) { $rounds = @($existing.rounds); $started = $existing.started_at }
    else           { $rounds = @();                 $started = $task.started_at }
    $n = $rounds.Count + 1

    if ($outcome -eq 'success') {
        $round = [ordered]@{ n=$n; ts=$ts; query=$query; outcome='success'; summary='task completed' }
        if ($od.test_command) { $round.test_command = [string]$od.test_command }
    } elseif ($outcome -eq 'failure') {
        $round = [ordered]@{ n=$n; ts=$ts; query=$query; outcome='failure' }
        if ($od.test_command)  { $round.test_command  = [string]$od.test_command }
        if ($od.failing_tests) { $round.failing_tests = $od.failing_tests }
        if ($od.notes)         { $round.notes         = [string]$od.notes }
    } else {
        $round = [ordered]@{ n=$n; ts=$ts; query=$query; outcome='in_progress' }
        if ($od -and $od.summary) { $round.summary = [string]$od.summary }
    }

    $status = if ($od -and $od.task_status) { [string]$od.task_status } else { 'in_progress' }

    $rounds = @($rounds) + $round
    $trace = [ordered]@{
        task_id    = $task.task_id
        goal       = $task.goal
        started_at = $started
        updated_at = (Now-Iso)
        status     = $status
        rounds     = $rounds
    }
    Write-MinifiedJson $traceFile $trace

    if ($od -and $od.task_status) { Remove-Item $taskFile -Force -ErrorAction SilentlyContinue }
    Remove-Item $promptFile, $outcomeFile -Force -ErrorAction SilentlyContinue
} catch { }
exit 0
```

- [ ] **Step 4: Run the suite to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`.

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/hooks/stop.ps1 tests/run-tests.ps1
git commit -m "feat: Stop trace hook records failing tests and closes the task"
```

---

## Task 4: `go` skill writes the trace markers

**Files:**
- Modify: `template/plugins/superharness/skills/go/SKILL.md`
- Modify: `tests/run-tests.ps1` (add test group 15)

- [ ] **Step 1: Write the failing tests**

Insert in `tests/run-tests.ps1` before the `# ---- cleanup + summary` block (after group 14):

```powershell
# ---------------------------------------------------------------- Test group 15: go skill documents the trace markers
Write-Host "`n[15] go skill writes task.json / outcome.json markers"
$goMd = Get-Content (Join-Path $plugin 'skills\go\SKILL.md') -Raw
Assert-True ($goMd -match 'task\.json') "go skill documents the task.json bootstrap marker"
Assert-True ($goMd -match 'outcome\.json') "go skill documents the outcome.json marker"
Assert-True ($goMd -match 'task_status') "go skill documents closing the trace with task_status"
```

- [ ] **Step 2: Run the suite to verify the new asserts fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — the three group 15 asserts fail (go skill has no marker docs yet).

- [ ] **Step 3: Edit `template/plugins/superharness/skills/go/SKILL.md`**

Add a trace-bootstrap bullet to **Phase 1 — Plan**. After the existing line (line 38):

```markdown
- Create one TodoWrite/Task item per plan task and keep statuses current.
```

insert:

```markdown
- **Trace bootstrap.** At task start, write `superharness/trace/.state/task.json`
  (single-line JSON) with `{"task_id":"<YYYY-MM-DD-slug>","slug":"<YYYY-MM-DD-slug>","goal":"<one-line goal>","started_at":"<ISO8601>"}`.
  This activates per-round tracking — the Stop hook is a no-op until it exists.
```

Add an outcome-marker bullet to **Phase 3 — Verify**. After the existing line (line 59):

```markdown
- Run the FULL test suite, not just the new tests. Paste actual output.
```

insert:

```markdown
- **Outcome marker.** Each time you run the test suite, before yielding control,
  write `superharness/trace/.state/outcome.json` (single-line JSON) describing the latest result:
  - all green → `{"outcome":"success","test_command":"<cmd>"}`
  - one or more failing → `{"outcome":"failure","test_command":"<cmd>","failing_tests":[{"name":"<test>","file":"<path>","message":"<assertion>"}],"notes":"<short>"}`
  - no tests this round (e.g. a clarifying question) → omit the marker; the round is recorded as `in_progress`.
  The Stop hook consumes this marker each round.
```

Add a close instruction to **Phase 5 — Report**. After the existing line (line 80):

```markdown
- Assumptions made and any noted Minor issues / follow-ups
```

insert:

```markdown

**Close the trace.** On final completion, write `superharness/trace/.state/outcome.json`
with `"task_status":"completed"` (or `"failed"` / `"abandoned"`) alongside the usual
outcome fields. The Stop hook records the final round, sets the trace `status`, and
removes `task.json`.
```

- [ ] **Step 4: Run the suite to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`.

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/skills/go/SKILL.md tests/run-tests.ps1
git commit -m "feat: go skill writes trace task/outcome markers"
```

---

## Task 5: `/superharness:resume` skill

**Files:**
- Create: `template/plugins/superharness/skills/resume/SKILL.md`
- Modify: `tests/run-tests.ps1` (add test group 16)

- [ ] **Step 1: Write the failing tests**

Insert in `tests/run-tests.ps1` before the `# ---- cleanup + summary` block (after group 15):

```powershell
# ---------------------------------------------------------------- Test group 16: resume skill
Write-Host "`n[16] resume skill is present, manual-only, and drives a root-cause fix"
$resumePath = Join-Path $plugin 'skills\resume\SKILL.md'
Assert-True (Test-Path $resumePath) "ships skills/resume/SKILL.md"
$resumeMd = if (Test-Path $resumePath) { Get-Content $resumePath -Raw } else { '' }
Assert-True ($resumeMd -match 'disable-model-invocation:\s*true') "resume skill is manual-only"
Assert-True ($resumeMd -match 'superharness/trace') "resume skill reads the trace files"
Assert-True ($resumeMd -match '(?i)root cause') "resume skill drives a root-cause fix, not a blind retry"
Assert-True ($resumeMd -match 'systematic-debugging') "resume skill invokes systematic-debugging"
Assert-True ($resumeMd -match 'verification-before-completion') "resume skill verifies before claiming done"
Assert-True ($resumeMd -notmatch 'superpowers:') "resume skill uses the superharness namespace"
```

- [ ] **Step 2: Run the suite to verify the new asserts fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — group 16 asserts fail (resume skill missing). (Note: test group 2's "no dangling superpowers:" sweep will also cover the new skill once created.)

- [ ] **Step 3: Create `template/plugins/superharness/skills/resume/SKILL.md`**

```markdown
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
`task_status":"completed"` once green, or another `failure` round if still red.

## Phase 5 — Report

Summarize: the root cause found, the fix and where, the verification output, and the
updated trace status.
```

- [ ] **Step 4: Run the suite to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`.

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/skills/resume/SKILL.md tests/run-tests.ps1
git commit -m "feat: /superharness:resume drives a recorded failure to a fix"
```

---

## Task 6: Docs, gitignore, and dogfood refresh

**Files:**
- Modify: `.gitignore`
- Modify: `README.md`
- Regenerate: `.claude/superharness/` (dogfood copy, gitignored) via the installer

- [ ] **Step 1: Ignore the transient state dir**

Add to `.gitignore` (after the existing `# superharness 本地运行时产物` block):

```gitignore
# 任务追踪 hook 的临时态（每任务的 trace .json 保留，仅忽略中间标记）
superharness/trace/.state/
```

- [ ] **Step 2: Document the feature in `README.md`**

Add a section describing: the trace files under `superharness/trace/<slug>.json` (one
minified line per task), what each round records (success → `task completed`; failure →
failing tests + query + key info; otherwise `in_progress`), that every round is recorded
even without a marker, and `/superharness:resume [slug]` for reproduce → root-cause →
fix → verify. Match the README's existing heading style and language (mixed zh/en).

- [ ] **Step 3: Refresh the dogfood install so this repo runs the new hooks**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File lib\install.ps1 -TargetDir .`
Expected: `Superharness installed into: ...\.claude\superharness`. This copies the new
hooks/skills into the gitignored `.claude/superharness/` so the running plugin in this
project picks them up on the next session.

- [ ] **Step 4: Run the full suite one last time**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — `=== Results: N passed, 0 failed ===`.

- [ ] **Step 5: Verify the working tree is clean of state litter**

Run: `git status --short`
Expected: no `superharness/trace/.state/` entries staged; only `.gitignore` and `README.md` changes pending.

- [ ] **Step 6: Commit**

```bash
git add .gitignore README.md
git commit -m "docs: document task trace & resume; ignore transient trace state"
```

---

## Self-Review

**Spec coverage:**
- Req 1 (every round recorded regardless of completion) → Task 1 (UserPromptSubmit captures query unconditionally) + Task 2 group 13b (missing marker → in_progress).
- Req 2 (success → `task completed`; failure → failing tests + query + key info, no full dialogue) → Task 2 (success) + Task 3 group 14a (failure fields + no-dialogue assert).
- Req 3 (success/failure by test case) → Task 2/3 outcome branches driven by the `outcome.json` marker the go skill writes after tests (Task 4).
- Req 4 (resume: human-confirmed reproduce → root-cause → fix → verify, no auto-retry) → Task 5 resume skill (Phase 0 confirm gate, Phases 1–4).
- Storage (per-task single-line minified JSON under `superharness/trace/`) → Task 1 `Write-MinifiedJson` + Task 2 group 13a single-line assert.
- §9 defaults (keep trace .json, ignore `.state/`) → Task 6.

**Placeholder scan:** No TBD/TODO; every code step shows full content; the README step describes exact required content (its "test" is the full suite + `git status`, since prose isn't unit-tested).

**Type consistency:** Marker field names are identical across hook code, tests, go skill, and resume skill: `task_id`, `slug`, `goal`, `started_at`, `outcome`, `summary`, `failing_tests` (`name`/`file`/`message`), `test_command`, `notes`, `task_status`; trace top-level `status`, `updated_at`, `rounds[]` with `n`/`ts`/`query`/`outcome`. State filenames consistent: `task.json`, `pending-prompt.json`, `outcome.json`.
