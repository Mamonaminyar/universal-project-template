[CmdletBinding()]
param(
    [string]$Path = ".",
    [switch]$Deep
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "Project-Doctor.ps1") 
    -Path $Path 
    -Deep:$Deep 
    -FailOnWarning 
    -Format All

if ($LASTEXITCODE -ne 0) {
    Write-Host "QUALITY GATE: FAILED" -ForegroundColor Red
    exit 1
}

Write-Host "QUALITY GATE: PASSED" -ForegroundColor Green
exit 0
