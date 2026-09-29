#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Path = ".",
    [string]$Output = ".doctor\project-profile.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path -LiteralPath $Path).Path

function Test-Marker {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $match = @(Get-ChildItem `
            -LiteralPath $Root `
            -Filter $name `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1)

        if ($match.Count -gt 0) {
            return $true
        }
    }

    return $false
}

$languages = [System.Collections.Generic.List[string]]::new()
$frameworks = [System.Collections.Generic.List[string]]::new()
$packageManagers = [System.Collections.Generic.List[string]]::new()
$buildSystems = [System.Collections.Generic.List[string]]::new()
$testSystems = [System.Collections.Generic.List[string]]::new()

if (Test-Marker @("package.json","pnpm-lock.yaml","yarn.lock","package-lock.json")) {
    $languages.Add("JavaScript/TypeScript")
}

if (Test-Marker @("pyproject.toml","requirements.txt","Pipfile","poetry.lock")) {
    $languages.Add("Python")
}

if (Test-Marker @("pom.xml","build.gradle","build.gradle.kts")) {
    $languages.Add("Java")
}

if (Test-Marker @("go.mod")) {
    $languages.Add("Go")
}

if (Test-Marker @("Cargo.toml")) {
    $languages.Add("Rust")
}

if (Test-Marker @("*.csproj","*.fsproj","*.sln")) {
    $languages.Add(".NET")
}

if (Test-Marker @("pnpm-lock.yaml")) {
    $packageManagers.Add("pnpm")
}

if (Test-Marker @("yarn.lock")) {
    $packageManagers.Add("Yarn")
}

if (Test-Marker @("package-lock.json")) {
    $packageManagers.Add("npm")
}

if (Test-Marker @("poetry.lock")) {
    $packageManagers.Add("Poetry")
}

if (Test-Marker @("requirements.txt","pyproject.toml")) {
    $packageManagers.Add("pip")
}

if (Test-Marker @("pom.xml")) {
    $buildSystems.Add("Maven")
}

if (Test-Marker @("build.gradle","build.gradle.kts")) {
    $buildSystems.Add("Gradle")
}

if (Test-Marker @("go.mod")) {
    $buildSystems.Add("Go")
}

if (Test-Marker @("Cargo.toml")) {
    $buildSystems.Add("Cargo")
}

if (Test-Marker @("*.csproj","*.sln")) {
    $buildSystems.Add(".NET CLI")
}

if (Test-Marker @("jest.config.*","vitest.config.*","pytest.ini","tox.ini")) {
    $testSystems.Add("Detected test configuration")
}

$allFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

$projectType = "unknown"

if ((Test-Path (Join-Path $Root "apps")) -or
    (Test-Path (Join-Path $Root "services"))) {
    $projectType = "monorepo"
}
elseif ($languages.Count -eq 1) {
    $projectType = "single-stack"
}
elseif ($languages.Count -gt 1) {
    $projectType = "multi-stack"
}

$profile = "unknown"

if (Test-Path (Join-Path $Root "config\active-profile.yml")) {
    $profile = "configured"
}

$gitRepository = Test-Path (Join-Path $Root ".git")
$githubWorkflow = Test-Path (Join-Path $Root ".github\workflows")

$profileData = [ordered]@{
    schemaVersion = "1.0"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    root = $Root
    projectType = $projectType
    profile = $profile
    languages = @($languages | Select-Object -Unique)
    frameworks = @($frameworks | Select-Object -Unique)
    packageManagers = @($packageManagers | Select-Object -Unique)
    buildSystems = @($buildSystems | Select-Object -Unique)
    testSystems = @($testSystems | Select-Object -Unique)
    repository = [ordered]@{
        git = $gitRepository
        githubActions = $githubWorkflow
        fileCount = $allFiles.Count
    }
}

$parent = Split-Path -Parent $Output

New-Item -ItemType Directory -Path $parent -Force | Out-Null

$profileData |
    ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $Output -Encoding utf8

$profileData | ConvertTo-Json -Depth 20
