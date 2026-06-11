# Superharness installer & hook test suite (zero-dependency, Windows PowerShell 5.1 compatible)
# TDD: these tests were written BEFORE the implementation.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallScript = Join-Path $RepoRoot 'lib\install.ps1'

$script:Passed = 0
$script:Failed = 0
$script:Failures = @()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS  $Message" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Failures += $Message
        Write-Host "  FAIL  $Message" -ForegroundColor Red
    }
}

function New-TempProject {
    $dir = Join-Path $env:TEMP ("superharness-test-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Invoke-Installer {
    param([string]$TargetDir)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScript -TargetDir $TargetDir | Out-Null
    return $LASTEXITCODE
}

function Get-MarketDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness' }
function Get-PluginDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness\plugins\superharness' }

Write-Host "`n=== Superharness test suite ===" -ForegroundColor Cyan

# ---------------------------------------------------------------- Test group 1: installer output
Write-Host "`n[1] Installer creates the project-level superharness plugin folder"
$proj = New-TempProject
$exit = Invoke-Installer -TargetDir $proj
$plugin = Get-PluginDir $proj

Assert-True ($exit -eq 0) "installer exits with code 0"
Assert-True (Test-Path (Join-Path $plugin '.claude-plugin\plugin.json')) "creates plugin manifest under plugins/superharness/.claude-plugin/"

$manifestOk = $false; $manifestName = ''
try {
    $m = Get-Content (Join-Path $plugin '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json
    $manifestOk = $true; $manifestName = $m.name
} catch {}
Assert-True $manifestOk "plugin.json is valid JSON"
Assert-True ($manifestName -eq 'superharness') "plugin.json name is 'superharness' (gives /superharness:* namespace)"

Assert-True (Test-Path (Join-Path $plugin 'HARNESS.md')) "creates HARNESS.md bootstrap document"
$harness = if (Test-Path (Join-Path $plugin 'HARNESS.md')) { Get-Content (Join-Path $plugin 'HARNESS.md') -Raw } else { '' }
Assert-True ($harness -match 'TDD|test-driven') "HARNESS.md mandates TDD"

# ---------------------------------------------------------------- Test group 1.5: marketplace layout
Write-Host "`n[1.5] Installer creates a local directory marketplace"
$market = Get-MarketDir $proj
$mpJsonPath = Join-Path $market '.claude-plugin\marketplace.json'
Assert-True (Test-Path $mpJsonPath) "creates .claude-plugin/marketplace.json at marketplace root"
$mpOk = $false; $mpName = ''; $mpSrc = ''
try {
    $mp = Get-Content $mpJsonPath -Raw | ConvertFrom-Json
    $mpOk = $true; $mpName = $mp.name; $mpSrc = $mp.plugins[0].source
} catch {}
Assert-True $mpOk "marketplace.json is valid JSON"
Assert-True ($mpName -eq 'superharness') "marketplace name is 'superharness'"
Assert-True ($mpSrc -eq './plugins/superharness') "marketplace lists plugin source ./plugins/superharness"
Assert-True (-not (Test-Path (Join-Path $proj '.claude\skills\superharness'))) "does not install to legacy .claude/skills/superharness path"

# ---------------------------------------------------------------- Test group 1.6: settings.json merge
Write-Host "`n[1.6] Installer enables the plugin via .claude/settings.json"
$settingsPath = Join-Path $proj '.claude\settings.json'
Assert-True (Test-Path $settingsPath) "creates .claude/settings.json"
$stOk = $false; $srcType = ''; $srcPath = ''; $enabled = $null
try {
    $st = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $stOk = $true
    $srcType = $st.extraKnownMarketplaces.superharness.source.source
    $srcPath = $st.extraKnownMarketplaces.superharness.source.path
    $enabled = $st.enabledPlugins.'superharness@superharness'
} catch {}
Assert-True $stOk "settings.json is valid JSON"
Assert-True ($srcType -eq 'directory') "extraKnownMarketplaces.superharness uses a directory source"
Assert-True ($srcPath -eq '.claude/superharness') "marketplace path is .claude/superharness"
Assert-True ($enabled -eq $true) "enabledPlugins['superharness@superharness'] is true"

# preserve existing settings keys
$proj3 = New-TempProject
New-Item -ItemType Directory -Force (Join-Path $proj3 '.claude') | Out-Null
Set-Content -Path (Join-Path $proj3 '.claude\settings.json') -Value '{"model":"opus","enabledPlugins":{"other@mp":true}}' -Encoding utf8
Invoke-Installer -TargetDir $proj3 | Out-Null
$st3 = Get-Content (Join-Path $proj3 '.claude\settings.json') -Raw | ConvertFrom-Json
Assert-True ($st3.model -eq 'opus') "existing settings keys are preserved"
Assert-True ($st3.enabledPlugins.'other@mp' -eq $true) "existing enabledPlugins entries are preserved"
Assert-True ($st3.enabledPlugins.'superharness@superharness' -eq $true) "superharness entry added alongside existing ones"

# idempotency
Invoke-Installer -TargetDir $proj3 | Out-Null
$st3b = Get-Content (Join-Path $proj3 '.claude\settings.json') -Raw | ConvertFrom-Json
Assert-True ($st3b.enabledPlugins.'superharness@superharness' -eq $true) "second install keeps settings valid and enabled"

# ---------------------------------------------------------------- Test group 2: skills
Write-Host "`n[2] Installer copies the go skill and the core engineering skills"
Assert-True (Test-Path (Join-Path $plugin 'skills\go\SKILL.md')) "creates skills/go/SKILL.md (/superharness:go entry point)"
$goSkill = if (Test-Path (Join-Path $plugin 'skills\go\SKILL.md')) { Get-Content (Join-Path $plugin 'skills\go\SKILL.md') -Raw } else { '' }
Assert-True ($goSkill -match '\$ARGUMENTS') "go skill consumes the task goal via `$ARGUMENTS"
Assert-True ($goSkill -match 'RED|failing test') "go skill enforces the TDD red-green cycle"

$coreSkills = @('test-driven-development','systematic-debugging','writing-plans','verification-before-completion','requesting-code-review')
foreach ($s in $coreSkills) {
    Assert-True (Test-Path (Join-Path $plugin "skills\$s\SKILL.md")) "includes core skill: $s"
}
Assert-True (Test-Path (Join-Path $plugin 'skills\test-driven-development\testing-anti-patterns.md')) "includes TDD supporting file testing-anti-patterns.md"
Assert-True (Test-Path (Join-Path $plugin 'skills\requesting-code-review\code-reviewer.md')) "includes code-reviewer.md template referenced by requesting-code-review"

# no dangling superpowers: references — copied skills must be patched to superharness:
$dangling = @(Get-ChildItem (Join-Path $plugin 'skills') -Recurse -Filter *.md -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw) -match 'superpowers:' })
Assert-True ($dangling.Count -eq 0) "no skill file references the superpowers: namespace (found: $($dangling.Count))"

# ---------------------------------------------------------------- Test group 3: hooks
Write-Host "`n[3] Installer creates the SessionStart hook"
$hooksJsonPath = Join-Path $plugin 'hooks\hooks.json'
Assert-True (Test-Path $hooksJsonPath) "creates hooks/hooks.json"
$hooksOk = $false; $hasSessionStart = $false
try {
    $h = Get-Content $hooksJsonPath -Raw | ConvertFrom-Json
    $hooksOk = $true
    $hasSessionStart = $null -ne $h.hooks.SessionStart
} catch {}
Assert-True $hooksOk "hooks.json is valid JSON"
Assert-True $hasSessionStart "hooks.json registers a SessionStart hook"
Assert-True (Test-Path (Join-Path $plugin 'hooks\session-start.ps1')) "creates hooks/session-start.ps1"

# ---------------------------------------------------------------- Test group 4: CLAUDE.md integration
Write-Host "`n[4] Installer wires CLAUDE.md (auto-read fallback)"
$claudeMd = Join-Path $proj 'CLAUDE.md'
Assert-True (Test-Path $claudeMd) "creates CLAUDE.md when missing"
$cm = if (Test-Path $claudeMd) { Get-Content $claudeMd -Raw } else { '' }
Assert-True ($cm -match '<!-- SUPERHARNESS:BEGIN -->') "CLAUDE.md contains SUPERHARNESS:BEGIN marker"
Assert-True ($cm -match '<!-- SUPERHARNESS:END -->') "CLAUDE.md contains SUPERHARNESS:END marker"
Assert-True ($cm -match 'superharness:go') "CLAUDE.md mentions /superharness:go"

# existing CLAUDE.md content is preserved
$proj2 = New-TempProject
Set-Content -Path (Join-Path $proj2 'CLAUDE.md') -Value '# My existing project rules' -Encoding utf8
Invoke-Installer -TargetDir $proj2 | Out-Null
$cm2 = Get-Content (Join-Path $proj2 'CLAUDE.md') -Raw
Assert-True ($cm2 -match 'My existing project rules') "existing CLAUDE.md content is preserved"
Assert-True ($cm2 -match '<!-- SUPERHARNESS:BEGIN -->') "superharness section appended to existing CLAUDE.md"

# idempotency: running twice yields exactly one marker pair
Invoke-Installer -TargetDir $proj2 | Out-Null
$cm3 = Get-Content (Join-Path $proj2 'CLAUDE.md') -Raw
$markerCount = ([regex]::Matches($cm3, '<!-- SUPERHARNESS:BEGIN -->')).Count
Assert-True ($markerCount -eq 1) "running installer twice keeps exactly one superharness section (found: $markerCount)"

# ---------------------------------------------------------------- Test group 5: session-start hook behavior
Write-Host "`n[5] session-start.ps1 injects HARNESS.md as additionalContext"
$hookScript = Join-Path $plugin 'hooks\session-start.ps1'
$out = ''
if (Test-Path $hookScript) {
    $env:CLAUDE_PLUGIN_ROOT = $plugin
    $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $hookScript) -join "`n"
    $hookExit = $LASTEXITCODE
    Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
} else { $hookExit = -1 }
Assert-True ($hookExit -eq 0) "hook exits 0 on initialized project"
$hookJsonOk = $false; $evt = ''; $ctx = ''
try {
    $j = $out | ConvertFrom-Json
    $hookJsonOk = $true
    $evt = $j.hookSpecificOutput.hookEventName
    $ctx = $j.hookSpecificOutput.additionalContext
} catch {}
Assert-True $hookJsonOk "hook stdout is valid JSON"
Assert-True ($evt -eq 'SessionStart') "hook output has hookEventName=SessionStart"
Assert-True ($ctx -match 'superharness') "additionalContext carries the HARNESS.md bootstrap"

# missing HARNESS.md -> still exits 0, no crash
$emptyDir = New-TempProject
$env:CLAUDE_PLUGIN_ROOT = $emptyDir
& powershell -NoProfile -ExecutionPolicy Bypass -File $hookScript 2>$null | Out-Null
$emptyExit = $LASTEXITCODE
Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
Assert-True ($emptyExit -eq 0) "hook exits 0 even when HARNESS.md is missing"

# ---------------------------------------------------------------- Test group 6: CLI entry
Write-Host "`n[6] CLI entry point"
Assert-True (Test-Path (Join-Path $RepoRoot 'bin\superharness.cmd')) "bin/superharness.cmd exists (PATH-callable from cmd and PowerShell)"

# ---------------------------------------------------------------- cleanup + summary
Remove-Item $proj, $proj2, $proj3, $emptyDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== Results: $script:Passed passed, $script:Failed failed ===" -ForegroundColor Cyan
if ($script:Failed -gt 0) {
    $script:Failures | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red }
    exit 1
}
exit 0
