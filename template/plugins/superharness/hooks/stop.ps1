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
