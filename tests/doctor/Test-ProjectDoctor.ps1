Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path "\..\..").Path
$doctor = Join-Path $root "scripts\Project-Doctor.ps1"

if (-not (Test-Path $doctor)) {
    throw "Project Doctor script is missing."
}

$tokens = $null
$errors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    $doctor,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
    exit 1
}

Write-Host "Project Doctor syntax: PASS" -ForegroundColor Green

& $doctor -Path $root -Deep -Format All

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Project Doctor execution: PASS" -ForegroundColor Green
