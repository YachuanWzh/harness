# Global superharness installer.
# Copies bin\, lib\, template\ to a permanent location (%LOCALAPPDATA%\superharness\)
# and adds its bin\ to the user PATH. After this, "superharness" works from any
# directory and survives deletion of the source clone.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install-global.ps1
#
# Update:  re-run this script from an updated clone to refresh the global install.
# Remove:  delete %LOCALAPPDATA%\superharness\ and remove its bin\ from user PATH.

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$InstallRoot = Join-Path $env:LOCALAPPDATA 'superharness'

# ---------- verify source ----------

$Required = @(
    (Join-Path $RepoRoot 'bin\superharness.cmd')
    (Join-Path $RepoRoot 'lib\install.ps1')
    (Join-Path $RepoRoot 'template\.claude-plugin\marketplace.json')
)
foreach ($f in $Required) {
    if (-not (Test-Path $f)) {
        Write-Error "Missing required source file: $f"
        exit 1
    }
}

# ---------- copy to install root ----------

Write-Host "Installing superharness to: $InstallRoot" -ForegroundColor Cyan

# remove previous install (if any) so stale files don't linger
if (Test-Path $InstallRoot) {
    Remove-Item $InstallRoot -Recurse -Force
    Write-Host "  Removed previous install." -ForegroundColor DarkGray
}

$Dirs = @('bin', 'lib', 'template')
foreach ($d in $Dirs) {
    $src  = Join-Path $RepoRoot $d
    $dest = Join-Path $InstallRoot $d
    Copy-Item -Path $src -Destination $dest -Recurse
    Write-Host "  Copied $d\" -ForegroundColor DarkGray
}

# ---------- PATH ----------

$BinDir = Join-Path $InstallRoot 'bin'
$current = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (-not $current) { $current = '' }

$parts = $current -split ';' | Where-Object { $_ -ne '' }

# clean up any old path pointing at a different clone location
$ClonePattern = [regex]::Escape((Join-Path $RepoRoot 'bin'))
$cleaned = $parts | Where-Object { $_ -notmatch $ClonePattern }
if ($cleaned.Count -ne $parts.Count) {
    Write-Host "  Removed old clone-based PATH entry." -ForegroundColor DarkGray
}
$parts = $cleaned

if ($parts -contains $BinDir) {
    Write-Host "Already on user PATH: $BinDir" -ForegroundColor Yellow
} else {
    $new = (@($parts) + $BinDir) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $new, 'User')
    Write-Host "Added to user PATH: $BinDir" -ForegroundColor Green
}

# ---------- done ----------

Write-Host ""
Write-Host "Global install complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open a NEW terminal (PATH change takes effect in new windows)."
Write-Host "  2. cd into any project and run:  superharness"
Write-Host "  3. Then start Claude Code in that project:  claude"
Write-Host ""
Write-Host "Update:  re-run this script from an updated clone to refresh."
Write-Host "Remove:  delete $InstallRoot and remove $BinDir from user PATH."
