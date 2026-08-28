[CmdletBinding()]
param(
    [string]$RepositoryRoot = $PSScriptRoot,
    [string]$OutputDirectory,
    [switch]$SkipTests,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepositoryRoot 'release'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

$sourceRoot = Join-Path $RepositoryRoot 'template\plugins\superharness'
$claudeManifestPath = Join-Path $sourceRoot '.claude-plugin\plugin.json'
$flavorManifestPath = Join-Path $sourceRoot 'plugin\flavor-plugin.json'

foreach ($path in @($claudeManifestPath, $flavorManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required manifest not found: $path"
    }
}

$claudeManifest = [IO.File]::ReadAllText($claudeManifestPath) | ConvertFrom-Json
$flavorManifest = [IO.File]::ReadAllText($flavorManifestPath) | ConvertFrom-Json
$version = [string]$claudeManifest.version
if ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "Invalid SemVer in $claudeManifestPath`: $version"
}
if ($claudeManifest.name -ne 'superharness' -or $flavorManifest.name -ne 'superharness') {
    throw 'Both manifests must declare name "superharness".'
}

if ([string]$flavorManifest.version -ne $version) {
    $raw = [IO.File]::ReadAllText($flavorManifestPath)
    $pattern = '(?m)^(\s*"version"\s*:\s*")[^"]+("\s*,?\s*)$'
    if ([regex]::Matches($raw, $pattern).Count -ne 1) {
        throw "Could not safely update the version field in $flavorManifestPath"
    }
    $replacement = '${1}' + $version + '${2}'
    $updated = [regex]::Replace($raw, $pattern, $replacement, 1)
    [IO.File]::WriteAllText($flavorManifestPath, $updated, $utf8NoBom)
    Write-Host "Synced flavor-plugin.json version to $version" -ForegroundColor Yellow
}

$required = @(
    (Join-Path $sourceRoot 'plugin\flavor-plugin.json'),
    (Join-Path $sourceRoot 'plugin\index.js'),
    (Join-Path $sourceRoot 'HARNESS.md'),
    (Join-Path $sourceRoot 'skills'),
    (Join-Path $sourceRoot 'scripts\ralph-lib.ps1'),
    (Join-Path $sourceRoot 'scripts\ralph-lib.sh')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required plugin content not found: $path" }
}

if (-not $SkipTests) {
    $testFile = Join-Path $RepositoryRoot 'tests\flavor-plugin.test.mjs'
    Write-Host "Running Flavor plugin tests..." -ForegroundColor Cyan
    & node --test $testFile
    if ($LASTEXITCODE -ne 0) { throw "Flavor plugin tests failed with exit code $LASTEXITCODE" }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stage = Join-Path $OutputDirectory "superharness-$version"
$archive = Join-Path $OutputDirectory "superharness-$version.tgz"

foreach ($target in @($stage, $archive)) {
    $resolvedTarget = [IO.Path]::GetFullPath($target)
    $outputPrefix = $OutputDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTarget.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace a path outside the output directory: $resolvedTarget"
    }
    if (Test-Path -LiteralPath $resolvedTarget) {
        if (-not $Force) { throw "Release output already exists: $resolvedTarget. Re-run with -Force to replace this exact version." }
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'plugin\flavor-plugin.json') -Destination (Join-Path $stage 'flavor-plugin.json')
Copy-Item -LiteralPath (Join-Path $sourceRoot 'plugin\index.js') -Destination (Join-Path $stage 'index.js')
Copy-Item -LiteralPath (Join-Path $sourceRoot 'HARNESS.md') -Destination (Join-Path $stage 'HARNESS.md')
Copy-Item -LiteralPath (Join-Path $sourceRoot 'skills') -Destination $stage -Recurse
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts') -Destination $stage -Recurse

$tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($null -eq $tarCommand) { $tarCommand = Get-Command tar -ErrorAction Stop }
& $tarCommand.Source -czf $archive -C $stage '.'
if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }

& $tarCommand.Source -tzf $archive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Generated archive could not be read: $archive" }

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "" 
Write-Host "Flavor plugin package ready" -ForegroundColor Green
Write-Host "  Version : $version"
Write-Host "  Stage   : $stage"
Write-Host "  Archive : $archive"
Write-Host "  SHA-256 : $hash"
