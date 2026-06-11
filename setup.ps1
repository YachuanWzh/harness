# One-time setup: add superharness\bin to the current user's PATH (idempotent).
# Uses [Environment]::SetEnvironmentVariable to avoid setx's 1024-character truncation.
# Undo: remove the bin path from  Settings > System > About > Advanced system settings
#       > Environment Variables > User PATH.

$ErrorActionPreference = 'Stop'

$BinDir = Join-Path $PSScriptRoot 'bin'
$current = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (-not $current) { $current = '' }

$parts = $current -split ';' | Where-Object { $_ -ne '' }
if ($parts -contains $BinDir) {
    Write-Host "Already on user PATH: $BinDir" -ForegroundColor Yellow
} else {
    $new = (@($parts) + $BinDir) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $new, 'User')
    Write-Host "Added to user PATH: $BinDir" -ForegroundColor Green
    Write-Host "Open a NEW terminal for the change to take effect, then run: superharness"
}
