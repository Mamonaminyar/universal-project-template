#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Path = ".",
    [ValidateSet("Auto","Web","Api","Ai","Data","Mobile","Enterprise")]
    [string]$Profile = "Auto",
    [switch]$Deep,
    [switch]$FailOnWarning,
    [ValidateSet("Console","Json","Markdown","All")]
    [string]$Format = "All",
    [string]$OutputDirectory = ".doctor\reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath $Path).Path
$Timestamp = (Get-Date).ToUniversalTime().ToString("o")
$Findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param(
        [string]$Id,
        [ValidateSet("info","warning","error","critical")]
        [string]$Severity,
        [string]$Category,
        [string]$Message,
        [string]$RelativePath = ".",
        [string]$Rule = "",
        [string]$Recommendation = ""
    )

    $Findings.Add([pscustomobject]@{
        id             = $Id
        severity       = $Severity
        category       = $Category
        message        = $Message
        path           = $RelativePath
        rule           = $Rule
        recommendation = $Recommendation
        detectedAt     = $Timestamp
    })
}

function Test-Exists {
    param([string]$RelativePath)

    Test-Path -LiteralPath (Join-Path $ProjectRoot $RelativePath)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " UNIVERSAL PROJECT DOCTOR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Project : $ProjectRoot"
Write-Host "Profile : $Profile"
Write-Host "Deep    : $Deep"
Write-Host ""

# ---------------------------------------------------------
# STRUCTURE
# ---------------------------------------------------------

$requiredItems = @(
    "README.md"
    "LICENSE"
    "SECURITY.md"
    "CONTRIBUTING.md"
    "CHANGELOG.md"
    "config"
    "docs"
    "scripts"
    "tests"
    ".github"
)

foreach ($item in $requiredItems) {
    if (-not (Test-Exists $item)) {
        Add-Finding `
            -Id "STRUCT-001" `
            -Severity "error" `
            -Category "structure" `
            -Message "Required project item is missing: $item" `
            -RelativePath $item `
            -Rule "required-project-structure" `
            -Recommendation "Create or restore the required project item."
    }
}

# ---------------------------------------------------------
# GIT
# ---------------------------------------------------------

if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git")) {
    $gitStatus = @(git -C $ProjectRoot status --porcelain 2>$null)

    if ($LASTEXITCODE -ne 0) {
        Add-Finding `
            -Id "GIT-001" `
            -Severity "error" `
            -Category "git" `
            -Message "Git working tree could not be inspected." `
            -Rule "git-health" `
            -Recommendation "Repair the Git working tree."
    }
    elseif ($gitStatus.Count -gt 0) {
        Add-Finding `
            -Id "GIT-002" `
            -Severity "info" `
            -Category "git" `
            -Message "Working tree contains uncommitted changes." `
            -Rule "git-working-tree" `
            -Recommendation "Review the changes before commit or release."
    }
}
else {
    Add-Finding `
        -Id "GIT-003" `
        -Severity "warning" `
        -Category "git" `
        -Message "Project is not a Git repository." `
        -Rule "git-repository" `
        -Recommendation "Initialize Git for source control."
}

# ---------------------------------------------------------
# TECHNOLOGY DETECTION
# ---------------------------------------------------------

$detectedStacks = [System.Collections.Generic.List[string]]::new()

$markers = @(
    @{ Name = "Node.js"; Files = @("package.json","pnpm-lock.yaml","yarn.lock","package-lock.json") }
    @{ Name = "Python";  Files = @("pyproject.toml","requirements.txt","Pipfile","poetry.lock") }
    @{ Name = "Java";    Files = @("pom.xml","build.gradle","build.gradle.kts") }
    @{ Name = "Go";      Files = @("go.mod") }
    @{ Name = "Rust";    Files = @("Cargo.toml") }
    @{ Name = ".NET";    Files = @("*.csproj","*.fsproj","*.sln") }
)

foreach ($marker in $markers) {
    foreach ($markerFile in $marker.Files) {
        $match = @(Get-ChildItem `
            -LiteralPath $ProjectRoot `
            -Filter $markerFile `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1)

        if ($match.Count -gt 0) {
            $detectedStacks.Add($marker.Name)
            break
        }
    }
}

$detectedStacks = @($detectedStacks | Select-Object -Unique)

if ($detectedStacks.Count -eq 0) {
    Add-Finding `
        -Id "TECH-001" `
        -Severity "info" `
        -Category "technology" `
        -Message "No primary application technology was detected yet." `
        -Rule "technology-detection" `
        -Recommendation "Add the appropriate project manifest when implementation begins."
}
else {
    Add-Finding `
        -Id "TECH-INFO-001" `
        -Severity "info" `
        -Category "technology" `
        -Message ("Detected stacks: " + ($detectedStacks -join ", ")) `
        -Rule "technology-detection"
}

# ---------------------------------------------------------
# SECURITY
# ---------------------------------------------------------

$secretPatterns = @(
    "AKIA[0-9A-Z]{16}"
    "-----BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----"
    "api[_-]?key\s*[:=]\s*['""]?[A-Za-z0-9_\-]{16,}"
    "password\s*[:=]\s*['""][^'""]{4,}['""]"
    "secret\s*[:=]\s*['""][^'""]{4,}['""]"
)

$excludedDirectories = @(
    ".git"
    "node_modules"
    ".doctor"
    ".turbo"
    ".snapshots"
    "dist"
    "build"
    "coverage"
)

$allFiles = @(
    Get-ChildItem `
        -LiteralPath $ProjectRoot `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)

foreach ($file in $allFiles) {

    if ($file.Length -gt 10MB) {
        continue
    }

    $relative = [System.IO.Path]::GetRelativePath(
        $ProjectRoot,
        $file.FullName
    )

    $parts = @($relative -split '[\\/]')

    $excludedMatch = @(
        $parts | Where-Object {
            $excludedDirectories -contains $_
        }
    )

    if ($excludedMatch.Count -gt 0) {
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
            Add-Finding `
                -Id "SEC-001" `
                -Severity "critical" `
                -Category "security" `
                -Message "Potential credential or secret pattern detected." `
                -RelativePath $relative `
                -Rule "secret-pattern-detection" `
                -Recommendation "Remove the credential, rotate it if real, and use secure secret storage."

            break
        }
    }
}

# ---------------------------------------------------------
# SENSITIVE FILE DETECTION
# ---------------------------------------------------------

$sensitiveNames = @(
    ".env"
    ".env.local"
    ".env.production"
    "id_rsa"
    "id_ed25519"
)

foreach ($sensitiveName in $sensitiveNames) {

    $sensitiveMatches = @(
        Get-ChildItem `
            -LiteralPath $ProjectRoot `
            -Filter $sensitiveName `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue
    )

    foreach ($match in $sensitiveMatches) {
        $relative = [System.IO.Path]::GetRelativePath(
            $ProjectRoot,
            $match.FullName
        )

        Add-Finding `
            -Id "SEC-002" `
            -Severity "warning" `
            -Category "security" `
            -Message "Sensitive-looking file detected: $sensitiveName" `
            -RelativePath $relative `
            -Rule "sensitive-file-detection" `
            -Recommendation "Verify the file is ignored and contains no production credentials."
    }
}

# ---------------------------------------------------------
# DOCUMENTATION
# ---------------------------------------------------------

$documentationFiles = @(
    "README.md"
    "SECURITY.md"
    "CONTRIBUTING.md"
    "CHANGELOG.md"
)

foreach ($documentationFile in $documentationFiles) {

    if (-not (Test-Exists $documentationFile)) {
        continue
    }

    $fullPath = Join-Path $ProjectRoot $documentationFile

    $content = Get-Content `
        -LiteralPath $fullPath `
        -Raw `
        -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($content)) {
        Add-Finding `
            -Id "DOC-001" `
            -Severity "warning" `
            -Category "documentation" `
            -Message "Documentation file exists but is empty." `
            -RelativePath $documentationFile `
            -Rule "non-empty-documentation" `
            -Recommendation "Populate the document with project-specific information."
    }
}

# ---------------------------------------------------------
# DEEP SCAN
# ---------------------------------------------------------

if ($Deep) {

    $largeFiles = @(
        $allFiles | Where-Object {
            $_.Length -gt 10MB
        }
    )

    Add-Finding `
        -Id "DEEP-001" `
        -Severity "info" `
        -Category "deep-scan" `
        -Message "Deep scan completed. Files scanned: $($allFiles.Count); files above 10 MB: $($largeFiles.Count)." `
        -Rule "deep-file-inventory"

    $binaryExtensions = @(
        ".exe"
        ".dll"
        ".bin"
        ".iso"
        ".zip"
        ".7z"
        ".rar"
        ".png"
        ".jpg"
        ".jpeg"
        ".gif"
        ".webp"
        ".mp4"
        ".mov"
    )

    $binaryFiles = @(
        $allFiles | Where-Object {
            $binaryExtensions -contains $_.Extension.ToLowerInvariant()
        }
    )

    if ($binaryFiles.Count -gt 0) {
        Add-Finding `
            -Id "DEEP-002" `
            -Severity "warning" `
            -Category "repository-hygiene" `
            -Message "Potential binary artifacts detected: $($binaryFiles.Count)." `
            -Rule "binary-artifact-detection" `
            -Recommendation "Keep generated binaries out of source control unless explicitly required."
    }
}

# ---------------------------------------------------------
# RESULT
# ---------------------------------------------------------

$errorFindings = @(
    $Findings | Where-Object {
        $_.severity -in @("error","critical")
    }
)

$warningFindings = @(
    $Findings | Where-Object {
        $_.severity -eq "warning"
    }
)

$infoFindings = @(
    $Findings | Where-Object {
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

# ---------------------------------------------------------
# REPORT
# ---------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $OutputDirectory `
    -Force |
    Out-Null

$Report = [pscustomobject]@{
    schemaVersion = "1.0"
    doctorVersion = "1.0.0"
    timestampUtc  = $Timestamp
    projectRoot   = $ProjectRoot
    profile       = $Profile
    deepScan      = [bool]$Deep
    status        = $Status
    summary       = [pscustomobject]@{
        total    = $Findings.Count
        errors   = $errorFindings.Count
        warnings = $warningFindings.Count
        info     = $infoFindings.Count
    }
    findings = @($Findings)
}

if ($Format -in @("Json","All")) {
    $jsonPath = Join-Path $OutputDirectory "project-doctor.json"

    $Report |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -LiteralPath $jsonPath `
            -Encoding utf8
}

if ($Format -in @("Markdown","All")) {

    $markdownPath = Join-Path $OutputDirectory "project-doctor.md"

    $markdown = [System.Collections.Generic.List[string]]::new()

    $markdown.Add("# Universal Project Doctor Report")
    $markdown.Add("")
    $markdown.Add("Status: **$Status**")
    $markdown.Add("Project: ``$ProjectRoot``")
    $markdown.Add("Profile: **$Profile**")
    $markdown.Add("Deep Scan: **$Deep**")
    $markdown.Add("Timestamp UTC: $Timestamp")
    $markdown.Add("")
    $markdown.Add("## Summary")
    $markdown.Add("")
    $markdown.Add("- Total: $($Findings.Count)")
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

    Set-Content `
        -LiteralPath $markdownPath `
        -Value $markdown `
        -Encoding utf8
}

# ---------------------------------------------------------
# CONSOLE
# ---------------------------------------------------------

if ($Format -in @("Console","All")) {

    foreach ($finding in $Findings) {

        $prefix = switch ($finding.severity) {
            "critical" { "[CRITICAL]" }
            "error"    { "[ERROR]   " }
            "warning"  { "[WARNING] " }
            default    { "[INFO]    " }
        }

        Write-Host "$prefix $($finding.id) - $($finding.message)"
    }

    Write-Host ""
    Write-Host "----------------------------------------"
    Write-Host "Status       : $Status"
    Write-Host "Total        : $($Findings.Count)"
    Write-Host "Errors       : $($errorFindings.Count)"
    Write-Host "Warnings     : $($warningFindings.Count)"
    Write-Host "Information  : $($infoFindings.Count)"
    Write-Host "----------------------------------------"
}

if ($Status -eq "FAILED") {
    exit 1
}

exit 0
