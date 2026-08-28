# Superharness SessionStart hook.
# Reads HARNESS.md from the plugin root and injects it into the session as
# additionalContext, so Claude Code starts every session with the harness rules loaded.
# Always exits 0: a broken hook must never block a session.

$ErrorActionPreference = 'SilentlyContinue'

$pluginRoot = $env:CLAUDE_PLUGIN_ROOT
if (-not $pluginRoot) { $pluginRoot = Split-Path -Parent $PSScriptRoot }

$harnessPath = Join-Path $pluginRoot 'HARNESS.md'
if (-not (Test-Path $harnessPath)) { exit 0 }

$content = Get-Content $harnessPath -Raw -Encoding UTF8
if (-not $content) { exit 0 }

$context = "<EXTREMELY_IMPORTANT>`nYou have superharness. Follow it for all engineering work in this project.`n`n$content`n</EXTREMELY_IMPORTANT>"

# Append the active tech-stack guidance (STACK.md lives at <marketplace root> = pluginRoot\..\..).
$stackPath = Join-Path (Split-Path -Parent (Split-Path -Parent $pluginRoot)) 'STACK.md'
if (Test-Path $stackPath) {
    $stackContent = Get-Content $stackPath -Raw -Encoding UTF8
    if ($stackContent) {
        $context += "`n`n<EXTREMELY_IMPORTANT>`nThis project targets a specific tech stack. Follow this guidance.`n`n$stackContent`n</EXTREMELY_IMPORTANT>"
    }
}

# Append the onboarding nudge when the workspace has neither the generated
# doc nor an analysis cache (mirrors the flavor-code plugin's SessionStart).
# Manual-only: hint the command, never auto-analyze.
$workspace = (Get-Location).Path
$onboardingDoc  = Join-Path $workspace 'ONBOARDING.md'
$onboardingCache = Join-Path $workspace '.claude\superharness\onboarding\cache.json'
if (-not (Test-Path $onboardingDoc) -and -not (Test-Path $onboardingCache)) {
    $context += "`n`n<superharness-onboarding-hint>`nNo onboarding guide for this workspace yet. Run /onboarding (superharness:onboarding) to analyze the codebase, map module business relationships, and generate ONBOARDING.md plus an interactive module mind map. The agent decides when to run it - nothing is analyzed automatically.`n</superharness-onboarding-hint>"
}

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $context
    }
}

# ConvertTo-Json handles all JSON escaping (quotes, newlines, unicode).
$json = $payload | ConvertTo-Json -Depth 4
[Console]::Out.Write($json)
exit 0
