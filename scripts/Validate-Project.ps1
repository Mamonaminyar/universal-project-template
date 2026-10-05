[CmdletBinding()]
param(
    [string]$Path = ".",
    [switch]$Deep
)

& (Join-Path $PSScriptRoot "Project-Doctor.ps1") 
    -Path $Path 
    -Deep:$Deep 
    -Format All

exit $LASTEXITCODE
