[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetOrg = 'AXON_DEV'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allowedTargets = @{
    AXON_DEV = '00Dfj00000YrNnkEAF'
}

if (-not $allowedTargets.ContainsKey($TargetOrg)) {
    throw "Salesforce target '$TargetOrg' is not allowlisted for this worktree."
}

$displayJson = & sf org display --target-org $TargetOrg --json 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Salesforce target '$TargetOrg' is unavailable or disconnected."
}

$display = $displayJson | ConvertFrom-Json
$actualOrgId = [string]$display.result.id
$expectedOrgId = $allowedTargets[$TargetOrg]
if ($actualOrgId -cne $expectedOrgId) {
    throw "Salesforce target '$TargetOrg' failed the source-controlled Org ID allowlist."
}

$env:SF_TARGET_ORG = $TargetOrg
Write-Output "Salesforce target verified: $TargetOrg ($expectedOrgId)"
