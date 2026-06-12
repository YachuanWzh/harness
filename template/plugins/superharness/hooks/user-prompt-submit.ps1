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
