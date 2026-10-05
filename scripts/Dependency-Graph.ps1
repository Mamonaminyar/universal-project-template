#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Path = ".",
    [string]$OutputDirectory = ".doctor\reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path -LiteralPath $Path).Path

$nodes = [System.Collections.Generic.List[object]]::new()
$edges = [System.Collections.Generic.List[object]]::new()
$manifests = [System.Collections.Generic.List[object]]::new()

function Add-Node {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Ecosystem,
        [string]$Version = "",
        [string]$Source = ""
    )

    $nodes.Add([pscustomobject]@{
        id = $Id
        name = $Name
        ecosystem = $Ecosystem
        version = $Version
        source = $Source
    })
}

function Add-Edge {
    param(
        [string]$From,
        [string]$To,
        [string]$Type = "depends-on"
    )

    $edges.Add([pscustomobject]@{
        from = $From
        to = $To
        type = $Type
    })
}

function Add-Manifest {
    param(
        [string]$Path,
        [string]$Ecosystem,
        [string]$Type
    )

    $manifests.Add([pscustomobject]@{
        path = $Path
        ecosystem = $Ecosystem
        type = $Type
    })
}

# ---------------------------------------------------------
# Node.js / package.json
# ---------------------------------------------------------

$packageFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Filter "package.json" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

foreach ($file in $packageFiles) {

    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName)

    Add-Manifest `
        -Path $relative `
        -Ecosystem "node" `
        -Type "package.json"

    try {
        $package = Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        continue
    }

    $projectId = "node:" + $relative

    Add-Node `
        -Id $projectId `
        -Name $package.name `
        -Ecosystem "node" `
        -Version $package.version `
        -Source $relative

    foreach ($section in @(
        "dependencies",
        "devDependencies",
        "peerDependencies",
        "optionalDependencies"
    )) {

        $sectionProperty = $package.PSObject.Properties[$section]

        if ($null -eq $sectionProperty) {
            continue
        }

        $sectionValue = $sectionProperty.Value

        if ($null -eq $sectionValue) {
            continue
        }

        foreach ($property in $sectionValue.PSObject.Properties) {

            $dependencyName = [string]$property.Name
            $dependencyVersion = [string]$property.Value
            $dependencyId = "node-package:$dependencyName"

            Add-Node `
                -Id $dependencyId `
                -Name $dependencyName `
                -Ecosystem "node-package" `
                -Version $dependencyVersion `
                -Source $relative

            Add-Edge `
                -From $projectId `
                -To $dependencyId `
                -Type $section
        }
    }
}

# ---------------------------------------------------------
# Python
# ---------------------------------------------------------

$requirementsFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Filter "requirements*.txt" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

foreach ($file in $requirementsFiles) {

    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName)

    Add-Manifest `
        -Path $relative `
        -Ecosystem "python" `
        -Type "requirements"

    $projectId = "python:" + $relative

    Add-Node `
        -Id $projectId `
        -Name $file.BaseName `
        -Ecosystem "python" `
        -Source $relative

    $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)

    foreach ($line in $lines) {

        $trimmed = $line.Trim()

        if (
            [string]::IsNullOrWhiteSpace($trimmed) -or
            $trimmed.StartsWith("#") -or
            $trimmed.StartsWith("-")
        ) {
            continue
        }

        if ($trimmed -match "^([A-Za-z0-9_.-]+)\s*([<>=!~].*)?$") {

            $dependencyName = $matches[1]
            $dependencyVersion = if ($matches[2]) { $matches[2].Trim() } else { "" }
            $dependencyId = "python-package:$dependencyName"

            Add-Node `
                -Id $dependencyId `
                -Name $dependencyName `
                -Ecosystem "python-package" `
                -Version $dependencyVersion `
                -Source $relative

            Add-Edge `
                -From $projectId `
                -To $dependencyId `
                -Type "requirements"
        }
    }
}

# ---------------------------------------------------------
# Go
# ---------------------------------------------------------

$goFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Filter "go.mod" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

foreach ($file in $goFiles) {

    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName)

    Add-Manifest `
        -Path $relative `
        -Ecosystem "go" `
        -Type "go.mod"

    $projectId = "go:" + $relative

    $moduleName = (
        Select-String `
            -LiteralPath $file.FullName `
            -Pattern "^\s*module\s+(.+)$" `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1
    )

    $name = if ($moduleName) {
        $moduleName.Matches[0].Groups[1].Value.Trim()
    }
    else {
        $file.Directory.Name
    }

    Add-Node `
        -Id $projectId `
        -Name $name `
        -Ecosystem "go" `
        -Source $relative

    $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)

    foreach ($line in $lines) {

        if ($line -match "^\s*([^\s]+)\s+v([0-9][^\s]+)") {

            $dependencyName = $matches[1]
            $dependencyVersion = $matches[2]
            $dependencyId = "go-module:$dependencyName"

            Add-Node `
                -Id $dependencyId `
                -Name $dependencyName `
                -Ecosystem "go-module" `
                -Version $dependencyVersion `
                -Source $relative

            Add-Edge `
                -From $projectId `
                -To $dependencyId `
                -Type "require"
        }
    }
}

# ---------------------------------------------------------
# Rust / Cargo.toml
# ---------------------------------------------------------

$cargoFiles = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Filter "Cargo.toml" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

foreach ($file in $cargoFiles) {

    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName)

    Add-Manifest `
        -Path $relative `
        -Ecosystem "rust" `
        -Type "Cargo.toml"

    $projectId = "rust:" + $relative

    Add-Node `
        -Id $projectId `
        -Name $file.Directory.Name `
        -Ecosystem "rust" `
        -Source $relative

    $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)

    $inDependencies = $false

    foreach ($line in $lines) {

        $trimmed = $line.Trim()

        if ($trimmed -match "^\[dependencies\]") {
            $inDependencies = $true
            continue
        }

        if ($trimmed -match "^\[.+\]") {
            $inDependencies = $false
            continue
        }

        if ($inDependencies -and $trimmed -match "^([A-Za-z0-9_-]+)\s*=") {

            $dependencyName = $matches[1]
            $dependencyId = "rust-crate:$dependencyName"

            Add-Node `
                -Id $dependencyId `
                -Name $dependencyName `
                -Ecosystem "rust-crate" `
                -Source $relative

            Add-Edge `
                -From $projectId `
                -To $dependencyId `
                -Type "dependencies"
        }
    }
}

# ---------------------------------------------------------
# Unique graph
# ---------------------------------------------------------

$uniqueNodes = @(
    $nodes |
        Group-Object id |
        ForEach-Object {
            $_.Group | Select-Object -First 1
        }
)

$uniqueEdges = @(
    $edges |
        Sort-Object from,to,type -Unique
)

$Report = [pscustomobject]@{
    schemaVersion = "1.0"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    projectRoot = $Root
    summary = [pscustomobject]@{
        manifests = $manifests.Count
        nodes = $uniqueNodes.Count
        edges = $uniqueEdges.Count
    }
    manifests = @($manifests)
    nodes = @($uniqueNodes)
    edges = @($uniqueEdges)
}

New-Item `
    -ItemType Directory `
    -Path $OutputDirectory `
    -Force |
    Out-Null

$jsonPath = Join-Path $OutputDirectory "dependency-graph.json"

$Report |
    ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath $jsonPath -Encoding utf8

Write-Host ""
Write-Host "DEPENDENCY GRAPH" -ForegroundColor Cyan
Write-Host "----------------"
Write-Host "Manifests : $($manifests.Count)"
Write-Host "Nodes     : $($uniqueNodes.Count)"
Write-Host "Edges     : $($uniqueEdges.Count)"
Write-Host "Report    : $jsonPath"
Write-Host ""

if ($uniqueNodes.Count -eq 0) {
    Write-Host "No supported dependency manifests detected." -ForegroundColor Yellow
}
else {
    Write-Host "Dependency discovery completed successfully." -ForegroundColor Green
}

