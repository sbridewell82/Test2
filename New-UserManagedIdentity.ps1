<#
.SYNOPSIS
    Creates an Azure User Managed Identity and assigns the required RBAC roles.

.DESCRIPTION
    Creates a UMI in the specified subscription/resource group and assigns all
    required RBAC roles at the subscription scope. Custom MS-ISR roles are
    resolved by display name.

.PARAMETER SubscriptionId
    The target Azure subscription ID.

.PARAMETER ResourceGroupName
    The resource group in which to create the UMI.

.PARAMETER Location
    Azure region for the UMI (e.g. 'uksouth').

.PARAMETER IdentityName
    Name for the UMI. Must follow the convention: umi-<env>-<purpose>
    e.g. umi-prod-avd

.PARAMETER RoleAssignmentScope
    Scope at which to assign the RBAC roles.
    Defaults to the subscription scope (/subscriptions/<SubscriptionId>).

.EXAMPLE
    .\New-UserManagedIdentity.ps1 `
        -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroupName "rg-identity-prod" `
        -Location "uksouth" `
        -IdentityName "umi-prod-avd"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [ValidatePattern('^umi-[a-z0-9]+-[a-z0-9-]+$')]
    [string]$IdentityName,

    [Parameter()]
    [string]$RoleAssignmentScope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Naming convention guard ────────────────────────────────────────────────────
# Expected format: umi-<env>-<purpose>  (all lowercase, hyphens only)
if ($IdentityName -notmatch '^umi-[a-z0-9]+-[a-z0-9-]+$') {
    throw "IdentityName '$IdentityName' does not follow the required convention: umi-<env>-<purpose>"
}

# ── Role definitions ───────────────────────────────────────────────────────────
$requiredRoles = @(
    'Application Group Contributor',
    'Backup Operator',
    'Desktop Virtualization Application Group Contributor',
    'Desktop Virtualization Host Pool Contributor',
    'Desktop Virtualization Workspace Contributor',
    'Key Vault Data Access Administrator',
    'MS-ISR: NetApp Contributor',
    'MS-ISR: Virtual Machine Contributor',
    'Network Contributor',
    'Reader',
    'MS-ISR: Recovery Services Contributor',
    'MS-ISR: Marketplace Ordering Contributor'
)

# ── Set subscription context ───────────────────────────────────────────────────
Write-Host "Setting subscription context: $SubscriptionId" -ForegroundColor Cyan
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$scope = if ($RoleAssignmentScope) {
    $RoleAssignmentScope
} else {
    "/subscriptions/$SubscriptionId"
}

# ── Create (or retrieve existing) UMI ─────────────────────────────────────────
Write-Host "Checking for existing UMI '$IdentityName' in '$ResourceGroupName'..." -ForegroundColor Cyan

$umi = Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $IdentityName -ErrorAction SilentlyContinue

if ($umi) {
    Write-Host "UMI '$IdentityName' already exists — skipping creation." -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$IdentityName", 'Create User Managed Identity')) {
        Write-Host "Creating UMI '$IdentityName'..." -ForegroundColor Cyan
        $umi = New-AzUserAssignedIdentity `
            -ResourceGroupName $ResourceGroupName `
            -Name $IdentityName `
            -Location $Location
        Write-Host "UMI created. Principal ID: $($umi.PrincipalId)" -ForegroundColor Green
    }
}

# ── Assign RBAC roles ──────────────────────────────────────────────────────────
Write-Host "`nAssigning $($requiredRoles.Count) RBAC roles at scope: $scope" -ForegroundColor Cyan

# Retrieve all role definitions once to avoid repeated API calls
$allRoles = Get-AzRoleDefinition

$results = foreach ($roleName in $requiredRoles) {
    $roleDef = $allRoles | Where-Object { $_.Name -eq $roleName }

    if (-not $roleDef) {
        Write-Warning "Role '$roleName' not found in subscription — skipping."
        [PSCustomObject]@{ Role = $roleName; Status = 'NotFound' }
        continue
    }

    $existing = Get-AzRoleAssignment `
        -ObjectId $umi.PrincipalId `
        -RoleDefinitionName $roleName `
        -Scope $scope `
        -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "  [SKIP]    $roleName (already assigned)" -ForegroundColor DarkGray
        [PSCustomObject]@{ Role = $roleName; Status = 'AlreadyAssigned' }
    } else {
        if ($PSCmdlet.ShouldProcess($scope, "Assign role '$roleName'")) {
            New-AzRoleAssignment `
                -ObjectId $umi.PrincipalId `
                -RoleDefinitionName $roleName `
                -Scope $scope | Out-Null
            Write-Host "  [OK]      $roleName" -ForegroundColor Green
            [PSCustomObject]@{ Role = $roleName; Status = 'Assigned' }
        }
    }
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host "`n── Summary ─────────────────────────────────────────────────────" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$notFound = $results | Where-Object { $_.Status -eq 'NotFound' }
if ($notFound) {
    Write-Warning "$($notFound.Count) role(s) were not found and could not be assigned. Verify the custom MS-ISR roles exist in subscription '$SubscriptionId'."
}

Write-Host "`nDone. UMI resource ID: $($umi.Id)" -ForegroundColor Green
