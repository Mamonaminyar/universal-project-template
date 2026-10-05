#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Path = ".",
    [string]$OutputDirectory = ".doctor\reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path -LiteralPath $Path).Path
$Findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param(
        [string]$Id,
        [string]$Severity,
        [string]$Category,
        [string]$Message,
        [string]$Path = ".",
        [string]$Recommendation = ""
    )

    $Findings.Add([pscustomobject]@{
        id = $Id
        severity = $Severity
        category = $Category
        message = $Message
        path = $Path
        recommendation = $Recommendation
    })
}

# ---------------------------------------------------------
# Environment files
# ---------------------------------------------------------

$envFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @(
                ".env",
                ".env.local",
                ".env.production",
                ".env.development",
                ".env.test"
            )
        }
)

foreach ($file in $envFiles) {

    $relative = [System.IO.Path]::GetRelativePath(
        $Root,
        $file.FullName
    )

    Add-Finding `
        -Id "CFG-001" `
        -Severity "warning" `
        -Category "environment" `
        -Message "Environment configuration file detected." `
        -Path $relative `
        -Recommendation "Ensure this file is intentionally managed and never contains committed production secrets."
}

# ---------------------------------------------------------
# Sensitive configuration names
# ---------------------------------------------------------

$sensitiveNames = @(
    "credentials.json",
    "credentials.yml",
    "credentials.yaml",
    "secrets.json",
    "secrets.yml",
    "secrets.yaml",
    "private.json"
)

foreach ($name in $sensitiveNames) {

    $matches = @(
        Get-ChildItem `
            -LiteralPath $Root `
            -Filter $name `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue
    )

    foreach ($file in $matches) {

        $relative = [System.IO.Path]::GetRelativePath(
            $Root,
            $file.FullName
        )

        Add-Finding `
            -Id "CFG-002" `
            -Severity "warning" `
            -Category "sensitive-configuration" `
            -Message "Sensitive-looking configuration file detected." `
            -Path $relative `
            -Recommendation "Review whether this file belongs in source control."
    }
}

# ---------------------------------------------------------
# JSON configuration validation
# ---------------------------------------------------------

$jsonNames = @(
    "package.json",
    "tsconfig.json",
    "settings.json",
    "config.json"
)

$jsonFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $jsonNames -contains $_.Name
        }
)

foreach ($file in $jsonFiles) {

    $relative = [System.IO.Path]::GetRelativePath(
        $Root,
        $file.FullName
    )

    try {
        Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -ErrorAction Stop |
            Out-Null
    }
    catch {
        Add-Finding `
            -Id "CFG-003" `
            -Severity "error" `
            -Category "syntax" `
            -Message "JSON configuration file is invalid." `
            -Path $relative `
            -Recommendation "Correct the JSON syntax before build or release."
    }
}

# ---------------------------------------------------------
# Common secret patterns inside configuration
# ---------------------------------------------------------

$configFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension.ToLowerInvariant() -in @(
                ".json",".yaml",".yml",".toml",".ini",".conf",".config"
            )
        }
)

$secretPatterns = @(
    "api[_-]?key\s*[:=]"
    "password\s*[:=]"
    "client[_-]?secret\s*[:=]"
    "access[_-]?token\s*[:=]"
    "private[_-]?key\s*[:=]"
)

foreach ($file in $configFiles) {

    if ($file.Length -gt 10MB) {
        continue
    }

    try {
        $content = Get-Content `
            -LiteralPath $file.FullName `
            -Raw `
            -ErrorAction Stop
    }
    catch {
        continue
    }

    foreach ($pattern in $secretPatterns) {

        if ($content -match $pattern) {

            $relative = [System.IO.Path]::GetRelativePath(
                $Root,
                $file.FullName
            )

            Add-Finding `
                -Id "CFG-004" `
                -Severity "warning" `
                -Category "secrets" `
                -Message "Credential-like configuration key detected." `
                -Path $relative `
                -Recommendation "Verify the value is not a real secret and move credentials to secure secret management."

            break
        }
    }
}

# ---------------------------------------------------------
# Summary
# ---------------------------------------------------------

$errors = @(
    $Findings | Where-Object { $_.severity -eq "error" }
)

$warnings = @(
    $Findings | Where-Object { $_.severity -eq "warning" }
)

$status = if ($errors.Count -gt 0) {
    "FAILED"
}
else {
    "PASSED"
}

$Report = [pscustomobject]@{
    schemaVersion = "1.0"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    projectRoot = $Root
    status = $status
    summary = [pscustomobject]@{
        total = $Findings.Count
        errors = $errors.Count
        warnings = $warnings.Count
    }
    findings = @($Findings)
}

New-Item `
    -ItemType Directory `
    -Path $OutputDirectory `
    -Force |
    Out-Null

$jsonPath = Join-Path `
    $OutputDirectory `
    "configuration-analysis.json"

$Report |
    ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath $jsonPath -Encoding utf8

Write-Host ""
Write-Host "CONFIGURATION ANALYZER" -ForegroundColor Cyan
Write-Host "----------------------"
Write-Host "Findings : $($Findings.Count)"
Write-Host "Errors   : $($errors.Count)"
Write-Host "Warnings : $($warnings.Count)"
Write-Host "Status   : $status"
Write-Host "Report   : $jsonPath"
Write-Host ""

if ($status -eq "FAILED") {
    exit 1
}

exit 0
