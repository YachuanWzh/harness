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
