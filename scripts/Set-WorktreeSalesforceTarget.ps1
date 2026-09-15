<#
.SYNOPSIS
    Locks an Axon Finance issue worktree to the shared DEV org.

.DESCRIPTION
    This script is intentionally development-only. It refuses main, release,
    and hotfix branches and writes project-local Salesforce configuration plus
    an environment lock under .sf/. Production selection is reserved for the
    protected GitHub production workflow.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [string]$DevAlias = "AXON_DEV"
)

$ErrorActionPreference = "Stop"

$resolvedRepo = (Resolve-Path -LiteralPath $RepoPath).Path
$branch = (& git -C $resolvedRepo branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or -not $branch) {
    throw "Unable to determine the current branch for '$resolvedRepo'."
}

$isIssueBranch = $branch -match "^(feature|bugfix)/AXF-\d+(?:-|$)"
$isDevelop = $branch -eq "develop"
if (-not ($isIssueBranch -or $isDevelop)) {
    throw "Branch '$branch' cannot receive a local Salesforce target. Issue worktrees and develop use DEV; production is GitHub-pipeline-only."
}

if ($DevAlias -ne "AXON_DEV") {
    throw "Unexpected DEV alias '$DevAlias'. The canonical alias is AXON_DEV."
}

$sfDirectory = Join-Path $resolvedRepo ".sf"
New-Item -ItemType Directory -Path $sfDirectory -Force | Out-Null

$configPath = Join-Path $sfDirectory "config.json"
$config = [ordered]@{}
if (Test-Path -LiteralPath $configPath) {
    $existing = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json -AsHashtable
    foreach ($key in $existing.Keys) {
        $config[$key] = $existing[$key]
    }
}
$config["target-org"] = $DevAlias
[System.IO.File]::WriteAllText(
    $configPath,
    (($config | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)

$lockPath = Join-Path $sfDirectory "environment-lock.json"
$lock = [ordered]@{
    schemaVersion = 1
    environment = "DEV"
    targetOrg = $DevAlias
    branch = $branch
    persistentDeployment = "github-develop-pipeline-only"
    production = "forbidden-locally"
}
[System.IO.File]::WriteAllText(
    $lockPath,
    (($lock | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)

$verified = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($verified.'target-org' -ne $DevAlias) {
    throw "Failed to lock '$resolvedRepo' to $DevAlias."
}

Write-Host "Salesforce environment locked: branch '$branch' -> DEV ($DevAlias)." -ForegroundColor Green
Write-Host "Persistent deployment: GitHub pipeline after merge to develop." -ForegroundColor Cyan
Write-Host "Production: forbidden from this worktree." -ForegroundColor Yellow

