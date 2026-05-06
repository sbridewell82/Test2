# Imports git repositories from a zip file into a GitLab instance.
#
# Usage:
#   $env:GITLAB_TOKEN = "your_token"
#   .\import_repos.ps1 -ZipFile repos.zip -GitLabUrl https://gitlab.example.com -Namespace mygroup
#
# The zip is expected to contain one directory per repository, each with a .git
# folder (regular clones) or a bare repo (HEAD, objects/, refs/ at root).
#
# Requires: git, unzip/Expand-Archive (built-in), PowerShell 5.1+

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ZipFile,
    [Parameter(Mandatory)][string]$GitLabUrl,
    [Parameter(Mandatory)][string]$Namespace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── helpers ──────────────────────────────────────────────────────────────────

function Log  { param([string]$msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }
function Ok   { param([string]$msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] v $msg" -ForegroundColor Green }
function Warn { param([string]$msg) Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] $msg" }
function Fail { param([string]$msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] x $msg" -ForegroundColor Red }

function Invoke-GitLabApi {
    param(
        [string]$Method,
        [string]$ApiPath,
        [hashtable]$Body = @{}
    )

    $uri = "$($GitLabUrl.TrimEnd('/'))/api/v4$ApiPath"
    $headers = @{ 'PRIVATE-TOKEN' = $Token }
    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $headers
    }

    if ($Body.Count -gt 0) {
        $params['Body']        = ($Body | ConvertTo-Json -Depth 5)
        $params['ContentType'] = 'application/json'
    }

    Invoke-RestMethod @params
}

function Resolve-NamespaceId {
    param([string]$Ns)

    # Try group first
    try {
        $encoded = [Uri]::EscapeDataString($Ns)
        $group = Invoke-GitLabApi -Method GET -ApiPath "/groups/$encoded"
        if ($group.id) { return $group.id }
    } catch { }

    # Fall back to user namespace
    try {
        $users = Invoke-GitLabApi -Method GET -ApiPath "/users?username=$([Uri]::EscapeDataString($Ns))"
        if ($users.Count -gt 0) { return $users[0].namespace_id }
    } catch { }

    return $null
}

function New-GitLabProject {
    param([string]$Name, [int]$NamespaceId)

    Invoke-GitLabApi -Method POST -ApiPath '/projects' -Body @{
        name             = $Name
        namespace_id     = $NamespaceId
        visibility       = 'private'
        initialize_with_readme = $false
    }
}

# ── validation ───────────────────────────────────────────────────────────────

$Token = $env:GITLAB_TOKEN
if (-not $Token) {
    Write-Error 'GITLAB_TOKEN environment variable is not set.'
    exit 1
}

if (-not (Test-Path $ZipFile)) {
    Write-Error "Zip file not found: $ZipFile"
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'git is required but was not found in PATH.'
    exit 1
}

# ── main logic ───────────────────────────────────────────────────────────────

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "import_repos_$(Get-Random)"
New-Item -ItemType Directory -Path $WorkDir | Out-Null

try {
    Log "Extracting $ZipFile ..."
    Expand-Archive -Path $ZipFile -DestinationPath (Join-Path $WorkDir 'extracted') -Force

    Log "Resolving namespace '$Namespace' ..."
    $NsId = Resolve-NamespaceId -Ns $Namespace
    if (-not $NsId) {
        Write-Error "Could not resolve GitLab namespace '$Namespace'. Check the name and your token permissions."
        exit 1
    }
    Log "Namespace ID: $NsId"

    $succeeded = 0
    $failed    = 0

    $extractedRoot = Join-Path $WorkDir 'extracted'

    # Check both top-level dirs and one level deeper (in case the zip has a wrapper folder)
    $candidates = Get-ChildItem -Path $extractedRoot -Directory -Depth 1

    foreach ($dir in $candidates) {
        $isGit = $false
        $isBare = $false

        if (Test-Path (Join-Path $dir.FullName '.git')) {
            $isGit = $true
        } elseif (
            (Test-Path (Join-Path $dir.FullName 'HEAD')) -and
            (Test-Path (Join-Path $dir.FullName 'objects')) -and
            (Test-Path (Join-Path $dir.FullName 'refs'))
        ) {
            $isGit = $true
            $isBare = $true
        }

        if (-not $isGit) { continue }

        $repoName = $dir.Name -replace '\.git$', ''
        Log "Importing '$repoName' ..."

        # Create project on GitLab
        try {
            $project = New-GitLabProject -Name $repoName -NamespaceId $NsId
        } catch {
            Fail "Failed to create project '$repoName': $_"
            $failed++
            continue
        }

        $httpUrl  = $project.http_url_to_repo
        # Embed token for push auth
        $pushUrl  = $httpUrl -replace '://', "://oauth2:$Token@"

        $cloneDir = Join-Path $WorkDir "push_$repoName"

        if ($isBare) {
            git clone --bare $dir.FullName $cloneDir -q 2>&1 | Out-Null
        } else {
            git clone --mirror $dir.FullName $cloneDir -q 2>&1 | Out-Null
        }

        $pushOutput = git -C $cloneDir push --mirror $pushUrl 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok "'$repoName' -> $($GitLabUrl.TrimEnd('/'))/$Namespace/$repoName"
            $succeeded++
        } else {
            Fail "Push failed for '$repoName': $pushOutput"
            $failed++
        }

        Remove-Item -Recurse -Force $cloneDir -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Log "Done. Succeeded: $succeeded  Failed: $failed"

    if ($failed -gt 0) { exit 1 }

} finally {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}
