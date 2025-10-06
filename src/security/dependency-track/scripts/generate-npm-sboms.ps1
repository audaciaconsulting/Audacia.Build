<#
.SYNOPSIS
    Generates npm SBOMs using CycloneDX for the specified npm project roots.

.PARAMETER NpmRootsJson
    JSON array of npm root directories to process.

.PARAMETER OutputDir
    Directory where npm SBOMs will be written.

.PARAMETER IncludeLicenseTexts
    Whether to include license texts in the SBOMs.

.OUTPUTS
    Writes SBOM JSON files to the specified output directory and reports success/failure counts.
#>
param(
    [string]$NpmRootsJson = '[]',
    [string]$OutputDir = '',
    [bool]$IncludeLicenseTexts = $true
)

$ErrorActionPreference = 'Stop'

# Restore Node tooling from environment variables
if ($env:SBOM_NODE_BIN) { $env:PATH = "$env:SBOM_NODE_BIN;$env:PATH" }

$projects = @()
try {
    $projects = $NpmRootsJson | ConvertFrom-Json
} catch {
    Write-Host "##vso[task.logissue type=warning]Invalid npmRootsJson: $NpmRootsJson"
    $projects = @()
}

$count = ($projects | Measure-Object).Count
if ($count -eq 0) {
    Write-Host "##[section]npm summary → ok=0, failed=0"
    Write-Host "##vso[task.logissue type=warning]No npm projects discovered. Set npmRootsMultiline or commit lockfiles."
    exit 0
}

$npmOk = 0; $npmFail = 0
$format = 'json'; $fileExt = 'json'

foreach ($proj in $projects) {
    $name = Split-Path $proj -Leaf
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'app' }
    $safe = ($name -replace '[<>:"/\\|?*]', '-').Trim().TrimEnd('.',' ')
    $outDir = Join-Path $OutputDir $safe
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $outFile = Join-Path $outDir ("$safe-sbom.$fileExt")

    Write-Host "##[group]JS SBOM → $proj"
    Push-Location $proj
    try {
        $hasLock = Test-Path -LiteralPath (Join-Path $proj 'package-lock.json')
        if (-not $hasLock -and (Test-Path -LiteralPath (Join-Path $proj 'package.json'))) {
            npm install --package-lock-only --ignore-scripts --no-audit --no-fund
            $hasLock = Test-Path -LiteralPath (Join-Path $proj 'package-lock.json')
            if (-not $hasLock) { throw "Failed to create package-lock.json" }
        }

        $nodeModules = Join-Path $proj 'node_modules'
        $needInstall = -not (Test-Path $nodeModules) -or @((Get-ChildItem -Path $nodeModules -Force -ErrorAction SilentlyContinue) | Measure-Object).Count -eq 0
        if ($needInstall) {
            npm ci --ignore-scripts --no-audit --no-fund --no-progress
        }

        $args = @('--output-format', $format, '--output-file', $outFile)
        if ($IncludeLicenseTexts) { $args += @('--gather-license-texts') }

        npx --yes -p @cyclonedx/cyclonedx-npm@latest cyclonedx-npm @args

        if (Test-Path $outFile) { $npmOk++ } else { $npmFail++ }
    } catch {
        Write-Warning "cyclonedx-npm failed: $($_.Exception.Message)"
        $npmFail++
    } finally {
        Pop-Location | Out-Null
        Write-Host "Output: $outFile"
        Write-Host "##[endgroup]"
    }
}

Write-Host "##[section]npm summary → ok=$npmOk, failed=$npmFail"
if ($npmFail -gt 0) { Write-Host "##vso[task.logissue type=warning]Some JS SBOMs failed" }
if ($npmFail -gt 0) { exit 1 }
