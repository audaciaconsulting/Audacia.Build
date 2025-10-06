<#
.SYNOPSIS
    Resolves npm project roots from multiline parameter or auto-discovery.

.PARAMETER RootsMultiline
    Multiline string containing npm root directories (one per line).

.PARAMETER WorkspaceRoot
    The workspace root directory for auto-discovery.

.OUTPUTS
    Sets pipeline variable 'npmRootsJson' containing JSON array of resolved npm root paths.
#>
param(
    [string]$RootsMultiline = '',
    [string]$WorkspaceRoot = $env:SYSTEM_DEFAULTWORKINGDIRECTORY
)

$ErrorActionPreference = 'Stop'

Write-Host "##[group]Discover JS manifests"
$locks_npm = Get-ChildItem -Path $WorkspaceRoot -Recurse -Filter 'package-lock.json' -File -ErrorAction SilentlyContinue
$pkgs      = Get-ChildItem -Path $WorkspaceRoot -Recurse -Filter 'package.json'      -File -ErrorAction SilentlyContinue
Write-Host "Found package-lock.json: $($locks_npm.Count)"
Write-Host "Found package.json:      $($pkgs.Count)"
Write-Host "##[endgroup]"

Write-Host "##[group]Resolve roots"
$rootsParam = $RootsMultiline -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
$projects = New-Object System.Collections.ArrayList

if ($rootsParam.Count -gt 0) {
    foreach ($r in $rootsParam) {
        if (Test-Path (Join-Path $r 'package.json')) {
            [void]$projects.Add($r)
            Write-Host "Root (param): $r"
        } else {
            Write-Warning "package.json not found under: $r (skipped)"
        }
    }
} else {
    if ($locks_npm.Count -gt 0) {
        foreach ($l in $locks_npm) { [void]$projects.Add($l.Directory.FullName) }
    } elseif ($pkgs.Count -gt 0) {
        foreach ($p in $pkgs) { [void]$projects.Add($p.Directory.FullName) }
    }
    $projects = $projects | Select-Object -Unique
    foreach ($p in $projects) { Write-Host "Root (auto): $p" }
}
Write-Host "##[endgroup]"

$projectsArray = @($projects)
$npmRootsJson = $projectsArray | ConvertTo-Json -Compress
Write-Host "##vso[task.setvariable variable=npmRootsJson;isOutput=true]$npmRootsJson"
Write-Host "Resolved npm roots JSON: $npmRootsJson"
