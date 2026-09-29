#requires -Version 7.2

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Engine = Join-Path $Root "scripts\Project-Health-Intelligence.ps1"

if (-not (Test-Path -LiteralPath $Engine)) {
    throw "Project Health Intelligence engine not found."
}

$tokens = $null
$syntaxErrors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    $Engine,
    [ref]$tokens,
    [ref]$syntaxErrors
) | Out-Null

if ($syntaxErrors.Count -gt 0) {
    foreach ($item in $syntaxErrors) {
        Write-Host $item.Message -ForegroundColor Red
    }

    throw "Project Health Intelligence syntax validation failed."
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " PROJECT HEALTH INTELLIGENCE TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Syntax validation: PASS" -ForegroundColor Green

$fixture = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("health-intelligence-" + [guid]::NewGuid().ToString("N"))

$reports = Join-Path $fixture ".doctor\reports"

try {

    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture "tests") -Force | Out-Null

    $package = [ordered]@{
        name = "health-intelligence-fixture"
        version = "1.0.0"
        scripts = [ordered]@{
            build = "echo build"
            test = "echo test"
            lint = "echo lint"
        }
    }

    $package |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath (Join-Path $fixture "package.json") `
            -Encoding utf8

    @(
        "PORT=8000"
        "MODE=test"
    ) |
        Set-Content `
            -LiteralPath (Join-Path $fixture "config\app.env.example") `
            -Encoding utf8

    "20.18.0" |
        Set-Content `
            -LiteralPath (Join-Path $fixture ".nvmrc") `
            -Encoding utf8

    "fixture tests" |
        Set-Content `
            -LiteralPath (Join-Path $fixture "tests\README.md") `
            -Encoding utf8

    # -----------------------------------------------------
    # BASELINE
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "[TEST] Baseline creation"

    & pwsh `
        -NoProfile `
        -File $Engine `
        -Path $fixture `
        -Mode All `
        -UpdateBaseline `
        -OutputDirectory $reports

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Baseline analysis failed with exit code $exitCode."
    }

    $baselinePath = Join-Path $fixture ".doctor\baseline.json"
    $jsonReport = Join-Path $reports "project-health-intelligence.json"
    $markdownReport = Join-Path $reports "project-health-intelligence.md"

    if (-not (Test-Path -LiteralPath $baselinePath)) {
        throw "Baseline file was not created: $baselinePath"
    }

    if (-not (Test-Path -LiteralPath $jsonReport)) {
        throw "JSON report was not created: $jsonReport"
    }

    if (-not (Test-Path -LiteralPath $markdownReport)) {
        throw "Markdown report was not created: $markdownReport"
    }

    Write-Host "Baseline creation: PASS" -ForegroundColor Green

    # -----------------------------------------------------
    # DRIFT
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "[TEST] Configuration drift"

    Add-Content `
        -LiteralPath (Join-Path $fixture "config\app.env.example") `
        -Value "FEATURE_X=true"

    & pwsh `
        -NoProfile `
        -File $Engine `
        -Path $fixture `
        -Mode Drift `
        -OutputDirectory $reports

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Drift analysis failed with exit code $exitCode."
    }

    if (-not (Test-Path -LiteralPath $jsonReport)) {
        throw "Drift JSON report does not exist: $jsonReport"
    }

    $driftData = (
        Get-Content `
            -LiteralPath $jsonReport `
            -Raw |
            ConvertFrom-Json
    )

    $driftFindings = @(
        $driftData.findings |
            Where-Object {
                $_.id -eq "DRIFT-004"
            }
    )

    if ($driftFindings.Count -eq 0) {
        throw "Expected DRIFT-004 was not detected."
    }

    Write-Host "Configuration drift: PASS" -ForegroundColor Green

    # -----------------------------------------------------
    # BUILD / TEST
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "[TEST] Build/Test Intelligence"

    & pwsh `
        -NoProfile `
        -File $Engine `
        -Path $fixture `
        -Mode BuildTest `
        -OutputDirectory $reports

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Build/Test analysis failed with exit code $exitCode."
    }

    if (-not (Test-Path -LiteralPath $jsonReport)) {
        throw "Build/Test JSON report does not exist: $jsonReport"
    }

    $buildData = (
        Get-Content `
            -LiteralPath $jsonReport `
            -Raw |
            ConvertFrom-Json
    )

    $buildResults = @(
        $buildData.results |
            Where-Object {
                $_.component -eq "Build/Test Intelligence"
            }
    )

    if ($buildResults.Count -eq 0) {
        throw "Build/Test Intelligence result was not generated."
    }

    Write-Host "Build/Test Intelligence: PASS" -ForegroundColor Green

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " ALL HEALTH INTELLIGENCE TESTS PASSED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}
finally {

    if (Test-Path -LiteralPath $fixture) {
        Remove-Item `
            -LiteralPath $fixture `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
