# Project Health Intelligence

Project Health Intelligence extends Universal Project Doctor with three higher-level diagnostic capabilities.

## Configuration Drift

The engine can create a configuration baseline and compare future scans against it.

Create or refresh a baseline:

```powershell
pwsh .\scripts\Project-Health-Intelligence.ps1 -Mode Drift -UpdateBaseline
-Encoding utf8
