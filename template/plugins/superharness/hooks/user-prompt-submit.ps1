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
