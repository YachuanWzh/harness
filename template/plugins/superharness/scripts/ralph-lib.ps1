# Ralph state mechanism — zero-dependency PowerShell state library.
#
# Manages the four runtime files of a resumable autonomous-task loop, all under
# <project>/superharness/ralph/ :
#   .current-task      one-line pointer to the active task (switch = rewrite the line)
#   task.json          task-list snapshot {status,phase,sprint,tasks[],updated_at}
#   trace.jsonl        append-only ledger, one {ts,phase,event,detail} JSON per line
#   .ralph-state.json  retry counter {retries,max,updated_at}, capped at 5
#
# Dot-source this file to use the functions. Conventions match hooks/trace-lib.ps1:
# UTF-8 without BOM, atomic temp-then-move for JSON snapshots, ISO-8601 timestamps.

# ---------------------------------------------------------------- paths & helpers

function Get-RalphDir {
    param([Parameter(Mandatory)][string]$Root)
    Join-Path $Root 'superharness\ralph'
}

function Get-RalphIso { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }

function New-RalphDir {
    param([string]$Root)
    $dir = Get-RalphDir $Root
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    return $dir
}

function Read-RalphJson {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-RalphText {
    # Atomic write: temp file then move-replace. UTF-8 without BOM.
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding($false)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $Text, $enc)
    Move-Item -Path $tmp -Destination $Path -Force
}

function Write-RalphJson {
    param([string]$Path, $Object)
    Write-RalphText $Path (ConvertTo-Json -InputObject $Object -Depth 12 -Compress)
}

# ---------------------------------------------------------------- .current-task

function Get-RalphCurrentTaskPath { param([string]$Root) Join-Path (Get-RalphDir $Root) '.current-task' }

function Set-RalphCurrentTask {
    # The pointer is a single line; switching a task rewrites only this line.
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$TaskId)
    Write-RalphText (Get-RalphCurrentTaskPath $Root) ($TaskId.Trim())
}

function Get-RalphCurrentTask {
    param([Parameter(Mandatory)][string]$Root)
    $p = Get-RalphCurrentTaskPath $Root
    if (-not (Test-Path $p)) { return $null }
    $raw = (Get-Content $p -Raw)
    if ($null -eq $raw) { return $null }
    $line = $raw.Trim()
    if ($line -eq '') { return $null }
    return $line
}
