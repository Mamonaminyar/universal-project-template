[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$')]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('web','api','ai','data','mobile','enterprise')]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [switch]$InitializeGit,

    [switch]$Force,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[BOOTSTRAP] $Message"
}

$templateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceProfile = Join-Path $templateRoot "config\profiles\$Profile.yml"

if (-not (Test-Path -LiteralPath $sourceProfile -PathType Leaf)) {
    throw "Profile not found: $Profile"
}

$targetRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $Destination $ProjectName)
)

$sourceFull = [System.IO.Path]::GetFullPath($templateRoot)

if ($targetRoot.TrimEnd('\') -eq $sourceFull.TrimEnd('\')) {
    throw "Destination cannot be the template repository itself."
}

if ((Test-Path -LiteralPath $targetRoot) -and -not $Force) {
    $items = @(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction SilentlyContinue)

    if ($items.Count -gt 0) {
        throw "Destination already exists and is not empty: $targetRoot. Use -Force only when intentional."
    }
}

if ($DryRun) {
    Write-Step "Dry run"
    Write-Step "Project: $ProjectName"
    Write-Step "Profile: $Profile"
    Write-Step "Destination: $targetRoot"
    Write-Step "Git initialization: $InitializeGit"
    exit 0
}

Write-Step "Creating project directory..."
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

Write-Step "Copying universal template..."
$excluded = @(
    '.git',
    '.snapshots',
    '.turbo',
    'node_modules'
)

Get-ChildItem -LiteralPath $templateRoot -Force |
    Where-Object { $excluded -notcontains $_.Name } |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName `
            -Destination (Join-Path $targetRoot $_.Name) `
            -Recurse `
            -Force
    }

Write-Step "Creating project metadata..."

$projectConfig = @"
project:
  name: $ProjectName
  profile: $Profile
  template: universal-project-template
  initialized_at: $([DateTime]::UtcNow.ToString('o'))

engineering:
  production_ready: true
  secure_by_default: true
  modular: true
  observable: true
  testable: true
  documented: true

lifecycle:
  stage: initialized
"@

$configDir = Join-Path $targetRoot "config"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$projectConfig | Set-Content `
    -LiteralPath (Join-Path $configDir "project.yml") `
    -Encoding utf8

$activeProfile = Join-Path $configDir "active-profile.yml"

Copy-Item `
    -LiteralPath $sourceProfile `
    -Destination $activeProfile `
    -Force

if ($InitializeGit) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not installed or is not available on PATH."
    }

    Push-Location $targetRoot
    try {
        Write-Step "Initializing Git repository..."
        git init

        git add .

        git commit -s -m "chore: initialize project from universal template"
    }
    finally {
        Pop-Location
    }
}

Write-Step "Bootstrap completed successfully."
Write-Host ""
Write-Host "Project : $ProjectName"
Write-Host "Profile : $Profile"
Write-Host "Path    : $targetRoot"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Review config/project.yml"
Write-Host "  2. Review config/active-profile.yml"
Write-Host "  3. Configure project-specific dependencies"
Write-Host "  4. Configure remote repository"
