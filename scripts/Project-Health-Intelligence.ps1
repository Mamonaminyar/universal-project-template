#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Path = ".",

    [ValidateSet("Drift","Environment","BuildTest","All")]
    [string]$Mode = "All",

    [string]$BaselinePath = ".doctor\baseline.json",

    [string]$OutputDirectory = ".doctor\reports",

    [switch]$UpdateBaseline,

    [switch]$FailOnWarning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path -LiteralPath $Path).Path

# Always resolve relative paths against the project root.
if ([System.IO.Path]::IsPathRooted($BaselinePath)) {
    $ResolvedBaselinePath = [System.IO.Path]::GetFullPath($BaselinePath)
}
else {
    $ResolvedBaselinePath = [System.IO.Path]::GetFullPath(
        (Join-Path $Root $BaselinePath)
    )
}

if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $ResolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
}
else {
    $ResolvedOutputDirectory = [System.IO.Path]::GetFullPath(
        (Join-Path $Root $OutputDirectory)
    )
}

$Findings = [System.Collections.Generic.List[object]]::new()
$Results = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param(
        [string]$Id,
        [ValidateSet("info","warning","error","critical")]
        [string]$Severity,
        [string]$Category,
        [string]$Message,
        [string]$RelativePath = ".",
        [string]$Recommendation = ""
    )

    $Findings.Add([pscustomobject]@{
        id = $Id
        severity = $Severity
        category = $Category
        message = $Message
        path = $RelativePath
        recommendation = $Recommendation
    })
}

function Add-Result {
    param(
        [string]$Component,
        [string]$Status,
        [hashtable]$Data = @{}
    )

    $Results.Add([pscustomobject]@{
        component = $Component
        status = $Status
        data = $Data
    })
}

function Get-RelativePathSafe {
    param(
        [string]$FullPath
    )

    try {
        return [System.IO.Path]::GetRelativePath($Root, $FullPath)
    }
    catch {
        return $FullPath
    }
}

function Test-Exists {
    param(
        [string]$RelativePath
    )

    return Test-Path -LiteralPath (Join-Path $Root $RelativePath)
}

function Get-ConfigurationFiles {

    $files = @(
        Get-ChildItem `
            -LiteralPath $Root `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue
    )

    $excludedDirectories = @(
        ".git"
        ".doctor"
        "node_modules"
        "dist"
        "build"
        "coverage"
        ".turbo"
        ".snapshots"
    )

    $configurationNames = @(
        "package.json"
        "tsconfig.json"
        "pyproject.toml"
        "requirements.txt"
        "requirements-dev.txt"
        "go.mod"
        "Cargo.toml"
        "global.json"
        ".nvmrc"
        ".python-version"
        ".tool-versions"
        ".editorconfig"
        ".gitattributes"
        ".gitignore"
        "Dockerfile"
        "docker-compose.yml"
        "docker-compose.yaml"
    )

    $selected = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $files) {

        $relative = Get-RelativePathSafe $file.FullName
        $parts = @($relative -split '[\\/]')

        $excluded = @(
            $parts | Where-Object {
                $excludedDirectories -contains $_
            }
        )

        if ($excluded.Count -gt 0) {
            continue
        }

        $isConfigDirectory = $parts -contains "config"
        $isGithubConfiguration = $parts -contains ".github"

        if (
            $isConfigDirectory -or
            $isGithubConfiguration -or
            ($configurationNames -contains $file.Name) -or
            ($file.Name -like "tsconfig*.json") -or
            ($file.Name -like "rust-toolchain*")
        ) {
            $selected.Add($file)
        }
    }

    return @($selected)
}

function Get-FileFingerprint {
    param(
        [System.IO.FileInfo]$File
    )

    $relative = Get-RelativePathSafe $File.FullName

    $hash = Get-FileHash `
        -LiteralPath $File.FullName `
        -Algorithm SHA256

    return [pscustomobject]@{
        path = $relative
        hash = $hash.Hash
        length = $File.Length
    }
}

function Get-Baseline {

    if (-not (Test-Path -LiteralPath $ResolvedBaselinePath)) {
        return $null
    }

    try {
        return (
            Get-Content `
                -LiteralPath $ResolvedBaselinePath `
                -Raw |
                ConvertFrom-Json `
                -ErrorAction Stop
        )
    }
    catch {
        Add-Finding `
            -Id "DRIFT-001" `
            -Severity "error" `
            -Category "drift" `
            -Message "Configuration baseline is invalid JSON." `
            -RelativePath $BaselinePath `
            -Recommendation "Regenerate the baseline with -UpdateBaseline."

        return $null
    }
}

function Update-ConfigurationBaseline {

    $configurationFiles = @(Get-ConfigurationFiles)

    $fingerprints = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $configurationFiles) {

        try {
            $fingerprints.Add(
                (Get-FileFingerprint $file)
            )
        }
        catch {
            Add-Finding `
                -Id "DRIFT-002" `
                -Severity "warning" `
                -Category "drift" `
                -Message "Unable to fingerprint configuration file." `
                -RelativePath (Get-RelativePathSafe $file.FullName) `
                -Recommendation "Verify that the file remains readable."
        }
    }

    $baseline = [ordered]@{
        schemaVersion = "1.0"
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        projectRoot = $Root
        files = @($fingerprints)
    }

    $baselineParent = Split-Path -Parent $ResolvedBaselinePath

    if (-not [string]::IsNullOrWhiteSpace($baselineParent)) {
        New-Item `
            -ItemType Directory `
            -Path $baselineParent `
            -Force |
            Out-Null
    }

    $baseline |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath $ResolvedBaselinePath `
            -Encoding utf8

    Add-Result `
        -Component "Configuration Drift" `
        -Status "BASELINE_UPDATED" `
        -Data @{
            fileCount = $fingerprints.Count
            baseline = $ResolvedBaselinePath
        }
}

function Invoke-ConfigurationDrift {

    if ($UpdateBaseline) {
        Update-ConfigurationBaseline
        return
    }

    $baseline = Get-Baseline

    if ($null -eq $baseline) {

        Add-Finding `
            -Id "DRIFT-000" `
            -Severity "info" `
            -Category "drift" `
            -Message "No configuration baseline exists yet." `
            -RelativePath $BaselinePath `
            -Recommendation "Run with -UpdateBaseline before drift monitoring."

        Add-Result `
            -Component "Configuration Drift" `
            -Status "BASELINE_REQUIRED"

        return
    }

    $baselineFiles = @($baseline.files)

    $currentFiles = @(
        Get-ConfigurationFiles |
            ForEach-Object {
                Get-FileFingerprint $_
            }
    )

    $baselineMap = @{}
    $currentMap = @{}

    foreach ($item in $baselineFiles) {
        $baselineMap[[string]$item.path] = $item
    }

    foreach ($item in $currentFiles) {
        $currentMap[[string]$item.path] = $item
    }

    foreach ($path in @($baselineMap.Keys)) {

        if (-not $currentMap.ContainsKey($path)) {

            Add-Finding `
                -Id "DRIFT-003" `
                -Severity "error" `
                -Category "drift" `
                -Message "Baseline configuration file is missing." `
                -RelativePath $path `
                -Recommendation "Restore the file or intentionally regenerate the baseline."

            continue
        }

        if ($baselineMap[$path].hash -ne $currentMap[$path].hash) {

            Add-Finding `
                -Id "DRIFT-004" `
                -Severity "warning" `
                -Category "drift" `
                -Message "Configuration file changed since the baseline." `
                -RelativePath $path `
                -Recommendation "Review the change and update the baseline when approved."
        }
    }

    foreach ($path in @($currentMap.Keys)) {

        if (-not $baselineMap.ContainsKey($path)) {

            Add-Finding `
                -Id "DRIFT-005" `
                -Severity "warning" `
                -Category "drift" `
                -Message "New configuration file detected after the baseline." `
                -RelativePath $path `
                -Recommendation "Review the new configuration and update the baseline when approved."
        }
    }

    Add-Result `
        -Component "Configuration Drift" `
        -Status "ANALYZED" `
        -Data @{
            baselineFiles = $baselineFiles.Count
            currentFiles = $currentFiles.Count
        }
}

function Get-CommandVersion {
    param(
        [string]$CommandName
    )

    $command = Get-Command `
        -Name $CommandName `
        -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        return [pscustomobject]@{
            name = $CommandName
            available = $false
            version = $null
        }
    }

    try {
        $output = @(
            & $command.Source --version 2>&1
        )

        $versionText = (
            $output |
            ForEach-Object {
                [string]$_
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            Select-Object -First 1
        )

        return [pscustomobject]@{
            name = $CommandName
            available = $true
            version = $versionText
        }
    }
    catch {
        return [pscustomobject]@{
            name = $CommandName
            available = $true
            version = "version-check-failed"
        }
    }
}

function Invoke-EnvironmentAnalysis {

    $tools = [System.Collections.Generic.List[object]]::new()

    foreach ($toolName in @(
        "git"
        "pwsh"
        "node"
        "npm"
        "pnpm"
        "yarn"
        "python"
        "java"
        "go"
        "cargo"
        "dotnet"
        "docker"
    )) {
        $tools.Add(
            (Get-CommandVersion -CommandName $toolName)
        )
    }

    $requirements = [System.Collections.Generic.List[string]]::new()

    if (
        (Test-Exists "package.json") -or
        (Test-Exists "pnpm-lock.yaml") -or
        (Test-Exists "yarn.lock") -or
        (Test-Exists "package-lock.json")
    ) {
        $requirements.Add("node")
    }

    if (
        (Test-Exists "pyproject.toml") -or
        (Test-Exists "requirements.txt") -or
        (Test-Exists "Pipfile")
    ) {
        $requirements.Add("python")
    }

    if (
        (Test-Exists "pom.xml") -or
        (Test-Exists "build.gradle") -or
        (Test-Exists "build.gradle.kts")
    ) {
        $requirements.Add("java")
    }

    if (Test-Exists "go.mod") {
        $requirements.Add("go")
    }

    if (Test-Exists "Cargo.toml") {
        $requirements.Add("cargo")
    }

    $uniqueRequirements = @(
        $requirements | Select-Object -Unique
    )

    foreach ($requiredTool in $uniqueRequirements) {

        $tool = @(
            $tools |
            Where-Object {
                $_.name -eq $requiredTool
            }
        ) |
        Select-Object -First 1

        if ($null -eq $tool -or -not $tool.available) {

            Add-Finding `
                -Id "ENV-001" `
                -Severity "warning" `
                -Category "environment" `
                -Message "Required development tool is not available: $requiredTool" `
                -Recommendation "Install or configure the required runtime/toolchain."
        }
    }

    Add-Result `
        -Component "Environment Analyzer" `
        -Status "ANALYZED" `
        -Data @{
            requiredTools = $uniqueRequirements
            tools = @($tools)
        }
}

function Get-PackageScripts {

    $packagePath = Join-Path $Root "package.json"

    if (-not (Test-Path -LiteralPath $packagePath)) {
        return @()
    }

    try {
        $package = (
            Get-Content `
                -LiteralPath $packagePath `
                -Raw |
                ConvertFrom-Json `
                -ErrorAction Stop
        )
    }
    catch {
        Add-Finding `
            -Id "BUILD-001" `
            -Severity "error" `
            -Category "build-test" `
            -Message "package.json could not be parsed." `
            -RelativePath "package.json" `
            -Recommendation "Fix package.json before running Node.js automation."

        return @()
    }

    $scriptsProperty = $package.PSObject.Properties["scripts"]

    if ($null -eq $scriptsProperty) {
        return @()
    }

    if ($null -eq $scriptsProperty.Value) {
        return @()
    }

    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($property in $scriptsProperty.Value.PSObject.Properties) {

        $result.Add(
            [pscustomobject]@{
                name = [string]$property.Name
                command = [string]$property.Value
            }
        )
    }

    return @($result)
}

function Invoke-BuildTestAnalysis {

    $buildIndicators = [System.Collections.Generic.List[string]]::new()
    $testIndicators = [System.Collections.Generic.List[string]]::new()

    $packageScripts = @(Get-PackageScripts)

    foreach ($script in $packageScripts) {

        switch -Regex ($script.name) {
            "^build$" {
                $buildIndicators.Add("npm-script:build")
            }
            "^test$" {
                $testIndicators.Add("npm-script:test")
            }
            "^lint$" {
                $testIndicators.Add("npm-script:lint")
            }
            "^(type-check|typecheck)$" {
                $testIndicators.Add("npm-script:typecheck")
            }
        }
    }

    if (
        (Test-Exists "pyproject.toml") -or
        (Test-Exists "requirements.txt")
    ) {

        if (Test-Exists "tests") {
            $testIndicators.Add("python-tests-directory")
        }
    }

    if (Test-Exists "go.mod") {
        $buildIndicators.Add("go-build")
        $testIndicators.Add("go-test")
    }

    if (Test-Exists "Cargo.toml") {
        $buildIndicators.Add("cargo-check")
        $buildIndicators.Add("cargo-build")
        $testIndicators.Add("cargo-test")
    }

    if (
        (Test-Exists "pom.xml") -or
        (Test-Exists "build.gradle") -or
        (Test-Exists "build.gradle.kts")
    ) {
        $buildIndicators.Add("java-build")
        $testIndicators.Add("java-test")
    }

    $dotnetFiles = @(
        Get-ChildItem `
            -LiteralPath $Root `
            -Filter "*.csproj" `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue
    )

    if ($dotnetFiles.Count -gt 0) {
        $buildIndicators.Add("dotnet-build")
        $testIndicators.Add("dotnet-test")
    }

    if (Test-Exists ".github\workflows") {
        $testIndicators.Add("github-actions")
    }

    Add-Result `
        -Component "Build/Test Intelligence" `
        -Status "ANALYZED" `
        -Data @{
            buildIndicators = @(
                $buildIndicators | Select-Object -Unique
            )
            testIndicators = @(
                $testIndicators | Select-Object -Unique
            )
            packageScripts = $packageScripts
        }
}

if ($Mode -in @("Drift","All")) {
    Invoke-ConfigurationDrift
}

if ($Mode -in @("Environment","All")) {
    Invoke-EnvironmentAnalysis
}

if ($Mode -in @("BuildTest","All")) {
    Invoke-BuildTestAnalysis
}

$errorFindings = @(
    $Findings |
        Where-Object {
            $_.severity -in @("error","critical")
        }
)

$warningFindings = @(
    $Findings |
        Where-Object {
            $_.severity -eq "warning"
        }
)

$infoFindings = @(
    $Findings |
        Where-Object {
            $_.severity -eq "info"
        }
)

if ($errorFindings.Count -gt 0) {
    $Status = "FAILED"
}
elseif ($FailOnWarning -and $warningFindings.Count -gt 0) {
    $Status = "FAILED"
}
else {
    $Status = "PASSED"
}

New-Item `
    -ItemType Directory `
    -Path $ResolvedOutputDirectory `
    -Force |
    Out-Null

$Report = [ordered]@{
    schemaVersion = "1.0"
    engineVersion = "1.0.1"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    projectRoot = $Root
    mode = $Mode
    status = $Status
    summary = [ordered]@{
        total = $Findings.Count
        errors = $errorFindings.Count
        warnings = $warningFindings.Count
        info = $infoFindings.Count
    }
    results = @($Results)
    findings = @($Findings)
}

$jsonPath = Join-Path `
    $ResolvedOutputDirectory `
    "project-health-intelligence.json"

$markdownPath = Join-Path `
    $ResolvedOutputDirectory `
    "project-health-intelligence.md"

$Report |
    ConvertTo-Json -Depth 30 |
    Set-Content `
        -LiteralPath $jsonPath `
        -Encoding utf8

$markdown = [System.Collections.Generic.List[string]]::new()

$markdown.Add("# Project Health Intelligence")
$markdown.Add("")
$markdown.Add("Status: **$Status**")
$markdown.Add("Mode: **$Mode**")
$markdown.Add("Project: $Root")
$markdown.Add("Generated: $($Report.generatedAt)")
$markdown.Add("")
$markdown.Add("## Summary")
$markdown.Add("")
$markdown.Add("- Total findings: $($Findings.Count)")
$markdown.Add("- Errors/Critical: $($errorFindings.Count)")
$markdown.Add("- Warnings: $($warningFindings.Count)")
$markdown.Add("- Info: $($infoFindings.Count)")
$markdown.Add("")

foreach ($finding in $Findings) {
    $markdown.Add("### [$($finding.severity)] $($finding.id)")
    $markdown.Add("")
    $markdown.Add("- Category: $($finding.category)")
    $markdown.Add("- Path: $($finding.path)")
    $markdown.Add("- Message: $($finding.message)")
    $markdown.Add("- Recommendation: $($finding.recommendation)")
    $markdown.Add("")
}

$markdown |
    Set-Content `
        -LiteralPath $markdownPath `
        -Encoding utf8

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " PROJECT HEALTH INTELLIGENCE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Project    : $Root"
Write-Host "Mode       : $Mode"
Write-Host "Status     : $Status"
Write-Host "Findings   : $($Findings.Count)"
Write-Host "Errors     : $($errorFindings.Count)"
Write-Host "Warnings   : $($warningFindings.Count)"
Write-Host "Info       : $($infoFindings.Count)"
Write-Host "JSON       : $jsonPath"
Write-Host "Markdown   : $markdownPath"
Write-Host "========================================" -ForegroundColor Cyan

if ($Status -eq "FAILED") {
    exit 1
}

exit 0
