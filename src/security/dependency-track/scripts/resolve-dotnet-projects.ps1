<#
.SYNOPSIS
    Resolves .NET project paths from multiline parameter.

.PARAMETER ProjectsMultiline
    Multiline string containing .NET project paths (one per line).

.OUTPUTS
    Sets pipeline variable 'dotnetProjectsJson' containing JSON array of resolved project paths.
#>
param(
    [string]$ProjectsMultiline = ''
)

$ErrorActionPreference = 'Stop'

Write-Host "##[group].NET projects"
$projPaths = $ProjectsMultiline -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }
$projPaths | ForEach-Object { Write-Host "Path: $_" }
Write-Host "##[endgroup]"

$projectsArray = @($projPaths)
$dotnetProjectsJson = $projectsArray | ConvertTo-Json -Compress
Write-Host "##vso[task.setvariable variable=dotnetProjectsJson;isOutput=true]$dotnetProjectsJson"
Write-Host "Resolved .NET projects JSON: $dotnetProjectsJson"
