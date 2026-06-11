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
