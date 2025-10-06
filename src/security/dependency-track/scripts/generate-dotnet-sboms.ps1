<#
.SYNOPSIS
    Generates .NET SBOMs using CycloneDX for the specified .NET project paths.

.PARAMETER DotnetProjectsJson
    JSON array of .NET project paths to process.

.PARAMETER OutputDir
    Directory where .NET SBOMs will be written.

.OUTPUTS
    Writes SBOM JSON files to the specified output directory and reports success/failure counts.
#>
param(
    [string]$DotnetProjectsJson = '[]',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'

$projPaths = @()
try {
    $projPaths = $DotnetProjectsJson | ConvertFrom-Json
} catch {
    Write-Host "##vso[task.logissue type=warning]Invalid dotnetProjectsJson: $DotnetProjectsJson"
    $projPaths = @()
}

if ($projPaths.Count -eq 0) {
    Write-Host "##vso[task.logissue type=warning].NET project list empty; skipping"
    exit 0
}

$format = 'Json'; $ext = 'json'
$ok = 0; $fail = 0

foreach ($p in $projPaths) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($p)
    $fileName = "{0}-sbom.{1}" -f $base, $ext

    Write-Host "##[group].NET → $p"
    try {
        dotnet restore "$p" | Out-Null
        dotnet CycloneDX "$p" -o "$OutputDir" -F "$format" -fn "$fileName"
        if ($LASTEXITCODE -ne 0) { throw "CycloneDX exit code: $LASTEXITCODE" }
        if (Test-Path (Join-Path $OutputDir $fileName)) { $ok++ } else { $fail++ }
    } catch {
        Write-Warning "CycloneDX .NET failed: $($_.Exception.Message)"
        $fail++
    } finally {
        Write-Host "Output: $(Join-Path $OutputDir $fileName)"
        Write-Host "##[endgroup]"
    }
}

Write-Host "##[section].NET summary → ok=$ok, failed=$fail"
if ($fail -gt 0) { Write-Host "##vso[task.logissue type=warning]Some .NET SBOMs failed" }
if ($fail -gt 0) { exit 1 }
