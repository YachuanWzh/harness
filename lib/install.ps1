# Superharness project installer.
# Detects project type automatically and installs superharness:
#   - Claude Code projects (CLAUDE.md / .claude)  → local marketplace plugin
#   - flavor-code projects (FLAVOR.md / .flavor)   → .flavor/plugins/superharness/
#   - Both present → both installed
#
# Usage: powershell -File install.ps1 [-TargetDir <project root>] [--template=...] [--uninstall]

param(
    [string]$TargetDir = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# --uninstall / -uninstall switches to revert mode (must be known before the
# template checks below run, so scan $Rest up front).
$Uninstall = $Rest -contains '--uninstall' -or $Rest -contains '-uninstall'

# --self-update switches to global self-update mode: delegate to install-global.ps1.
# Bare 'self-update' (passed through from the CLI) is also accepted.
$SelfUpdate = $Rest -contains '--self-update' -or $Rest -contains '-self-update' -or $Rest -contains 'self-update'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TemplateDir = Join-Path $RepoRoot 'template'

# --- self-update mode ---
if ($SelfUpdate) {
    $GlobalInstall = Join-Path $env:LOCALAPPDATA 'superharness'
    $GlobalScript = Join-Path $GlobalInstall 'lib' 'install.ps1'
    if (-not (Test-Path $GlobalScript)) {
        Write-Error "Global superharness install not found at $GlobalInstall. Run install-global.ps1 first."
        exit 1
    }
    Write-Host "Superharness self-update: refreshing global install..." -ForegroundColor Cyan
    & $GlobalScript -TargetDir (Get-Location).Path @Rest
    exit $LASTEXITCODE
}

if (-not $Uninstall -and -not (Test-Path $TemplateDir)) {
    Write-Error "Template directory not found: $TemplateDir"
    exit 1
}
if (-not (Test-Path $TargetDir)) {
    Write-Error "Target directory not found: $TargetDir"
    exit 1
}

# ============================================================================
# 0. Uninstall mode — revert everything the installer adds (and only that)
# ============================================================================
if ($Uninstall) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    # Drop the managed .gitignore blocks: a '# superharness ...' comment line
    # followed by the runtime pattern we appended.
    function Remove-ManagedGitignoreLines {
        param([string]$Path, [string[]]$Patterns)
        if (-not (Test-Path $Path)) { return $false }
        $lines = [IO.File]::ReadAllLines($Path)
        $out = New-Object System.Collections.Generic.List[string]
        $changed = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^# superharness ') {
                $changed = $true
                if ($i + 1 -lt $lines.Count -and $Patterns -contains $lines[$i + 1].Trim()) {
                    $i++
                }
                continue
            }
            $out.Add($line)
        }
        if (-not $changed) { return $false }
        $text = ($out -join "`r`n").TrimEnd()
        if ($text -eq '') {
            Remove-Item $Path -Force
        } else {
            [IO.File]::WriteAllText($Path, $text + "`r`n", $utf8)
        }
        return $true
    }

    # Remove the managed marker section from a markdown file. Returns $true if
    # a section was removed. A file left empty is deleted (installer-created).
    function Remove-ManagedSection {
        param([string]$Path, [string]$BeginMarker, [string]$EndMarker)
        if (-not (Test-Path $Path)) { return $false }
        $existing = [IO.File]::ReadAllText($Path, $utf8)
        $pattern = [regex]::Escape($BeginMarker) + '[\s\S]*?' + [regex]::Escape($EndMarker)
        $updated = [regex]::Replace($existing, $pattern, '')
        if ($updated -eq $existing) { return $false }
        $updated = $updated.TrimEnd() + "`r`n"
        if ($updated.Trim() -eq '') {
            Remove-Item $Path -Force
        } else {
            [IO.File]::WriteAllText($Path, $updated, $utf8)
        }
        return $true
    }

    Write-Host "Superharness uninstall..." -ForegroundColor Cyan
    $UninstalledAnything = $false

    # --- Claude Code side ---
    $MarketDir = Join-Path $TargetDir '.claude\superharness'
    if (Test-Path $MarketDir) {
        Remove-Item $MarketDir -Recurse -Force
        Write-Host "  Removed $MarketDir" -ForegroundColor Green
        $UninstalledAnything = $true
    }
    $LegacyDir = Join-Path $TargetDir '.claude\skills\superharness'
    if (Test-Path $LegacyDir) {
        Remove-Item $LegacyDir -Recurse -Force
        Write-Host "  Removed legacy $LegacyDir" -ForegroundColor Green
        $UninstalledAnything = $true
    }

    # .claude/settings.json — drop only the superharness keys we merge in
    $SettingsPath = Join-Path $TargetDir '.claude\settings.json'
    if (Test-Path $SettingsPath) {
        $settings = $null
        try { $settings = [IO.File]::ReadAllText($SettingsPath, $utf8) | ConvertFrom-Json } catch {}
        if ($null -ne $settings) {
            $settingsChanged = $false
            if ($settings.PSObject.Properties['extraKnownMarketplaces']) {
                $settings.extraKnownMarketplaces.PSObject.Properties.Remove('superharness') | Out-Null
                $settingsChanged = $true
                if (@($settings.extraKnownMarketplaces.PSObject.Properties).Count -eq 0) {
                    $settings.PSObject.Properties.Remove('extraKnownMarketplaces') | Out-Null
                }
            }
            if ($settings.PSObject.Properties['enabledPlugins']) {
                $settings.enabledPlugins.PSObject.Properties.Remove('superharness@superharness') | Out-Null
                $settingsChanged = $true
                if (@($settings.enabledPlugins.PSObject.Properties).Count -eq 0) {
                    $settings.PSObject.Properties.Remove('enabledPlugins') | Out-Null
                }
            }
            if ($settingsChanged) {
                if (@($settings.PSObject.Properties).Count -eq 0) {
                    Remove-Item $SettingsPath -Force
                } else {
                    [IO.File]::WriteAllText($SettingsPath, ($settings | ConvertTo-Json -Depth 16), $utf8)
                }
            }
        }
    }

    # CLAUDE.md — remove the managed section
    if (Remove-ManagedSection -Path (Join-Path $TargetDir 'CLAUDE.md') -BeginMarker '<!-- SUPERHARNESS:BEGIN -->' -EndMarker '<!-- SUPERHARNESS:END -->') {
        $UninstalledAnything = $true
    }

    # --- flavor-code side ---
    $FlavorPluginDir = Join-Path $TargetDir '.flavor\plugins\superharness'
    if (Test-Path $FlavorPluginDir) {
        Remove-Item $FlavorPluginDir -Recurse -Force
        Write-Host "  Removed $FlavorPluginDir" -ForegroundColor Green
        $UninstalledAnything = $true
    }

    # FLAVOR.md — remove the managed section
    if (Remove-ManagedSection -Path (Join-Path $TargetDir 'FLAVOR.md') -BeginMarker '<!-- SUPERHARNESS:FLAVOR-BEGIN -->' -EndMarker '<!-- SUPERHARNESS:FLAVOR-END -->') {
        $UninstalledAnything = $true
    }

    # .gitignore — drop the managed runtime-state blocks (both hosts)
    $GitignorePath = Join-Path $TargetDir '.gitignore'
    if (Test-Path $GitignorePath) {
        $giChanged = Remove-ManagedGitignoreLines -Path $GitignorePath -Patterns @(
            '.claude/superharness/ralph/', '.claude/superharness/brainstorm/',
            '.claude/superharness/onboarding/',
            '.superharness/', '.flavor/superharness/ralph/', '.flavor/superharness/onboarding/'
        )
        if ($giChanged) { $UninstalledAnything = $true }
    }

    if (-not $UninstalledAnything) {
        Write-Host "No superharness install found in $TargetDir. Nothing to uninstall." -ForegroundColor Yellow
    } else {
        Write-Host "Superharness uninstalled from $TargetDir. Your other project settings were left untouched." -ForegroundColor Green
    }
    exit 0
}

# --- Parse optional --template / --stack / --frontend / --backend / --uninstall from forwarded CLI args ---
$Template = $null; $Stack = $null; $Frontend = $null; $Backend = $null
$sawTemplateFlag = $false; $sawStackFlag = $false; $sawFrontendFlag = $false; $sawBackendFlag = $false
foreach ($a in $Rest) {
    if ($a -match '^--template($|=)') {
        $sawTemplateFlag = $true
        if ($a -match '^--template=(.+)$') { $Template = $Matches[1].ToLower() }
    }
    elseif ($a -match '^--stack($|=)') {
        $sawStackFlag = $true
        if ($a -match '^--stack=(.+)$') { $Stack = $Matches[1].ToLower() }
    }
    elseif ($a -match '^--frontend($|=)') {
        $sawFrontendFlag = $true
        if ($a -match '^--frontend=(.+)$') { $Frontend = $Matches[1].ToLower() }
    }
    elseif ($a -match '^--backend($|=)') {
        $sawBackendFlag = $true
        if ($a -match '^--backend=(.+)$') { $Backend = $Matches[1].ToLower() }
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
if (($sawFrontendFlag -or $sawBackendFlag) -and $Template -ne 'fullstack') {
    Write-Error "--frontend/--backend only apply to --template=fullstack."
    exit 1
}

# resolved stack-doc id for single-stack templates (or $null when no --template given);
# fullstack instead resolves $FullstackFront / $FullstackBack and concatenates docs.
$StackDocId = $null
$FullstackFront = $null
$FullstackBack = $null
if ($Template) {
    $valid = @{
        frontend  = @{ default = 'react';  stacks = @('react','vue') }
        backend   = @{ default = 'python'; stacks = @('python','java','node') }
    }
    if ($Template -eq 'fullstack') {
        if ($Stack) {
            Write-Error "--stack is not allowed with --template=fullstack; use --frontend=react|vue and --backend=python|java|node instead."
            exit 1
        }
        if (-not $Frontend) { $Frontend = 'react' }
        if (-not $Backend)  { $Backend = 'python' }
        if ($valid['frontend'].stacks -notcontains $Frontend) {
            Write-Error "Invalid --frontend '$Frontend'. Valid: react, vue."
            exit 1
        }
        if ($valid['backend'].stacks -notcontains $Backend) {
            Write-Error "Invalid --backend '$Backend'. Valid: python, java, node."
            exit 1
        }
        $FullstackFront = $Frontend
        $FullstackBack  = $Backend
    } elseif (-not $valid.ContainsKey($Template)) {
        Write-Error "Unknown --template '$Template'. Valid: frontend, backend, fullstack."
        exit 1
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

# Write the active stack guidance. Single-stack templates copy one doc;
# fullstack concatenates frontend + backend + seam docs into STACK.md.
function Write-StackGuidance {
    param([string]$StackRoot, [string]$TargetPath)
    $stacksDir = Join-Path $StackRoot 'plugins\superharness\stacks'
    if ($StackDocId) {
        $src = Join-Path $stacksDir "$StackDocId.md"
        if (-not (Test-Path $src)) { Write-Error "Stack guidance doc missing: $src"; exit 1 }
        Copy-Item -Path $src -Destination $TargetPath -Force
    } elseif ($FullstackFront) {
        $front = Join-Path $stacksDir "frontend-$FullstackFront.md"
        $back  = Join-Path $stacksDir "backend-$FullstackBack.md"
        $seam  = Join-Path $stacksDir 'fullstack-seam.md'
        foreach ($src in @($front, $back, $seam)) {
            if (-not (Test-Path $src)) { Write-Error "Stack guidance doc missing: $src"; exit 1 }
        }
        $combined = (Get-Content $front -Raw).TrimEnd() + "`r`n`r`n" +
                    (Get-Content $back -Raw).TrimEnd() + "`r`n`r`n" +
                    (Get-Content $seam -Raw).TrimEnd() + "`r`n"
        [IO.File]::WriteAllText($TargetPath, $combined, $utf8)
    } elseif (Test-Path $TargetPath) {
        Remove-Item $TargetPath -Force
    }
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
    Write-StackGuidance -StackRoot $MarketDir -TargetPath $StackTarget

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
- Onboard a newcomer / understand the codebase's business logic:
  ``/superharness:onboarding [module or flow]``
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
        @{ Comment = '# superharness brainstorm mind-map session state (transient)';     Line = '.claude/superharness/brainstorm/' },
        @{ Comment = '# superharness onboarding analysis cache (regenerable, never committed)'; Line = '.claude/superharness/onboarding/' }
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

    # Detect whether this is a fresh install or an upgrade of an existing one.
    $IsUpgrade = Test-Path $FlavorPluginDir

    # --- 2a. Create plugin directory, copy manifest + entry point ---
    New-Item -ItemType Directory -Force $FlavorPluginDir | Out-Null
    Copy-Item -Path (Join-Path $PluginMetaSource 'flavor-plugin.json') -Destination $FlavorPluginDir -Force
    Copy-Item -Path (Join-Path $PluginMetaSource 'index.js')          -Destination $FlavorPluginDir -Force

    # --- 2a'. Docs consumed by the plugin hooks (SessionStart injects HARNESS.md) ---
    Copy-Item -Path (Join-Path $TemplateDir 'plugins\superharness\HARNESS.md') -Destination $FlavorPluginDir -Force
    $FlavorStackTarget = Join-Path $FlavorPluginDir 'STACK.md'
    Write-StackGuidance -StackRoot $TemplateDir -TargetPath $FlavorStackTarget

    # --- 2b. Copy skills into .flavor/plugins/superharness/skills/ ---
    if (Test-Path $FlavorSkillsDest) { Remove-Item $FlavorSkillsDest -Recurse -Force }
    Copy-Item -Path $SkillsSource -Destination $FlavorSkillsDest -Recurse

    # --- 2b'. Ralph state library — skills (go) dot-source it to drive task tracking;
    #          its install path under .flavor/ selects the .flavor state root ---
    $FlavorScriptsDest = Join-Path $FlavorPluginDir 'scripts'
    New-Item -ItemType Directory -Force $FlavorScriptsDest | Out-Null
    Copy-Item -Path (Join-Path $TemplateDir 'plugins\superharness\scripts\ralph-lib.ps1') -Destination $FlavorScriptsDest -Force
    Copy-Item -Path (Join-Path $TemplateDir 'plugins\superharness\scripts\ralph-lib.sh')  -Destination $FlavorScriptsDest -Force

    # --- 2c. On upgrade, verify the flavor-plugin.json manifest includes the new hook events.
    #          flavor-code's PluginHost validates that every declared hook in the manifest is
    #          actually registered by activate(), so stale manifests cause activation failures. ---
    if ($IsUpgrade) {
        Write-Host "  Upgraded existing flavor-code plugin; manifest and hooks are current." -ForegroundColor DarkGray
    }

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
``.flavor/plugins/superharness/``. It registers a skill root plus eight session,
planning, and subagent lifecycle hooks. On flavor-code 1.2.20+, SessionStart
injects ``HARNESS.md`` into the persistent context and the host ``Skill`` tool
loads required sub-skills during ``/go``. Ralph checkpoints live under
``.flavor/superharness/ralph/`` and remain resumable across host sessions.

Installed skills: $skillList

Key capabilities:
- **go** -- Drive a task end-to-end under strict TDD + verification + code review discipline.
- **light** -- Lightweight mode for small focused tasks: TDD with exemptions, real-output verification, no worktree/plan-file/ralph overhead.
- **brainstorm** -- Explore requirements with a live browser mind map (manual trigger only).
- **onboarding** -- Deep-analyze the workspace's business logic for newcomers: ONBOARDING.md + interactive module mind map, astgraph-powered with fallback, incremental via cache.
- **test-driven-development** -- RED-GREEN-REFACTOR cycle. No production code without a failing test first.
- **systematic-debugging** -- Root-cause tracing, defense-in-depth, no guess-and-patch.
- **verification-before-completion** -- Run the full test suite and show real output before claiming done.
- **requesting-code-review** -- Dispatch a reviewer subagent over the diff.
- **receiving-code-review** -- Verify review findings against the code before implementing; no performative agreement, no blind fixes.
- **converge** -- Audit implementation vs spec/plan after review; append leftovers as tasks and sink a living spec (go Phase 4.5).
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
        @{ Comment = '# superharness ralph runtime state (per-task tracking + retry)'; Line = '.flavor/superharness/ralph/' },
        @{ Comment = '# superharness onboarding analysis cache (regenerable, never committed)'; Line = '.flavor/superharness/onboarding/' }
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
