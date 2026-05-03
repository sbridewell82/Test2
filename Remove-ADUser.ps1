#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Search for and delete Active Directory user accounts.

.DESCRIPTION
    Searches AD for users matching the provided criteria and removes
    the matched accounts after confirmation. Supports searching by
    SamAccountName, display name, email address, or OU.

.PARAMETER SearchBy
    The attribute to search by: SamAccountName, Name, EmailAddress, or OU.

.PARAMETER SearchValue
    The value to search for. Supports wildcards (*) for Name searches.

.PARAMETER Force
    Skip the confirmation prompt and delete immediately.

.PARAMETER WhatIf
    Show what would be deleted without actually deleting.

.EXAMPLE
    .\Remove-ADUser.ps1 -SearchBy SamAccountName -SearchValue jdoe
    Search for a user by login name and prompt before deleting.

.EXAMPLE
    .\Remove-ADUser.ps1 -SearchBy Name -SearchValue "John*" -WhatIf
    Preview which users named John* would be deleted.

.EXAMPLE
    .\Remove-ADUser.ps1 -SearchBy EmailAddress -SearchValue jdoe@contoso.com -Force
    Delete by email address without a confirmation prompt.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidateSet('SamAccountName', 'Name', 'EmailAddress', 'OU')]
    [string]$SearchBy,

    [Parameter(Mandatory)]
    [string]$SearchValue,

    [switch]$Force
)

# Verify the ActiveDirectory module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not installed. Install RSAT or run on a domain controller."
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

function Search-ADUsers {
    param ([string]$By, [string]$Value)

    $filter = switch ($By) {
        'SamAccountName' { "SamAccountName -eq '$Value'" }
        'Name'           { "Name -like '$Value'" }
        'EmailAddress'   { "EmailAddress -eq '$Value'" }
        'OU'             {
            # For OU, search within the specified SearchBase path
            try {
                return Get-ADUser -Filter * -SearchBase $Value -Properties DisplayName, EmailAddress, Enabled, DistinguishedName
            } catch {
                Write-Error "Invalid OU path: $_"
                return @()
            }
        }
    }

    try {
        Get-ADUser -Filter $filter -Properties DisplayName, EmailAddress, Enabled, DistinguishedName
    } catch {
        Write-Error "AD search failed: $_"
        return @()
    }
}

# Find matching users
Write-Host "Searching Active Directory..." -ForegroundColor Cyan
$users = Search-ADUsers -By $SearchBy -Value $SearchValue

if (-not $users) {
    Write-Host "No users found matching '$SearchValue' in '$SearchBy'." -ForegroundColor Yellow
    exit 0
}

# Display results table
Write-Host "`nFound $($users.Count) user(s):" -ForegroundColor Green
$users | Select-Object SamAccountName, DisplayName, EmailAddress, Enabled, DistinguishedName |
    Format-Table -AutoSize

# Confirm and delete
$deleted = 0
$skipped = 0

foreach ($user in $users) {
    $label = "$($user.SamAccountName) ($($user.DisplayName))"

    if ($Force -or $PSCmdlet.ShouldProcess($label, "Delete AD user")) {
        try {
            Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false
            Write-Host "Deleted: $label" -ForegroundColor Red
            $deleted++
        } catch {
            Write-Warning "Failed to delete $label : $_"
            $skipped++
        }
    } else {
        Write-Host "Skipped: $label" -ForegroundColor DarkYellow
        $skipped++
    }
}

Write-Host "`nSummary: $deleted deleted, $skipped skipped." -ForegroundColor Cyan
