#requires -Version 7.2

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path

$DependencyScript = Join-Path $Root "scripts\Dependency-Graph.ps1"
$ConfigurationScript = Join-Path $Root "scripts\Configuration-Analyzer.ps1"

foreach ($requiredFile in @(
    $DependencyScript,
    $ConfigurationScript
)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required analyzer not found: $requiredFile"
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DEPENDENCY + CONFIGURATION TEST"
Write-Host "========================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# Syntax validation
# ---------------------------------------------------------

foreach ($target in @(
    $DependencyScript,
    $ConfigurationScript
)) {
    $tokens = $null
    $errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $target,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors.Count -gt 0) {
        Write-Host "SYNTAX FAILED: $target" -ForegroundColor Red

        foreach ($error in $errors) {
            Write-Host $error.Message -ForegroundColor Red
        }

        throw "PowerShell syntax validation failed."
    }
}

Write-Host "Analyzer syntax validation: PASS" -ForegroundColor Green

# ---------------------------------------------------------
# Temporary integration fixture
# ---------------------------------------------------------

$fixture = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("universal-doctor-fixture-" + [guid]::NewGuid().ToString("N"))

try {

    $reports = Join-Path $fixture "reports"

    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    New-Item -ItemType Directory -Path $reports -Force | Out-Null

    # Valid Node project
    $package = [ordered]@{
        name = "doctor-fixture"
        version = "1.0.0"
        dependencies = [ordered]@{
            lodash = "^4.17.21"
        }
        devDependencies = [ordered]@{
            vitest = "^3.0.0"
        }
    }

    $package |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath (Join-Path $fixture "package.json") `
            -Encoding utf8

    # Valid Python dependency manifest
    @(
        "requests>=2.32.0"
        "pydantic>=2.0.0"
    ) |
        Set-Content `
            -LiteralPath (Join-Path $fixture "requirements.txt") `
            -Encoding utf8

    # Invalid JSON for configuration analyzer
    "{ invalid json" |
        Set-Content `
            -LiteralPath (Join-Path $fixture "config.json") `
            -Encoding utf8

    # -----------------------------------------------------
    # Dependency Graph integration test
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "[TEST] Dependency Graph"

    & pwsh `
        -NoProfile `
        -File $DependencyScript `
        -Path $fixture `
        -OutputDirectory $reports

    $dependencyExitCode = $LASTEXITCODE

    if ($dependencyExitCode -ne 0) {
        throw "Dependency Graph failed with exit code $dependencyExitCode."
    }

    $dependencyReportPath = Join-Path `
        $reports `
        "dependency-graph.json"

    if (-not (Test-Path -LiteralPath $dependencyReportPath)) {
        throw "Dependency Graph report was not created."
    }

    $dependencyReport = Get-Content `
        -LiteralPath $dependencyReportPath `
        -Raw |
        ConvertFrom-Json

    if ([int]$dependencyReport.summary.manifests -lt 2) {
        throw "Dependency Graph detected fewer manifests than expected."
    }

    if ([int]$dependencyReport.summary.nodes -lt 3) {
        throw "Dependency Graph detected fewer nodes than expected."
    }

    if ([int]$dependencyReport.summary.edges -lt 2) {
        throw "Dependency Graph detected fewer edges than expected."
    }

    Write-Host "Dependency Graph integration: PASS" -ForegroundColor Green

    # -----------------------------------------------------
    # Configuration Analyzer integration test
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "[TEST] Configuration Analyzer"

    & pwsh `
        -NoProfile `
        -File $ConfigurationScript `
        -Path $fixture `
        -OutputDirectory $reports

    $configurationExitCode = $LASTEXITCODE

    # Invalid JSON is intentional, therefore exit code must be 1.
    if ($configurationExitCode -ne 1) {
        throw "Configuration Analyzer returned unexpected exit code: $configurationExitCode"
    }

    $configurationReportPath = Join-Path `
        $reports `
        "configuration-analysis.json"

    if (-not (Test-Path -LiteralPath $configurationReportPath)) {
        throw "Configuration Analyzer report was not created."
    }

    $configurationReport = Get-Content `
        -LiteralPath $configurationReportPath `
        -Raw |
        ConvertFrom-Json

    if ($configurationReport.status -ne "FAILED") {
        throw "Configuration Analyzer did not detect the intentional invalid JSON."
    }

    $configErrors = @(
        $configurationReport.findings |
            Where-Object {
                $_.id -eq "CFG-003"
            }
    )

    if ($configErrors.Count -eq 0) {
        throw "Expected CFG-003 was not detected."
    }

    Write-Host "Configuration Analyzer integration: PASS" -ForegroundColor Green

    # -----------------------------------------------------
    # Final
    # -----------------------------------------------------

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " ALL ANALYZER TESTS PASSED" -ForegroundColor Green
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
