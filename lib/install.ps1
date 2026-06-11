# Superharness project installer.
# Installs the template as a local plugin marketplace at <project>/.claude/superharness/
# and enables the plugin via .claude/settings.json (extraKnownMarketplaces + enabledPlugins),
# giving the project /superharness:* skills and the SessionStart hook.
#
# Usage: powershell -File install.ps1 [-TargetDir <project root>]

param(
    [string]$TargetDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TemplateDir = Join-Path $RepoRoot 'template'

if (-not (Test-Path $TemplateDir)) {
    Write-Error "Template directory not found: $TemplateDir"
    exit 1
}
if (-not (Test-Path $TargetDir)) {
    Write-Error "Target directory not found: $TargetDir"
    exit 1
}

$MarketDir = Join-Path $TargetDir '.claude\superharness'

# --- 1. Copy template -> .claude/superharness (local marketplace root, idempotent overwrite) ---
New-Item -ItemType Directory -Force $MarketDir | Out-Null
Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $MarketDir -Recurse -Force

# --- 2. Managed section in CLAUDE.md (auto-read fallback + user docs) ---
$BeginMarker = '<!-- SUPERHARNESS:BEGIN -->'
$EndMarker   = '<!-- SUPERHARNESS:END -->'

$Section = @"
$BeginMarker
## Superharness

This project uses **superharness** (loaded from ``.claude/skills/superharness/`` as the
``superharness@skills-dir`` plugin). Its SessionStart hook injects ``HARNESS.md`` into every
session. If that context is missing, read ``.claude/skills/superharness/HARNESS.md`` now
and follow it for all engineering work.

- Run a task end-to-end: ``/superharness:go <task goal>``
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
$EndMarker
"@

$ClaudeMdPath = Join-Path $TargetDir 'CLAUDE.md'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (Test-Path $ClaudeMdPath) {
    $existing = [IO.File]::ReadAllText($ClaudeMdPath, $utf8)
    if ($existing -match [regex]::Escape($BeginMarker)) {
        # Replace the existing managed section in place
        $pattern = [regex]::Escape($BeginMarker) + '[\s\S]*?' + [regex]::Escape($EndMarker)
        $updated = [regex]::Replace($existing, $pattern, $Section.TrimEnd())
        [IO.File]::WriteAllText($ClaudeMdPath, $updated, $utf8)
    } else {
        [IO.File]::WriteAllText($ClaudeMdPath, $existing.TrimEnd() + "`r`n`r`n" + $Section, $utf8)
    }
} else {
    [IO.File]::WriteAllText($ClaudeMdPath, $Section, $utf8)
}

Write-Host ""
Write-Host "Superharness installed into: $MarketDir" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Start Claude Code in this project directory (trust the workspace when asked)."
Write-Host "  2. The plugin loads automatically as superharness@skills-dir."
Write-Host "  3. Run a task:  /superharness:go <your task goal>"
exit 0
