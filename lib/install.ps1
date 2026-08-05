# Superharness project installer.
# Detects project type automatically and installs superharness:
#   - Claude Code projects (CLAUDE.md / .claude)  → local marketplace plugin
#   - flavor-code projects (FLAVOR.md / .flavor)   → .flavor/plugins/superharness/
#   - Both present → both installed
#
# Usage: powershell -File install.ps1 [-TargetDir <project root>]

param(
    [string]$TargetDir = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
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

# --- Parse optional --template / --stack from forwarded CLI args ---
$Template = $null; $Stack = $null
$sawTemplateFlag = $false; $sawStackFlag = $false
foreach ($a in $Rest) {
    if ($a -match '^--template($|=)') {
        $sawTemplateFlag = $true
        if ($a -match '^--template=(.+)$') { $Template = $Matches[1].ToLower() }
    }
    elseif ($a -match '^--stack($|=)') {
        $sawStackFlag = $true
        if ($a -match '^--stack=(.+)$') { $Stack = $Matches[1].ToLower() }
    }
}
if ($sawTemplateFlag -and -not $Template) {
    Write-Error "--template requires a value. Valid: frontend, backend, fullstack."
    exit 1
}
if ($sawStackFlag -and -not $Template) {
    Write-Error "--stack requires --template (stack is meaningless without a template)."
    exit 1
}

# resolved stack-doc id, or $null when no --template given
$StackDocId = $null
if ($Template) {
    $valid = @{
        frontend  = @{ default = 'react';  stacks = @('react','vue') }
        backend   = @{ default = 'python'; stacks = @('python','java','node') }
        fullstack = @{ default = $null;    stacks = @() }
    }
    if (-not $valid.ContainsKey($Template)) {
        Write-Error "Unknown --template '$Template'. Valid: frontend, backend, fullstack."
        exit 1
    }
    if ($Template -eq 'fullstack') {
        if ($Stack) { Write-Error "--stack is not allowed with --template=fullstack (fixed React+Python)."; exit 1 }
        $StackDocId = 'fullstack'
    } else {
        if (-not $Stack) { $Stack = $valid[$Template].default }
        if ($valid[$Template].stacks -notcontains $Stack) {
            Write-Error "Invalid --stack '$Stack' for --template=$Template. Valid: $($valid[$Template].stacks -join ', ')."
            exit 1
        }
        $StackDocId = "$Template-$Stack"
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Set-Member {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# ============================================================================
# 0. Detect project type
# ============================================================================

$HasClaudeMarker = (Test-Path (Join-Path $TargetDir 'CLAUDE.md')) -or (Test-Path (Join-Path $TargetDir '.claude'))
$HasFlavorMarker = (Test-Path (Join-Path $TargetDir 'FLAVOR.md')) -or (Test-Path (Join-Path $TargetDir '.flavor'))

# Backward compatible: if nothing detected, default to Claude Code
if (-not $HasClaudeMarker -and -not $HasFlavorMarker) {
    $HasClaudeMarker = $true
}

$InstalledAnything = $false

# ============================================================================
# 1. Install for Claude Code (CLAUDE.md / .claude)
# ============================================================================

if ($HasClaudeMarker) {
    Write-Host "[Claude Code] Detected Claude Code project, installing superharness plugin..." -ForegroundColor Cyan

    $MarketDir = Join-Path $TargetDir '.claude\superharness'

    # --- 1a. Copy template -> .claude/superharness ---
    New-Item -ItemType Directory -Force $MarketDir | Out-Null
    Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $MarketDir -Recurse -Force

    # --- 1b. Active stack guidance ---
    $StackTarget = Join-Path $MarketDir 'STACK.md'
    if ($StackDocId) {
        $StackSource = Join-Path $MarketDir "plugins\superharness\stacks\$StackDocId.md"
        if (-not (Test-Path $StackSource)) { Write-Error "Stack guidance doc missing: $StackSource"; exit 1 }
        Copy-Item -Path $StackSource -Destination $StackTarget -Force
    } elseif (Test-Path $StackTarget) {
        Remove-Item $StackTarget -Force
    }

    # --- 1c. Merge .claude/settings.json ---
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

    # --- 1d. Remove legacy skills-dir install ---
    $LegacyDir = Join-Path $TargetDir '.claude\skills\superharness'
    if (Test-Path $LegacyDir) { Remove-Item $LegacyDir -Recurse -Force }

    # --- 1e. Managed section in CLAUDE.md ---
    $ClaudeBeginMarker = '<!-- SUPERHARNESS:BEGIN -->'
    $ClaudeEndMarker   = '<!-- SUPERHARNESS:END -->'

    $ClaudeSection = @"
$ClaudeBeginMarker
## Superharness

This project uses **superharness**, loaded as a Claude Code plugin from the local
marketplace at ``.claude/superharness`` (enabled in ``.claude/settings.json`` via
``extraKnownMarketplaces`` + ``enabledPlugins``). Its SessionStart hook injects
``HARNESS.md`` into every session. If that context is missing, read
``.claude/superharness/plugins/superharness/HARNESS.md`` now and follow it for all
engineering work.

- Run a task end-to-end: ``/superharness:go <task goal>``
- Small focused change (lighter go, no worktree/plan-file/ralph overhead):
  ``/superharness:light <task goal>``
- Brainstorm with a live browser mind map (manual trigger only):
  ``/superharness:brainstorm <topic>``
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
$ClaudeEndMarker
"@

    $ClaudeMdPath = Join-Path $TargetDir 'CLAUDE.md'

    if (Test-Path $ClaudeMdPath) {
        $existing = [IO.File]::ReadAllText($ClaudeMdPath, $utf8)
        if ($existing -match [regex]::Escape($ClaudeBeginMarker)) {
            $pattern = [regex]::Escape($ClaudeBeginMarker) + '[\s\S]*?' + [regex]::Escape($ClaudeEndMarker)
            $updated = [regex]::Replace($existing, $pattern, $ClaudeSection.TrimEnd())
            [IO.File]::WriteAllText($ClaudeMdPath, $updated, $utf8)
        } else {
            [IO.File]::WriteAllText($ClaudeMdPath, $existing.TrimEnd() + "`r`n`r`n" + $ClaudeSection, $utf8)
        }
    } else {
        [IO.File]::WriteAllText($ClaudeMdPath, $ClaudeSection, $utf8)
    }

    # --- 1f. .gitignore entries for Claude Code runtime state ---
    $GitignorePath = Join-Path $TargetDir '.gitignore'
    $giExisting = if (Test-Path $GitignorePath) { [IO.File]::ReadAllText($GitignorePath, $utf8) } else { '' }
    $claudeIgnoreLines = @(
        @{ Comment = '# superharness ralph runtime state (per-task tracking + retry)'; Line = '.claude/superharness/ralph/' },
        @{ Comment = '# superharness brainstorm mind-map session state (transient)';     Line = '.claude/superharness/brainstorm/' }
    )
    foreach ($entry in $claudeIgnoreLines) {
        if ($giExisting -notmatch [regex]::Escape($entry.Line)) {
            $prefix = if ($giExisting -and -not $giExisting.EndsWith("`n")) { "`r`n" } else { '' }
            $block = "$prefix$($entry.Comment)`r`n$($entry.Line)`r`n"
            $giExisting = $giExisting + $block
        }
    }
    [IO.File]::WriteAllText($GitignorePath, $giExisting, $utf8)

    Write-Host "  Claude Code plugin installed to: $MarketDir" -ForegroundColor Green
    $InstalledAnything = $true
}

# ============================================================================
# 2. Install for flavor-code (FLAVOR.md / .flavor)
# ============================================================================

if ($HasFlavorMarker) {
    Write-Host "[flavor-code] Detected flavor-code project, installing superharness plugin..." -ForegroundColor Cyan

    $FlavorPluginDir  = Join-Path $TargetDir '.flavor\plugins\superharness'
    $FlavorSkillsDest = Join-Path $FlavorPluginDir 'skills'
    $SkillsSource     = Join-Path $TemplateDir 'plugins\superharness\skills'
    $PluginMetaSource = Join-Path $TemplateDir 'plugins\superharness\plugin'

    if (-not (Test-Path $SkillsSource)) {
        Write-Error "Skills source directory not found: $SkillsSource"
        exit 1
    }

    # --- 2a. Create plugin directory, copy manifest + entry point ---
    New-Item -ItemType Directory -Force $FlavorPluginDir | Out-Null
    Copy-Item -Path (Join-Path $PluginMetaSource 'flavor-plugin.json') -Destination $FlavorPluginDir -Force
    Copy-Item -Path (Join-Path $PluginMetaSource 'index.js')          -Destination $FlavorPluginDir -Force

    # --- 2a'. Docs consumed by the plugin hooks (SessionStart injects HARNESS.md) ---
    Copy-Item -Path (Join-Path $TemplateDir 'plugins\superharness\HARNESS.md') -Destination $FlavorPluginDir -Force
    $FlavorStackTarget = Join-Path $FlavorPluginDir 'STACK.md'
    if ($StackDocId) {
        Copy-Item -Path (Join-Path $TemplateDir "plugins\superharness\stacks\$StackDocId.md") -Destination $FlavorStackTarget -Force
    } elseif (Test-Path $FlavorStackTarget) {
        Remove-Item $FlavorStackTarget -Force
    }

    # --- 2b. Copy skills into .flavor/plugins/superharness/skills/ ---
    if (Test-Path $FlavorSkillsDest) { Remove-Item $FlavorSkillsDest -Recurse -Force }
    Copy-Item -Path $SkillsSource -Destination $FlavorSkillsDest -Recurse

    $copiedSkills = @()
    Get-ChildItem -Directory $FlavorSkillsDest | ForEach-Object { $copiedSkills += $_.Name }

    # --- 2c. Clean up legacy flat .flavor/skills/ install (pre-plugin) ---
    $LegacyFlavorSkills = Join-Path $TargetDir '.flavor\skills'
    if (Test-Path $LegacyFlavorSkills) {
        Remove-Item $LegacyFlavorSkills -Recurse -Force
    }
    # --- 2d. Managed section in FLAVOR.md ---
    $FlavorBeginMarker = '<!-- SUPERHARNESS:FLAVOR-BEGIN -->'
    $FlavorEndMarker   = '<!-- SUPERHARNESS:FLAVOR-END -->'

    $skillList = ($copiedSkills | ForEach-Object { "``$_``" }) -join ', '
    $FlavorSection = @"
$FlavorBeginMarker
## Superharness

This project has **superharness** installed as a flavor-code plugin under
``.flavor/plugins/superharness/``. It registers a skill root that provides
engineering-discipline skills for autonomous development, plus SessionStart /
UserPromptSubmit / Stop hooks that inject ``HARNESS.md`` into every session and
track ``/go`` tasks under ``.claude/superharness/ralph/``.

Installed skills: $skillList

Key capabilities:
- **go** -- Drive a task end-to-end under strict TDD + verification + code review discipline.
- **light** -- Lightweight mode for small focused tasks: TDD with exemptions, real-output verification, no worktree/plan-file/ralph overhead.
- **brainstorm** -- Explore requirements with a live browser mind map (manual trigger only).
- **test-driven-development** -- RED-GREEN-REFACTOR cycle. No production code without a failing test first.
- **systematic-debugging** -- Root-cause tracing, defense-in-depth, no guess-and-patch.
- **verification-before-completion** -- Run the full test suite and show real output before claiming done.
- **requesting-code-review** -- Dispatch a reviewer subagent over the diff.
- **writing-plans** -- Break down multi-step work into bite-sized TDD tasks.
- **using-git-worktrees** -- Isolate work in a disposable workspace.
- **subagent-driven-development** -- Execute multi-task plans with parallel subagents.

Usage in flavor-code: ``/<skill-name> <args>``, e.g. ``/go refactor login module`` or ``/brainstorm payment plan``.
$FlavorEndMarker
"@

    $FlavorMdPath = Join-Path $TargetDir 'FLAVOR.md'

    if (Test-Path $FlavorMdPath) {
        $existing = [IO.File]::ReadAllText($FlavorMdPath, $utf8)
        if ($existing -match [regex]::Escape($FlavorBeginMarker)) {
            # Replace existing managed section in place
            $pattern = [regex]::Escape($FlavorBeginMarker) + '[\s\S]*?' + [regex]::Escape($FlavorEndMarker)
            $updated = [regex]::Replace($existing, $pattern, $FlavorSection.TrimEnd())
            [IO.File]::WriteAllText($FlavorMdPath, $updated, $utf8)
        } else {
            [IO.File]::WriteAllText($FlavorMdPath, $existing.TrimEnd() + "`r`n`r`n" + $FlavorSection, $utf8)
        }
    } else {
        [IO.File]::WriteAllText($FlavorMdPath, $FlavorSection, $utf8)
    }

    # --- 2e. .gitignore entries for flavor-code runtime state ---
    $GitignorePath = Join-Path $TargetDir '.gitignore'
    $giExisting = if (Test-Path $GitignorePath) { [IO.File]::ReadAllText($GitignorePath, $utf8) } else { '' }
    $flavorIgnoreLines = @(
        @{ Comment = '# superharness brainstorm mind-map session state (transient)'; Line = '.superharness/' },
        @{ Comment = '# superharness ralph runtime state (per-task tracking + retry)'; Line = '.claude/superharness/ralph/' }
    )
    foreach ($entry in $flavorIgnoreLines) {
        if ($giExisting -notmatch [regex]::Escape($entry.Line)) {
            $prefix = if ($giExisting -and -not $giExisting.EndsWith("`n")) { "`r`n" } else { '' }
            $block = "$prefix$($entry.Comment)`r`n$($entry.Line)`r`n"
            $giExisting = $giExisting + $block
        }
    }
    [IO.File]::WriteAllText($GitignorePath, $giExisting, $utf8)

    Write-Host "  flavor-code plugin installed to: $FlavorPluginDir" -ForegroundColor Green
    $InstalledAnything = $true
}

# ============================================================================
# 3. Done
# ============================================================================

if (-not $InstalledAnything) {
    Write-Host "No project marker detected (CLAUDE.md/.claude or FLAVOR.md/.flavor). Nothing installed." -ForegroundColor Yellow
    Write-Host "Run superharness in a project directory with CLAUDE.md, FLAVOR.md, .claude, or .flavor." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

if ($HasClaudeMarker) {
    Write-Host "-- Claude Code --" -ForegroundColor Cyan
    Write-Host "  1. Start Claude Code in this project directory (trust workspace when asked)."
    Write-Host "  2. Plugin loads automatically from local marketplace .claude/superharness."
    Write-Host "  3. Run a task:  /superharness:go [task goal]"
    Write-Host "     or a small focused change:  /superharness:light [task goal]"
    Write-Host "     or brainstorm:  /superharness:brainstorm [topic]"
}

if ($HasFlavorMarker) {
    if ($HasClaudeMarker) { Write-Host "" }
    Write-Host "-- flavor-code --" -ForegroundColor Cyan
    Write-Host "  1. Start flavor-code in this project directory:  flavor"
    Write-Host "  2. Plugin auto-loads from .flavor/plugins/superharness/ (skillRoot registered at startup)."
    Write-Host "  3. Run a task:  /go [task goal]"
    Write-Host "     or a small focused change:  /light [task goal]"
    Write-Host "     or brainstorm:  /brainstorm [topic]"
}

Write-Host ""
exit 0
