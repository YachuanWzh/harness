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
    param([string]$TargetDir, [string]$Template, [string]$Stack)
    $extra = @()
    if ($Template) { $extra += "--template=$Template" }
    if ($Stack)    { $extra += "--stack=$Stack" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScript -TargetDir $TargetDir @extra | Out-Null
    return $LASTEXITCODE
}

function Get-MarketDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness' }
function Get-PluginDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness\plugins\superharness' }

function Set-RalphPendingPrompt {
    param([string]$Cwd, [string]$Query, [string]$Ts = '2026-06-16T10:00:00+08:00')
    $dir = Join-Path $Cwd 'superharness\ralph'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $u = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $dir '.pending-prompt.json'), (ConvertTo-Json @{ ts = $Ts; query = $Query } -Compress), $u)
}

function Invoke-HookJson {
    param([string]$ScriptPath, $InputObj)
    $json = ConvertTo-Json -InputObject $InputObj -Depth 12 -Compress
    $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath | Out-Null
    return $LASTEXITCODE
}

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

# ---------------------------------------------------------------- Test group 1.7: legacy cleanup + docs
Write-Host "`n[1.7] Installer cleans legacy install and updates docs"
$proj4 = New-TempProject
$legacy = Join-Path $proj4 '.claude\skills\superharness'
New-Item -ItemType Directory -Force $legacy | Out-Null
Set-Content -Path (Join-Path $legacy 'dummy.txt') -Value 'old' -Encoding utf8
Invoke-Installer -TargetDir $proj4 | Out-Null
Assert-True (-not (Test-Path $legacy)) "removes legacy .claude/skills/superharness directory"

$cm4 = Get-Content (Join-Path $proj4 'CLAUDE.md') -Raw
Assert-True ($cm4 -match '\.claude/superharness') "CLAUDE.md section points to .claude/superharness"
Assert-True ($cm4 -notmatch 'skills-dir') "CLAUDE.md section no longer mentions skills-dir"
Assert-True ($cm4 -match 'superharness:brainstorm') "CLAUDE.md mentions /superharness:brainstorm"

$harnessDoc = Get-Content (Join-Path (Get-PluginDir $proj4) 'HARNESS.md') -Raw
Assert-True ($harnessDoc -notmatch 'skills-dir') "HARNESS.md no longer mentions skills-dir loading"
Assert-True ($harnessDoc -match 'superharness:brainstorm') "HARNESS.md lists the brainstorm skill"

$pj = Get-Content (Join-Path (Get-PluginDir $proj4) '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json
Assert-True ($pj.version -eq '2.0.0') "plugin.json version bumped to 2.0.0"

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

# brainstorm skill: present, manual-only, documents the message protocol
$bsSkillPath = Join-Path $plugin 'skills\brainstorm\SKILL.md'
Assert-True (Test-Path $bsSkillPath) "includes brainstorm skill (/superharness:brainstorm)"
$bs = if (Test-Path $bsSkillPath) { Get-Content $bsSkillPath -Raw } else { '' }
Assert-True ($bs -match 'disable-model-invocation:\s*true') "brainstorm skill is manual-only (disable-model-invocation: true)"
Assert-True ($bs -match 'mindmap:snapshot') "brainstorm skill documents the mindmap:snapshot format"
Assert-True ($bs -match 'node:click') "brainstorm skill documents the node:click event format"
Assert-True ($bs -match 'start-server\.ps1') "brainstorm skill references start-server.ps1"
foreach ($f in @('server.cjs','mindmap.html','layout.js','start-server.ps1','stop-server.ps1')) {
    Assert-True (Test-Path (Join-Path $plugin "skills\brainstorm\scripts\$f")) "includes brainstorm script: $f"
}

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

# ---------------------------------------------------------------- Test group 7: brainstorm server scripts
Write-Host "`n[7] Brainstorm start/stop server scripts"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host "  SKIP  node not on PATH - skipping server script tests" -ForegroundColor Yellow
} else {
    $scriptsDir = Join-Path $RepoRoot 'template\plugins\superharness\skills\brainstorm\scripts'
    $projS = New-TempProject
    $startOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'start-server.ps1') -ProjectDir $projS
    Assert-True ($LASTEXITCODE -eq 0) "start-server.ps1 exits 0"
    $infoOk = $false; $info = $null
    try { $info = ($startOut -join "`n") | ConvertFrom-Json; $infoOk = $true } catch {}
    Assert-True $infoOk "start-server.ps1 prints server-info JSON"
    Assert-True ($info.url -match '^http://localhost:\d+$') "server-info has a localhost URL"
    $sessionDir = Split-Path -Parent $info.state_dir
    Assert-True ($sessionDir -like (Join-Path $projS '.superharness\brainstorm\*')) "session dir lives under .superharness/brainstorm/"

    $httpOk = $false
    try { $resp = Invoke-WebRequest -Uri $info.url -UseBasicParsing -TimeoutSec 5; $httpOk = ($resp.StatusCode -eq 200) } catch {}
    Assert-True $httpOk "served URL responds with HTTP 200"

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'stop-server.ps1') -SessionDir $sessionDir | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "stop-server.ps1 exits 0"
    Start-Sleep -Milliseconds 500
    $procGone = $null -eq (Get-Process -Id $info.pid -ErrorAction SilentlyContinue)
    Assert-True $procGone "server process is stopped"
    Assert-True (Test-Path (Join-Path $sessionDir 'state\server-stopped')) "server-stopped marker exists"
    Assert-True (-not (Test-Path (Join-Path $sessionDir 'state\server-info'))) "server-info removed after stop"
    Remove-Item $projS -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- Test group 8: stack guidance source docs
Write-Host "`n[8] Template ships the six stack guidance docs"
$stacksDir = Join-Path $RepoRoot 'template\plugins\superharness\stacks'
$stackDocs = @{
    'frontend-react.md' = 'React'
    'frontend-vue.md'   = 'Vue'
    'backend-python.md' = 'pytest'
    'backend-java.md'   = 'JUnit'
    'backend-node.md'   = 'Jest'
    'fullstack.md'      = 'React'
}
foreach ($doc in $stackDocs.Keys) {
    $p = Join-Path $stacksDir $doc
    Assert-True (Test-Path $p) "template ships stacks/$doc"
    $body = if (Test-Path $p) { Get-Content $p -Raw } else { '' }
    Assert-True ($body -match $stackDocs[$doc]) "stacks/$doc mentions $($stackDocs[$doc])"
    Assert-True ($body -match 'TDD|test') "stacks/$doc covers testing discipline"
}
$fs = Join-Path $stacksDir 'fullstack.md'
$fsBody = if (Test-Path $fs) { Get-Content $fs -Raw } else { '' }
Assert-True ($fsBody -match 'Python') "stacks/fullstack.md mentions Python (combined stack)"

# ---------------------------------------------------------------- Test group 9: --template validation + resolution
Write-Host "`n[9] Installer resolves --template/--stack into STACK.md"
function Get-StackFile { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness\STACK.md' }

# 9a. frontend default -> React
$pf = New-TempProject
Invoke-Installer -TargetDir $pf -Template 'frontend' | Out-Null
$sf = Get-StackFile $pf
Assert-True (Test-Path $sf) "frontend default writes STACK.md"
$sfBody = if (Test-Path $sf) { Get-Content $sf -Raw } else { '' }
Assert-True ($sfBody -match 'React') "frontend default STACK.md is React"
Assert-True ($sfBody -notmatch 'This project''s frontend is \*\*Vue') "frontend default is not Vue"

# 9b. frontend --stack=vue
$pv = New-TempProject
Invoke-Installer -TargetDir $pv -Template 'frontend' -Stack 'vue' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pv) -Raw) -match 'Vue') "frontend --stack=vue STACK.md is Vue"

# 9c. backend default -> Python
$pb = New-TempProject
Invoke-Installer -TargetDir $pb -Template 'backend' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pb) -Raw) -match 'pytest') "backend default STACK.md is Python"

# 9d. backend --stack=java / node
$pj = New-TempProject
Invoke-Installer -TargetDir $pj -Template 'backend' -Stack 'java' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pj) -Raw) -match 'JUnit') "backend --stack=java STACK.md is Java"
$pn = New-TempProject
Invoke-Installer -TargetDir $pn -Template 'backend' -Stack 'node' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pn) -Raw) -match 'Jest|Node') "backend --stack=node STACK.md is Node"

# 9e. fullstack -> React + Python
$pfs = New-TempProject
Invoke-Installer -TargetDir $pfs -Template 'fullstack' | Out-Null
$fsB = Get-Content (Get-StackFile $pfs) -Raw
Assert-True ($fsB -match 'React' -and $fsB -match 'Python') "fullstack STACK.md mentions React and Python"
Assert-True ($fsB -match 'seam|API contract') "fullstack STACK.md covers the integration seam"

# 9f. errors -> non-zero exit
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'bogus') -ne 0) "invalid --template exits non-zero"
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'frontend' -Stack 'python') -ne 0) "invalid stack for template exits non-zero"
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'fullstack' -Stack 'react') -ne 0) "fullstack + --stack exits non-zero"

# 9f2. malformed input -> non-zero exit (don't silently plain-install)
$InstallScriptRef = $InstallScript
function Invoke-Raw { param([string]$TargetDir, [string[]]$ExtraArgs)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScriptRef -TargetDir $TargetDir @ExtraArgs | Out-Null
    return $LASTEXITCODE
}
Assert-True ((Invoke-Raw (New-TempProject) @('--template=')) -ne 0) "empty --template= exits non-zero"
Assert-True ((Invoke-Raw (New-TempProject) @('--template')) -ne 0) "bare --template (no value) exits non-zero"
Assert-True ((Invoke-Raw (New-TempProject) @('--stack=vue')) -ne 0) "--stack without --template exits non-zero"

# 9g. backward compat: no --template -> no STACK.md
$pnone = New-TempProject
Invoke-Installer -TargetDir $pnone | Out-Null
Assert-True (-not (Test-Path (Get-StackFile $pnone))) "no --template leaves no STACK.md"

# 9h. plain re-install after a template removes STACK.md
Invoke-Installer -TargetDir $pf | Out-Null
Assert-True (-not (Test-Path (Get-StackFile $pf))) "plain re-install removes a previously written STACK.md"

Remove-Item $pf, $pv, $pb, $pj, $pn, $pfs, $pnone -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 10: hook injects STACK.md
Write-Host "`n[10] session-start.ps1 appends STACK.md when present"
$ph = New-TempProject
Invoke-Installer -TargetDir $ph -Template 'frontend' -Stack 'vue' | Out-Null
$pluginH = Get-PluginDir $ph
$env:CLAUDE_PLUGIN_ROOT = $pluginH
$outH = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginH 'hooks\session-start.ps1')) -join "`n"
Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
$ctxH = ''
try { $ctxH = ($outH | ConvertFrom-Json).hookSpecificOutput.additionalContext } catch {}
Assert-True ($ctxH -match 'superharness') "hook still injects HARNESS.md"
Assert-True ($ctxH -match 'Vue') "hook appends STACK.md (Vue) when present"

# absent STACK.md -> unchanged (no stack marker)
$ph2 = New-TempProject
Invoke-Installer -TargetDir $ph2 | Out-Null
$pluginH2 = Get-PluginDir $ph2
$env:CLAUDE_PLUGIN_ROOT = $pluginH2
$outH2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginH2 'hooks\session-start.ps1')) -join "`n"
Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
$ctxH2 = ''
try { $ctxH2 = ($outH2 | ConvertFrom-Json).hookSpecificOutput.additionalContext } catch {}
Assert-True ($ctxH2 -notmatch 'Frontend stack:') "hook omits stack guidance when no STACK.md"

Remove-Item $ph, $ph2 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 11: trace hooks install
Write-Host "`n[11] Installer registers SessionStart + UserPromptSubmit + Stop and ships ralph-lib"
$hk = Get-Content (Join-Path $plugin 'hooks\hooks.json') -Raw | ConvertFrom-Json
Assert-True ($null -ne $hk.hooks.SessionStart) "hooks.json still registers SessionStart"
Assert-True ($null -ne $hk.hooks.UserPromptSubmit) "hooks.json registers a UserPromptSubmit hook"
Assert-True ($null -ne $hk.hooks.Stop) "hooks.json registers a Stop hook"
Assert-True (Test-Path (Join-Path $plugin 'hooks\user-prompt-submit.ps1')) "ships hooks/user-prompt-submit.ps1"
Assert-True (Test-Path (Join-Path $plugin 'hooks\stop.ps1')) "ships hooks/stop.ps1"
Assert-True (Test-Path (Join-Path $plugin 'scripts\ralph-lib.ps1')) "ships scripts/ralph-lib.ps1 for the hooks"
Assert-True (-not (Test-Path (Join-Path $plugin 'hooks\trace-lib.ps1'))) "old hooks/trace-lib.ps1 is gone"
Assert-True (-not (Test-Path (Join-Path $plugin 'skills\resume\SKILL.md'))) "resume skill is removed (auto-retry replaces manual resume)"

# dot-source ralph-lib so the test process can assert on ralph state
. (Join-Path $plugin 'scripts\ralph-lib.ps1')

# ---------------------------------------------------------------- Test group 12: UserPromptSubmit behavior
Write-Host "`n[12] user-prompt-submit.ps1 stashes the pending round under superharness/ralph/"
$cwd12 = New-TempProject
$ex12 = Invoke-HookJson (Join-Path $plugin 'hooks\user-prompt-submit.ps1') @{ cwd = $cwd12; session_id = 's1'; prompt = 'hello world' }
Assert-True ($ex12 -eq 0) "user-prompt-submit exits 0"
$pf12 = Join-Path $cwd12 'superharness\ralph\.pending-prompt.json'
Assert-True (Test-Path $pf12) "writes superharness/ralph/.pending-prompt.json"
$pj12 = $null; try { $pj12 = Get-Content $pf12 -Raw | ConvertFrom-Json } catch {}
Assert-True ($null -ne $pj12 -and $pj12.query -eq 'hello world') "pending-prompt captures the user query"
Assert-True ($null -ne $pj12 -and $pj12.ts -match '^\d{4}-\d{2}-\d{2}T') "pending-prompt captures an ISO timestamp"
Remove-Item $cwd12 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 13: Stop hook records a round heartbeat
Write-Host "`n[13] stop.ps1 appends a round event to trace.jsonl when a go task is active"
$stop = Join-Path $plugin 'hooks\stop.ps1'

# 13a. active task -> round heartbeat appended, pending prompt consumed
$c1 = New-TempProject
Set-RalphCurrentTask -Root $c1 -TaskId '2026-06-16-x'
Initialize-RalphTasks -Root $c1 -Tasks @(@{ id = 1; name = 'a' }) -Phase 'implement'
Set-RalphPendingPrompt -Cwd $c1 -Query 'do the thing'
$e1 = Invoke-HookJson $stop @{ cwd = $c1; session_id = 's1' }
Assert-True ($e1 -eq 0) "stop exits 0 on an active task"
$tr1 = Join-Path $c1 'superharness\ralph\trace.jsonl'
Assert-True (Test-Path $tr1) "stop creates/appends superharness/ralph/trace.jsonl"
$tail1 = @(Get-RalphTraceTail -Root $c1 -Count 1)
Assert-True ($tail1.Count -eq 1 -and $tail1[0].event -eq 'round') "appends a 'round' event"
Assert-True ($tail1[0].detail -eq 'do the thing') "round detail carries the user query"
Assert-True ($tail1[0].phase -eq 'implement') "round phase comes from task.json"
Assert-True (-not (Test-Path (Join-Path $c1 'superharness\ralph\.pending-prompt.json'))) "pending-prompt consumed"

# 13b. second round appends a second line (append-only)
Set-RalphPendingPrompt -Cwd $c1 -Query 'round two'
Invoke-HookJson $stop @{ cwd = $c1; session_id = 's1' } | Out-Null
$lines1 = @((Get-Content $tr1) | Where-Object { $_.Trim() -ne '' })
Assert-True ($lines1.Count -eq 2) "second round is appended (append-only ledger)"

# 13c. active task but no pending prompt -> still records a round (empty detail)
$c2 = New-TempProject
Set-RalphCurrentTask -Root $c2 -TaskId '2026-06-16-y'
$e2 = Invoke-HookJson $stop @{ cwd = $c2; session_id = 's2' }
Assert-True ($e2 -eq 0) "stop exits 0 with no pending prompt"
$tail2 = @(Get-RalphTraceTail -Root $c2 -Count 1)
Assert-True ($tail2.Count -eq 1 -and $tail2[0].event -eq 'round') "records a round even without a pending prompt"
Assert-True ($tail2[0].phase -eq 'go') "phase defaults to 'go' when no task.json"

# 13d. no .current-task -> no-op (no ledger, stray pending cleaned)
$c3 = New-TempProject
Set-RalphPendingPrompt -Cwd $c3 -Query 'stray'
$e3 = Invoke-HookJson $stop @{ cwd = $c3; session_id = 's3' }
Assert-True ($e3 -eq 0) "stop exits 0 when no task is active"
Assert-True (-not (Test-Path (Join-Path $c3 'superharness\ralph\trace.jsonl'))) "no trace.jsonl created without a task"
Assert-True (-not (Test-Path (Join-Path $c3 'superharness\ralph\.pending-prompt.json'))) "stray pending-prompt cleaned when no task"

# 13e. malformed / empty stdin -> exit 0, no throw
$e4a = '' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4a = $LASTEXITCODE
$e4b = 'not json' | & powershell -NoProfile -ExecutionPolicy Bypass -File $stop; $e4b = $LASTEXITCODE
Assert-True ($e4a -eq 0) "stop exits 0 on empty stdin"
Assert-True ($e4b -eq 0) "stop exits 0 on malformed stdin"

Remove-Item $c1, $c2, $c3 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 15: go skill drives ralph tracking
Write-Host "`n[15] go skill drives the ralph state mechanism with in-run auto-retry"
$goMd = Get-Content (Join-Path $plugin 'skills\go\SKILL.md') -Raw
Assert-True ($goMd -match 'superharness/ralph') "go skill documents the superharness/ralph/ location"
Assert-True ($goMd -match 'Set-RalphCurrentTask' -and $goMd -match '\.current-task') "go skill sets the .current-task pointer"
Assert-True ($goMd -match 'Initialize-RalphTasks') "go skill seeds the ralph task list"
Assert-True ($goMd -match 'Add-RalphTrace' -and $goMd -match 'trace\.jsonl') "go skill records execution events to trace.jsonl"
Assert-True ($goMd -match 'Set-RalphTaskStatus') "go skill flips per-task status as work completes"
Assert-True ($goMd -match 'Add-RalphRetry' -and $goMd -match 'Test-RalphRetryExhausted') "go skill drives the retry counter"
Assert-True ($goMd -match '(?i)auto(matic)?[- ]?retr' -and $goMd -match '5') "go skill documents in-run auto-retry capped at 5"
Assert-True ($goMd -match '(?i)one active') "go skill documents one active go task per project"
Assert-True ($goMd -notmatch 'superharness/trace') "go skill no longer references the old superharness/trace/ mechanism"
Assert-True ($goMd -notmatch 'outcome\.json') "go skill no longer references outcome.json markers"
Assert-True ($goMd -match 'using-git-worktrees') "go skill still delegates isolation to using-git-worktrees"
Assert-True ($goMd -match 'subagent-driven-development') "go skill still delegates Phase 2 to subagent-driven-development"

# ---------------------------------------------------------------- Test group 18: subagent-driven + worktree skills
Write-Host "`n[18] Subagent-driven implementation and worktree isolation skills"

# using-git-worktrees skill
$wtPath = Join-Path $plugin 'skills\using-git-worktrees\SKILL.md'
Assert-True (Test-Path $wtPath) "ships skills/using-git-worktrees/SKILL.md"
$wtMd = if (Test-Path $wtPath) { Get-Content $wtPath -Raw } else { '' }
Assert-True ($wtMd -match 'git worktree') "worktree skill uses git worktree"
Assert-True ($wtMd -match '(?i)not a git|no git repo|work in place') "worktree skill degrades when there is no git repo"
Assert-True ($wtMd -match '(?i)by default') "worktree skill documents create-by-default for go"

# subagent-driven-development skill
$sdPath = Join-Path $plugin 'skills\subagent-driven-development\SKILL.md'
Assert-True (Test-Path $sdPath) "ships skills/subagent-driven-development/SKILL.md"
$sdMd = if (Test-Path $sdPath) { Get-Content $sdPath -Raw } else { '' }
Assert-True ($sdMd -match '(?i)fresh subagent') "subagent skill dispatches a fresh subagent per task"
Assert-True ($sdMd -match 'superharness:test-driven-development') "subagent skill delegates TDD to test-driven-development"
Assert-True ($sdMd -match '(?i)self-review') "subagent skill keeps per-task review to self-review only"

# go wires both phases in
$goMd3 = Get-Content (Join-Path $plugin 'skills\go\SKILL.md') -Raw
Assert-True ($goMd3 -match 'using-git-worktrees') "go skill delegates isolation to using-git-worktrees"
Assert-True ($goMd3 -match 'subagent-driven-development') "go skill delegates Phase 2 to subagent-driven-development"
Assert-True ($goMd3 -match '(?i)Phase 0.5|Isolate') "go skill adds the Isolate phase"

# HARNESS lists both
$harnessDoc2 = Get-Content (Join-Path $plugin 'HARNESS.md') -Raw
Assert-True ($harnessDoc2 -match 'using-git-worktrees') "HARNESS.md lists using-git-worktrees"
Assert-True ($harnessDoc2 -match 'subagent-driven-development') "HARNESS.md lists subagent-driven-development"

# ---------------------------------------------------------------- Test group 17a: ralph-lib ships + .current-task
Write-Host "`n[17a] ralph-lib.ps1 ships and .current-task round-trips a single line"
$ralphLib = Join-Path $plugin 'scripts\ralph-lib.ps1'
Assert-True (Test-Path $ralphLib) "installer ships scripts/ralph-lib.ps1"
if (Test-Path $ralphLib) { . $ralphLib }

$rp1 = New-TempProject
Set-RalphCurrentTask -Root $rp1 -TaskId '2026-06-16-foo'
$ctPath = Join-Path $rp1 'superharness\ralph\.current-task'
Assert-True (Test-Path $ctPath) "Set-RalphCurrentTask writes superharness/ralph/.current-task"
Assert-True ((Get-RalphCurrentTask -Root $rp1) -eq '2026-06-16-foo') "Get-RalphCurrentTask round-trips the id"
$ctLines1 = @((Get-Content $ctPath) | Where-Object { $_.Trim() -ne '' })
Assert-True ($ctLines1.Count -eq 1) ".current-task holds exactly one non-empty line"
Set-RalphCurrentTask -Root $rp1 -TaskId '2026-06-16-bar'
Assert-True ((Get-RalphCurrentTask -Root $rp1) -eq '2026-06-16-bar') "re-setting overwrites (switch only rewrites the line)"
$ctLines2 = @((Get-Content $ctPath) | Where-Object { $_.Trim() -ne '' })
Assert-True ($ctLines2.Count -eq 1) "still one line after switch (no append)"
Assert-True ((Get-RalphCurrentTask -Root (New-TempProject)) -eq $null) "Get-RalphCurrentTask returns null when absent"
Remove-Item $rp1 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 17b: task.json task list
Write-Host "`n[17b] task.json holds an idempotent per-task status list"
$rp2 = New-TempProject
Initialize-RalphTasks -Root $rp2 -Tasks @(
    @{ id=1; name='scaffold' },
    @{ id=2; name='ledger'; status='done' },
    @{ id=3; name='retry' }
) -SprintTotal 7
$tjPath = Join-Path $rp2 'superharness\ralph\task.json'
Assert-True (Test-Path $tjPath) "Initialize-RalphTasks writes superharness/ralph/task.json"
$tjLines = @((Get-Content $tjPath) | Where-Object { $_.Trim() -ne '' })
Assert-True ($tjLines.Count -eq 1) "task.json is a single minified line"
$tj = Get-RalphTasks -Root $rp2
Assert-True ($tj.status -eq 'planning') "default overall status is planning"
Assert-True ($tj.phase -eq 'implement') "default phase is implement"
Assert-True ($tj.sprint.total -eq 7) "sprint.total recorded"
Assert-True (@($tj.tasks).Count -eq 3) "all tasks recorded"
Assert-True ((@($tj.tasks) | Where-Object { $_.id -eq 1 }).status -eq 'pending') "unset task defaults to pending"
Assert-True ((@($tj.tasks) | Where-Object { $_.id -eq 2 }).status -eq 'done') "explicit done status preserved"
Assert-True ($tj.updated_at -match '^\d{4}-\d{2}-\d{2}T') "updated_at is an ISO timestamp"

$next = Get-RalphNextTask -Root $rp2
Assert-True ($next.id -eq 1) "Get-RalphNextTask returns the first not-done task"

$before = (Get-RalphTasks -Root $rp2).updated_at
Start-Sleep -Milliseconds 1100
Set-RalphTaskStatus -Root $rp2 -Id 1 -Status 'done'
$tj2 = Get-RalphTasks -Root $rp2
Assert-True ((@($tj2.tasks) | Where-Object { $_.id -eq 1 }).status -eq 'done') "Set-RalphTaskStatus flips the task status"
Assert-True ($tj2.updated_at -ne $before) "updated_at refreshed on every write"
Assert-True ((Get-RalphNextTask -Root $rp2).id -eq 3) "next now skips both done tasks to task 3"
Set-RalphTaskStatus -Root $rp2 -Id 1 -Status 'done'
Assert-True (@((Get-RalphTasks -Root $rp2).tasks).Count -eq 3) "idempotent re-set keeps the task count"
Set-RalphTaskStatus -Root $rp2 -Id 3 -Status 'done'
Assert-True ((Get-RalphNextTask -Root $rp2) -eq $null) "Get-RalphNextTask is null when all tasks are done"
Remove-Item $rp2 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 17c: trace.jsonl append-only ledger
Write-Host "`n[17c] trace.jsonl is an append-only ledger"
$rp3 = New-TempProject
Add-RalphTrace -Root $rp3 -Phase 'implement' -Event 'implement:start' -Detail 'Dispatching subagent'
$trPath = Join-Path $rp3 'superharness\ralph\trace.jsonl'
Assert-True (Test-Path $trPath) "Add-RalphTrace creates superharness/ralph/trace.jsonl"
$firstBytes = [IO.File]::ReadAllText($trPath)
Add-RalphTrace -Root $rp3 -Phase 'implement' -Event 'implement:done' -Detail 'Green'
$allLines = @((Get-Content $trPath) | Where-Object { $_.Trim() -ne '' })
Assert-True ($allLines.Count -eq 2) "each call appends exactly one line"
Assert-True ([IO.File]::ReadAllText($trPath).StartsWith($firstBytes)) "earlier line is byte-for-byte unchanged after append (append-only)"
$tail = @(Get-RalphTraceTail -Root $rp3 -Count 1)
Assert-True ($tail.Count -eq 1 -and $tail[0].event -eq 'implement:done') "Get-RalphTraceTail returns the last event"
$tail2 = @(Get-RalphTraceTail -Root $rp3 -Count 2)
Assert-True ($tail2.Count -eq 2 -and $tail2[0].event -eq 'implement:start' -and $tail2[1].event -eq 'implement:done') "tail preserves chronological order"
Assert-True ($tail[0].ts -match '^\d{4}-\d{2}-\d{2}T') "trace event carries an ISO ts"
Assert-True (@(Get-RalphTraceTail -Root (New-TempProject)).Count -eq 0) "tail of a missing trace is empty"
Remove-Item $rp3 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 17d: .ralph-state.json retry counter
Write-Host "`n[17d] .ralph-state.json retry counter caps at 5"
$rp4 = New-TempProject
$st0 = Get-RalphRetryState -Root $rp4
Assert-True ($st0.retries -eq 0 -and $st0.max -eq 5) "defaults to retries=0, max=5 when absent"
Assert-True (-not (Test-RalphRetryExhausted -Root $rp4)) "not exhausted at 0 retries"
1..5 | ForEach-Object { Add-RalphRetry -Root $rp4 | Out-Null }
$rsPath = Join-Path $rp4 'superharness\ralph\.ralph-state.json'
Assert-True (Test-Path $rsPath) ".ralph-state.json is written"
Assert-True ((Get-RalphRetryState -Root $rp4).retries -eq 5) "Add-RalphRetry increments and persists"
Assert-True (Test-RalphRetryExhausted -Root $rp4) "exhausted at the cap of 5"
Add-RalphRetry -Root $rp4 | Out-Null
Assert-True ((Get-RalphRetryState -Root $rp4).retries -eq 5) "retries never exceed the cap of 5"
Reset-RalphRetry -Root $rp4 | Out-Null
Assert-True ((Get-RalphRetryState -Root $rp4).retries -eq 0) "Reset-RalphRetry returns the counter to 0"
Assert-True (-not (Test-RalphRetryExhausted -Root $rp4)) "not exhausted after reset"
Remove-Item $rp4 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 17e: cold-start resume context
Write-Host "`n[17e] Get-RalphResumeContext assembles the cold-start facts"
$rp5 = New-TempProject
Set-RalphCurrentTask -Root $rp5 -TaskId '2026-06-16-demo'
Initialize-RalphTasks -Root $rp5 -Tasks @(@{id=1;name='a';status='done'},@{id=2;name='b'}) -SprintTotal 2
Add-RalphTrace -Root $rp5 -Phase 'implement' -Event 'task1:done' -Detail 'done a'
Add-RalphTrace -Root $rp5 -Phase 'implement' -Event 'task2:start' -Detail 'starting b'
$ctx = Get-RalphResumeContext -Root $rp5
Assert-True ($ctx.current_task -eq '2026-06-16-demo') "context carries the .current-task pointer"
Assert-True ($ctx.next_task.id -eq 2) "context.next_task is the first not-done task"
Assert-True ($ctx.last_trace.event -eq 'task2:start') "context.last_trace is the latest ledger event"
Assert-True ($ctx.all_done -eq $false) "all_done is false while a task remains"
Assert-True (@($ctx.tasks.tasks).Count -eq 2) "context carries the task snapshot"

Set-RalphTaskStatus -Root $rp5 -Id 2 -Status 'done'
$ctxDone = Get-RalphResumeContext -Root $rp5
Assert-True ($ctxDone.all_done -eq $true) "all_done is true once every task is done"
Assert-True ($ctxDone.next_task -eq $null) "next_task is null when all tasks are done"

$ctxEmpty = Get-RalphResumeContext -Root (New-TempProject)
Assert-True ($ctxEmpty.current_task -eq $null -and $ctxEmpty.next_task -eq $null -and $ctxEmpty.all_done -eq $false) "empty project yields a well-formed null context (no throw)"
Remove-Item $rp5 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- Test group 17f: README documents the mechanism
Write-Host "`n[17f] README documents the ralph state mechanism"
$readmeRalph = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
Assert-True ($readmeRalph -match 'superharness/ralph/') "README documents the superharness/ralph/ location"
Assert-True ($readmeRalph -match '\.current-task' -and $readmeRalph -match 'trace\.jsonl' -and $readmeRalph -match '\.ralph-state\.json') "README documents all four ralph files"
Assert-True ($readmeRalph -match 'Get-RalphResumeContext') "README documents the cold-start resume context function"

# ---------------------------------------------------------------- cleanup + summary
Remove-Item $proj, $proj2, $proj3, $proj4, $emptyDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== Results: $script:Passed passed, $script:Failed failed ===" -ForegroundColor Cyan
if ($script:Failed -gt 0) {
    $script:Failures | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red }
    exit 1
}
exit 0
