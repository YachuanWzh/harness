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

# --- 2. Merge .claude/settings.json (preserving existing keys) ---
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Set-Member {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

$SettingsPath = Join-Path $TargetDir '.claude\settings.json'
$settings = if (Test-Path $SettingsPath) {
    [IO.File]::ReadAllText($SettingsPath, $utf8) | ConvertFrom-Json
} else { New-Object PSObject }

$shMarket = '{"source":{"source":"directory","path":".claude/superharness"}}' | ConvertFrom-Json
if (-not $settings.PSObject.Properties['extraKnownMarketplaces']) {
    Set-Member $settings 'extraKnownMarketplaces' (New-Object PSObject)
}
Set-Member $settings.extraKnownMarketplaces 'superharness' $shMarket

if (-not $settings.PSObject.Properties['enabledPlugins']) {
    Set-Member $settings 'enabledPlugins' (New-Object PSObject)
}
Set-Member $settings.enabledPlugins 'superharness@superharness' $true

[IO.File]::WriteAllText($SettingsPath, ($settings | ConvertTo-Json -Depth 16), $utf8)

# --- 3. Remove legacy skills-dir install ---
$LegacyDir = Join-Path $TargetDir '.claude\skills\superharness'
if (Test-Path $LegacyDir) { Remove-Item $LegacyDir -Recurse -Force }

# --- 4. Managed section in CLAUDE.md (auto-read fallback + user docs) ---
$BeginMarker = '<!-- SUPERHARNESS:BEGIN -->'
$EndMarker   = '<!-- SUPERHARNESS:END -->'

$Section = @"
$BeginMarker
## Superharness

This project uses **superharness**, loaded as a Claude Code plugin from the local
marketplace at ``.claude/superharness`` (enabled in ``.claude/settings.json`` via
``extraKnownMarketplaces`` + ``enabledPlugins``). Its SessionStart hook injects
``HARNESS.md`` into every session. If that context is missing, read
``.claude/superharness/plugins/superharness/HARNESS.md`` now and follow it for all
engineering work.

- Run a task end-to-end: ``/superharness:go <task goal>``
- Brainstorm with a live browser mind map (manual trigger only):
  ``/superharness:brainstorm <topic>``
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
$EndMarker
"@

$ClaudeMdPath = Join-Path $TargetDir 'CLAUDE.md'

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
Write-Host "  2. The plugin loads automatically from the local marketplace at .claude/superharness."
Write-Host "  3. Run a task:       /superharness:go <your task goal>"
Write-Host "     or brainstorm:    /superharness:brainstorm <topic>"
exit 0
