param(
    [Parameter(Mandatory = $true)]
    [string]$Tag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Tag -notmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(alpha|beta|rc)\.\d+)?$') {
    throw "Invalid release tag: $Tag"
}

git fetch --tags --force | Out-Null

$currentBranch = git branch --show-current
if ($currentBranch -ne "main") {
    throw "Release validation must run from main. Current branch: $currentBranch"
}

$status = git status --porcelain
if ($status) {
    throw "Working tree is not clean."
}

$tagExists = git tag --list $Tag
if ($tagExists) {
    throw "Release tag already exists: $Tag"
}

Write-Host "Release validation passed for $Tag"
