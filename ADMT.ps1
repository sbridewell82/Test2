### ADMT v1.25 Changes:
# - Added IFG Mission Plane
# - Added P67 Mission Plane

# Import the Active Directory module
Import-Module ActiveDirectory

# ===================== UID Helpers =====================
# Build a HashSet[int] of existing uidNumbers for fast uniqueness checks
function Get-ExistingUids {
    param(
        [string]$Server = $null
    )
    $params = @{ Filter = 'uidNumber -like "*"' ; Properties = 'uidNumber' }
    if ($Server) { $params.Server = $Server }
    try {
        $set = New-Object 'System.Collections.Generic.HashSet[int]'
        Get-ADUser @params | Where-Object { $_.uidNumber } | ForEach-Object {
            [void]$set.Add([int]$_.uidNumber)
        }
        return $set
    } catch {
        return (New-Object 'System.Collections.Generic.HashSet[int]')
    }
}

function Test-UidInUse {
    param(
        [int]$Uid,
        [System.Collections.Generic.HashSet[int]]$Existing
    )
    return $Existing.Contains($Uid)
}

function New-UniqueUid {
    param(
        [System.Collections.Generic.HashSet[int]]$Existing,
        [int]$MinUid = 200000,
        [int]$MaxUid = 299999,
        [int]$MaxTries = 5000
    )
    if ($MinUid -ge $MaxUid) { throw "New-UniqueUid: MinUid must be less than MaxUid" }
    $rand = [System.Random]::new()
    for ($i=0; $i -lt $MaxTries; $i++) {
        $candidate = $rand.Next($MinUid, $MaxUid + 1)
        if (-not $Existing.Contains($candidate)) {
            [void]$Existing.Add($candidate)
            return $candidate
        }
    }
    throw "Could not find an unused UID in range $MinUid..$MaxUid after $MaxTries attempts."
}
# =======================================================

$t = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
add-type -name win -member $t -namespace native
[native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0)

Add-Type -AssemblyName System.Windows.Forms

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Account Management Tool v1.25"
$form.Size = New-Object System.Drawing.Size(400, 500)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

# Create buttons and add event handlers
$buttons = @(
    @{ Text = "Create User Account"; Action = { CreateNewUserAccount } },
    @{ Text = "Disable User Account"; Action = { DisableExistingUserAccount } },
    @{ Text = "Enable User Account"; Action = { EnableExistingUserAccount } },
    @{ Text = "Delete User Account"; Action = { DeleteExistingUserAccount } },
    @{ Text = "Reset User Password"; Action = { ResetExistingUserAccountPassword } },
    @{ Text = "Add User to Groups"; Action = { AddUserToADGroups } },
    @{ Text = "Get User Info"; Action = { GetUserInfo } },
    @{ Text = "Change User Type"; Action = { ChangeUserAccountType } },
    @{ Text = "Exit"; Action = { $form.Close() } }
)

$buttonTop = 20
$buttonHeight = 30

foreach ($buttonInfo in $buttons) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $buttonInfo.Text
    $button.Size = New-Object System.Drawing.Size(350, $buttonHeight)
    $button.Location = New-Object System.Drawing.Point(20, $buttonTop)
    $buttonTop += $buttonHeight + 10
    $button.Add_Click($buttonInfo.Action)
    $form.Controls.Add($button)
}

function CreateNewUserAccount {
    $outputTextBox.AppendText("Creating new user account...`r`n")

    $ouOptions = @{
        "DATAPLANE"   = "OU=DataPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "MPE"         = "OU=MPE,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "P51"         = "OU=P51,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "P67"         = "OU=P67,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "MIGR"        = "OU=migr,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "PDEV"        = "OU=PDev,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "SHARED"      = "OU=Shared,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "TEST"        = "OU=Test,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "ASWL"        = "OU=ASWL,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "IFG"         = "OU=IFG,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        "NONE"        = ""
    }

    $acctType = @{
        "GENERAL-USER"    = "OU=Internal,OU=Standard,OU=Accounts,DC=lmc-aero-up,DC=com"
        "DP-ADMIN"        = "OU=DPAdmins,OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com"
        "MP-ADMIN"        = "OU=MPAdmins,OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com"
        "SERVICE-ACCOUNT" = "OU=Service,OU=Accounts,DC=lmc-aero-up,DC=com"
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Create New IL4 Account"
    $form.Size = New-Object System.Drawing.Size(350, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

    $labelNumUsers = New-Object System.Windows.Forms.Label
    $labelNumUsers.Location = New-Object System.Drawing.Point(20, 20)
    $labelNumUsers.Size = New-Object System.Drawing.Size(100, 20)
    $labelNumUsers.Text = "Number of Users:"
    $form.Controls.Add($labelNumUsers)

    $numericUpDown = New-Object System.Windows.Forms.NumericUpDown
    $numericUpDown.Location = New-Object System.Drawing.Point(130, 20)
    $numericUpDown.Size = New-Object System.Drawing.Size(50, 20)
    $numericUpDown.Minimum = 1
    $form.Controls.Add($numericUpDown)

    $labelDefaultPassword = New-Object System.Windows.Forms.Label
    $labelDefaultPassword.Location = New-Object System.Drawing.Point(20, 50)
    $labelDefaultPassword.Size = New-Object System.Drawing.Size(110, 30)
    $labelDefaultPassword.Text = "Default Password:"
    $form.Controls.Add($labelDefaultPassword)

    $maskedTxtDefaultPassword = New-Object System.Windows.Forms.MaskedTextBox
    $maskedTxtDefaultPassword.Location = New-Object System.Drawing.Point(130, 50)
    $maskedTxtDefaultPassword.Size = New-Object System.Drawing.Size(200, 50)
    $maskedTxtDefaultPassword.PasswordChar = '*'
    $form.Controls.Add($maskedTxtDefaultPassword)

    $checkBoxShowPassword = New-Object System.Windows.Forms.CheckBox
    $checkBoxShowPassword.Location = New-Object System.Drawing.Point(130, 80)
    $checkBoxShowPassword.Size = New-Object System.Drawing.Size(180, 20)
    $checkBoxShowPassword.Text = "Show Password"
    $form.Controls.Add($checkBoxShowPassword)

    $checkBoxShowPassword.Add_CheckedChanged({
        if ($checkBoxShowPassword.Checked) {
            $maskedTxtDefaultPassword.PasswordChar = 0
        } else {
            $maskedTxtDefaultPassword.PasswordChar = '*'
        }
    })

    $btnCreateUsers = New-Object System.Windows.Forms.Button
    $btnCreateUsers.Location = New-Object System.Drawing.Point(100, 120)
    $btnCreateUsers.Size = New-Object System.Drawing.Size(150, 30)
    $btnCreateUsers.Text = "Create Users"
    $btnCreateUsers.Add_Click({
        $numUsers = $numericUpDown.Value
        $defaultPassword = $maskedTxtDefaultPassword.Text

        $domainControllerList = "dc-01.lmc-aero-up.com", "dc-02.lmc-aero-up.com"
        $anyDC = Get-Random -InputObject $domainControllerList
        $existingUids = Get-ExistingUids -Server $anyDC

        for ($i = 0; $i -lt $numUsers; $i++) {
            $userForm = New-Object System.Windows.Forms.Form
            $userForm.Text = "Create Azure il4 User $($i + 1)"
            $userForm.Size = New-Object System.Drawing.Size(600, 500)
            $userForm.StartPosition = "CenterScreen"
            $userForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

            $labelFirstName = New-Object System.Windows.Forms.Label
            $labelFirstName.Location = New-Object System.Drawing.Point(20, 20)
            $labelFirstName.Size = New-Object System.Drawing.Size(150, 20)
            $labelFirstName.Text = "First Name:"
            $userForm.Controls.Add($labelFirstName)

            $labelLastName = New-Object System.Windows.Forms.Label
            $labelLastName.Location = New-Object System.Drawing.Point(20, 50)
            $labelLastName.Size = New-Object System.Drawing.Size(150, 20)
            $labelLastName.Text = "Last Name:"
            $userForm.Controls.Add($labelLastName)

            $labelUserName = New-Object System.Windows.Forms.Label
            $labelUserName.Location = New-Object System.Drawing.Point(20, 80)
            $labelUserName.Size = New-Object System.Drawing.Size(150, 20)
            $labelUserName.Text = "Username:"
            $userForm.Controls.Add($labelUserName)

            $txtUserName = New-Object System.Windows.Forms.TextBox
            $txtUserName.Location = New-Object System.Drawing.Point(180, 80)
            $txtUserName.Size = New-Object System.Drawing.Size(250, 20)
            $userForm.Controls.Add($txtUserName)

            $txtFirstName = New-Object System.Windows.Forms.TextBox
            $txtFirstName.Location = New-Object System.Drawing.Point(180, 20)
            $txtFirstName.Size = New-Object System.Drawing.Size(250, 20)
            $userForm.Controls.Add($txtFirstName)

            $txtLastName = New-Object System.Windows.Forms.TextBox
            $txtLastName.Location = New-Object System.Drawing.Point(180, 50)
            $txtLastName.Size = New-Object System.Drawing.Size(250, 20)
            $userForm.Controls.Add($txtLastName)

            $labelOUPath = New-Object System.Windows.Forms.Label
            $labelOUPath.Location = New-Object System.Drawing.Point(20, 110)
            $labelOUPath.Size = New-Object System.Drawing.Size(150, 20)
            $labelOUPath.Text = "Select Mission Plane:"
            $userForm.Controls.Add($labelOUPath)

            $comboBoxOUPath = New-Object System.Windows.Forms.ComboBox
            $comboBoxOUPath.Location = New-Object System.Drawing.Point(180, 110)
            $comboBoxOUPath.Size = New-Object System.Drawing.Size(250, 20)
            $comboBoxOUPath.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $ouOptions.Keys | ForEach-Object { [void]$comboBoxOUPath.Items.Add($_) }
            $userForm.Controls.Add($comboBoxOUPath)

            $labelGroups = New-Object System.Windows.Forms.Label
            $labelGroups.Location = New-Object System.Drawing.Point(20, 140)
            $labelGroups.Size = New-Object System.Drawing.Size(150, 20)
            $labelGroups.Text = "Select Account Type:"
            $userForm.Controls.Add($labelGroups)

            $comboBoxAcctType = New-Object System.Windows.Forms.ComboBox
            $comboBoxAcctType.Location = New-Object System.Drawing.Point(180, 140)
            $comboBoxAcctType.Size = New-Object System.Drawing.Size(250, 20)
            $comboBoxAcctType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $acctType.Keys | ForEach-Object { [void]$comboBoxAcctType.Items.Add($_) }
            $userForm.Controls.Add($comboBoxAcctType)

            $labelUID = New-Object System.Windows.Forms.Label
            $labelUID.Location = New-Object System.Drawing.Point(20, 170)
            $labelUID.Size = New-Object System.Drawing.Size(150, 20)
            $labelUID.Text = "Unix UID (EWP):"
            $userForm.Controls.Add($labelUID)

            $txtUID = New-Object System.Windows.Forms.TextBox
            $txtUID.Location = New-Object System.Drawing.Point(180, 170)
            $txtUID.Size = New-Object System.Drawing.Size(250, 20)
            $userForm.Controls.Add($txtUID)

            $txtUID.Add_KeyPress({
                param($sender, $e)
                if ($txtUID.ReadOnly) { return }
                if (-not [char]::IsControl($e.KeyChar) -and -not [char]::IsDigit($e.KeyChar)) {
                    $e.Handled = $true
                }
            })

            $labelSelectGroups = New-Object System.Windows.Forms.Label
            $labelSelectGroups.Location = New-Object System.Drawing.Point(20, 200)
            $labelSelectGroups.Size = New-Object System.Drawing.Size(150, 20)
            $labelSelectGroups.Text = "Select Groups for User:"
            $userForm.Controls.Add($labelSelectGroups)

            $checkedListBoxGroups = New-Object System.Windows.Forms.CheckedListBox
            $checkedListBoxGroups.Location = New-Object System.Drawing.Point(180, 200)
            $checkedListBoxGroups.Size = New-Object System.Drawing.Size(250, 150)
            $checkedListBoxGroups.CheckOnClick = $true
            $userForm.Controls.Add($checkedListBoxGroups)

            $comboBoxOUPath.Add_SelectedIndexChanged({
                $selectedShortName = $comboBoxOUPath.SelectedItem.ToString()
                $ouPathLocal = $ouOptions[$selectedShortName]
                $groups = Get-ADGroup -Filter * -SearchBase $ouPathLocal
                $checkedListBoxGroups.Items.Clear()
                foreach ($group in $groups) { $checkedListBoxGroups.Items.Add($group.Name) }
            })

            $labelLMIEmail = New-Object System.Windows.Forms.Label
            $labelLMIEmail.Location = New-Object System.Drawing.Point(20, 360)
            $labelLMIEmail.Size = New-Object System.Drawing.Size(150, 20)
            $labelLMIEmail.Text = "Email Address(EWP):"
            $userForm.Controls.Add($labelLMIEmail)

            $txtLMIEmail = New-Object System.Windows.Forms.TextBox
            $txtLMIEmail.Location = New-Object System.Drawing.Point(180, 360)
            $txtLMIEmail.Size = New-Object System.Drawing.Size(250, 20)
            $userForm.Controls.Add($txtLMIEmail)

            $checkboxEnabled = New-Object System.Windows.Forms.CheckBox
            $checkboxEnabled.Location = New-Object System.Drawing.Point(180, 390)
            $checkboxEnabled.Size = New-Object System.Drawing.Size(200, 20)
            $checkboxEnabled.Text = "Account Enabled"
            $checkboxEnabled.Checked = $true
            $userForm.Controls.Add($checkboxEnabled)

            $labelEWP = New-Object System.Windows.Forms.Label
            $labelEWP.Location = New-Object System.Drawing.Point(400, 460)
            $labelEWP.Size = New-Object System.Drawing.Size(180, 20)
            $labelEWP.Text = "**EWP = Enterprise White Pages"
            $labelEWP.TextAlign = "Right"
            $userForm.Controls.Add($labelEWP)

            $comboBoxAcctType.Add_SelectedIndexChanged({
                $selType = $comboBoxAcctType.SelectedItem.ToString()
                if ($selType -eq "SERVICE-ACCOUNT") {
                    try {
                        $auto = New-UniqueUid -Existing $existingUids -MinUid 200000 -MaxUid 299999
                        $txtUID.Text = "$auto"
                        $txtUID.ReadOnly = $true
                        $labelUID.Text = "Unix UID (auto for Service Accounts):"
                    } catch {
                        [System.Windows.Forms.MessageBox]::Show("Failed to auto-generate UID: $_","UID Error",
                            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        $txtUID.Text = ""
                        $txtUID.ReadOnly = $true
                    }
                } else {
                    $txtUID.ReadOnly = $false
                    $txtUID.Text = ""
                    $labelUID.Text = "Unix UID (required):"
                }
            })

            $btnCreateUser = New-Object System.Windows.Forms.Button
            $btnCreateUser.Location = New-Object System.Drawing.Point(200, 420)
            $btnCreateUser.Size = New-Object System.Drawing.Size(100, 30)
            $btnCreateUser.Text = "Create User"

            $btnCreateUser.Add_Click({
                $selectedShortName = $comboBoxOUPath.SelectedItem.ToString()
                $ouPath = $ouOptions[$selectedShortName]
                $selectedAcctType = $comboBoxAcctType.SelectedItem.ToString()
                $acctPath = $acctType[$selectedAcctType]

                switch ($selectedAcctType) {
                    "SERVICE-ACCOUNT" {
                        if ([string]::IsNullOrWhiteSpace($txtUID.Text) -or $txtUID.Text -notmatch '^\d+$') {
                            try {
                                $uidNumber = New-UniqueUid -Existing $existingUids -MinUid 200000 -MaxUid 299999
                                $txtUID.Text = "$uidNumber"
                            } catch {
                                [System.Windows.Forms.MessageBox]::Show("Failed to generate UID: $_","UID Error",
                                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                                return
                            }
                        } else {
                            $uidNumber = [int]$txtUID.Text
                            if (Test-UidInUse -Uid $uidNumber -Existing $existingUids) {
                                try {
                                    $uidNumber = New-UniqueUid -Existing $existingUids -MinUid 200000 -MaxUid 299999
                                    $txtUID.Text = "$uidNumber"
                                } catch {
                                    [System.Windows.Forms.MessageBox]::Show("Failed to generate UID: $_","UID Error",
                                        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                                    return
                                }
                            } else {
                                [void]$existingUids.Add($uidNumber)
                            }
                        }
                    }
                    default {
                        if ([string]::IsNullOrWhiteSpace($txtUID.Text)) {
                            [System.Windows.Forms.MessageBox]::Show("Unix UID is required.","Validation Error",
                                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                            return
                        }
                        if ($txtUID.Text -notmatch '^\d+$') {
                            [System.Windows.Forms.MessageBox]::Show("Unix UID must be numeric digits only.","Validation Error",
                                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                            return
                        }
                        $uidNumber = [int]$txtUID.Text
                    }
                }

                $displayNameSuffix = ""
                $descriptionSuffix = ""
                if ($checkedListBoxGroups.CheckedItems -contains "mp-pdev-local-admin") {
                    $displayNameSuffix = " (Local Admin)"
                    $descriptionSuffix = "Local Admin account for $($txtUserName.Text)"
                }

                $userProperties = @{
                    GivenName         = $txtFirstName.Text
                    Surname           = ($txtLastName.Text + " " + $displayNameSuffix)
                    DisplayName       = ($txtFirstName.Text + " " + $txtLastName.Text + $displayNameSuffix)
                    SamAccountName    = $txtUserName.Text
                    UserPrincipalName = ($txtUserName.Text.ToLower() + "@lmc-aero-up.com")
                    AccountPassword   = ConvertTo-SecureString $defaultPassword -AsPlainText -Force
                    Enabled           = $checkboxEnabled.Checked
                    Pager             = $txtLMIEmail.Text
                    Description       = $descriptionSuffix
                }

                if ($descriptionSuffix -eq "") {
                    switch ($selectedAcctType) {
                        "GENERAL-USER"    { $userProperties.Description = "General account for $($txtUserName.Text)" }
                        "DP-ADMIN"        { $userProperties.Description = "DataPlane Admin account for $($txtUserName.Text)" }
                        "MP-ADMIN"        { $userProperties.Description = "MissionPlane Admin account for $($txtUserName.Text)" }
                        "SERVICE-ACCOUNT" { $userProperties.Description = "Service Account. Please update description for its purpose." }
                    }
                }

                $selectedGroups = @()
                foreach ($item in $checkedListBoxGroups.CheckedItems) { $selectedGroups += $item.ToString() }

                try {
                    New-ADUser -Name ($userProperties.GivenName + " " + $userProperties.Surname) `
                               -GivenName $userProperties.GivenName `
                               -Surname $userProperties.Surname `
                               -DisplayName $userProperties.DisplayName `
                               -SamAccountName $userProperties.SamAccountName `
                               -UserPrincipalName $userProperties.UserPrincipalName `
                               -Description $userProperties.Description `
                               -AccountPassword $userProperties.AccountPassword `
                               -Enabled $userProperties.Enabled `
                               -Path $acctPath `
                               -OtherAttributes @{pager = $userProperties.Pager}

                    Set-ADUser -Identity $userProperties.SamAccountName -Replace @{ unixhomedirectory = "/home/$($userProperties.SamAccountName)" }
                    Set-ADUser -Identity $userProperties.SamAccountName -Add @{ ObjectClass = "posixAccount" }

                    foreach ($group in $selectedGroups) {
                        Add-ADGroupMember -Identity $group -Members $userProperties.SamAccountName
                    }

                    if ($selectedAcctType -eq "SERVICE-ACCOUNT") {
                        Add-ADGroupMember -Identity "CN=ServiceAccounts,OU=Security,OU=Groups,DC=lmc-aero-up,DC=com" -Members $userProperties.SamAccountName
                    }

                    Invoke-Command -ComputerName $anyDC -ScriptBlock {
                        Enable-QASUnixuser -Identity $using:userProperties.SamAccountName | Out-Null
                    }

                    Set-ADUser -Identity $userProperties.SamAccountName -Replace @{ uidNumber = "$uidNumber" }

                    Invoke-Command -ComputerName "aadc-01.lmc-aero-up.com" -ScriptBlock {
                        param ($PolicyType)
                        Start-ADSyncSyncCycle -PolicyType $PolicyType
                    } -ArgumentList "Delta"

                    [System.Windows.Forms.MessageBox]::Show("User/s created successfully.", "Success",
                        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    $userForm.Close()
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            })
            $userForm.Controls.Add($btnCreateUser)
            $userForm.ShowDialog() | Out-Null
        }

        [System.Windows.Forms.MessageBox]::Show(
            "All il4 users have been created. Please email users their logon info, with a separate email containing the password.",
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information
        )
        $form.Close()
    })

    $form.Controls.Add($btnCreateUsers)
    $form.ShowDialog() | Out-Null
}

function DeleteExistingUserAccount {
    $outputTextBox.AppendText("Deleting existing user account...`r`n")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Delete Existing User Account"
    $form.Size = New-Object System.Drawing.Size(400, 150)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(10, 20)
    $labelUsername.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(120, 20)
    $textBoxUsername.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($textBoxUsername)

    $deleteButton = New-Object System.Windows.Forms.Button
    $deleteButton.Location = New-Object System.Drawing.Point(150, 60)
    $deleteButton.Size = New-Object System.Drawing.Size(100, 25)
    $deleteButton.Text = "Delete User"
    $deleteButton.Add_Click({
        $username = $textBoxUsername.Text
        if (Get-ADUser -Filter "SamAccountName -eq '$username'") {
            Remove-ADUser -Identity $username -Confirm:$false
            [System.Windows.Forms.MessageBox]::Show("User '$username' has been successfully deleted.", "Success", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
            $form.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("User '$username' does not exist.", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
            $form.Close()
        }
    })
    $form.Controls.Add($deleteButton)
    $form.ShowDialog() | Out-Null
}

function DisableExistingUserAccount {
    $outputTextBox.AppendText("Disabling existing user account...`r`n")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Disable Existing User Account"
    $form.Size = New-Object System.Drawing.Size(300, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(20, 20)
    $labelUsername.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(110, 20)
    $textBoxUsername.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($textBoxUsername)

    $labelDescription = New-Object System.Windows.Forms.Label
    $labelDescription.Text = "Description:"
    $labelDescription.Location = New-Object System.Drawing.Point(20, 60)
    $labelDescription.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($labelDescription)

    $textBoxDescription = New-Object System.Windows.Forms.TextBox
    $textBoxDescription.Location = New-Object System.Drawing.Point(110, 60)
    $textBoxDescription.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($textBoxDescription)

    $buttonDisable = New-Object System.Windows.Forms.Button
    $buttonDisable.Text = "Disable"
    $buttonDisable.Location = New-Object System.Drawing.Point(110, 100)
    $buttonDisable.Size = New-Object System.Drawing.Size(80, 25)
    $buttonDisable.Add_Click({
        $username = $textBoxUsername.Text
        $description = $textBoxDescription.Text
        DisableExistingUserAccountFunction -Username $username -Description $description
    })
    $form.Controls.Add($buttonDisable)
    $form.ShowDialog() | Out-Null
}

function DisableExistingUserAccountFunction {
    param (
        [string]$Username,
        [string]$Description
    )
    try {
        $user = Get-ADUser -Identity $Username -ErrorAction Stop
        Set-ADUser -Identity $user -Enabled $false
        Set-ADUser -Identity $user -Description $Description
        $newOU = "OU=Disabled,OU=Accounts,DC=lmc-aero-up,DC=com"
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $newOU
        [System.Windows.Forms.MessageBox]::Show("User account '$Username' disabled and moved to Disabled OU successfully.", "Success", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error disabling user account '$Username': $_", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
        $form.Close()
    }
}

function EnableExistingUserAccount {
    $outputTextBox.AppendText("Enabling existing user account...`r`n")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Enable Existing User Account"
    $form.Size = New-Object System.Drawing.Size(400, 250)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(20, 20)
    $labelUsername.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(130, 20)
    $textBoxUsername.Size = New-Object System.Drawing.Size(230, 20)
    $form.Controls.Add($textBoxUsername)

    $labelOU = New-Object System.Windows.Forms.Label
    $labelOU.Text = "Select OU:"
    $labelOU.Location = New-Object System.Drawing.Point(20, 60)
    $labelOU.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelOU)

    $comboBoxOU = New-Object System.Windows.Forms.ComboBox
    $comboBoxOU.Location = New-Object System.Drawing.Point(130, 60)
    $comboBoxOU.Size = New-Object System.Drawing.Size(230, 20)
    $comboBoxOU.Items.Add("GENERAL")
    $comboBoxOU.Items.Add("DP-ADMIN")
    $comboBoxOU.Items.Add("MP-ADMIN")
    $comboBoxOU.SelectedIndex = 0
    $form.Controls.Add($comboBoxOU)

    $labelDescription = New-Object System.Windows.Forms.Label
    $labelDescription.Text = "Description (optional):"
    $labelDescription.Location = New-Object System.Drawing.Point(20, 100)
    $labelDescription.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($labelDescription)

    $textBoxDescription = New-Object System.Windows.Forms.TextBox
    $textBoxDescription.Location = New-Object System.Drawing.Point(150, 100)
    $textBoxDescription.Size = New-Object System.Drawing.Size(210, 20)
    $form.Controls.Add($textBoxDescription)

    $buttonEnable = New-Object System.Windows.Forms.Button
    $buttonEnable.Text = "Enable"
    $buttonEnable.Location = New-Object System.Drawing.Point(150, 140)
    $buttonEnable.Size = New-Object System.Drawing.Size(80, 25)
    $buttonEnable.Add_Click({
        $username = $textBoxUsername.Text
        $ouSelection = $comboBoxOU.SelectedItem
        $description = $textBoxDescription.Text
        EnableExistingUserAccountFunction -Username $username -OUSelection $ouSelection -Description $description
    })
    $form.Controls.Add($buttonEnable)
    $form.ShowDialog() | Out-Null
}

function EnableExistingUserAccountFunction {
    param (
        [string]$Username,
        [string]$OUSelection,
        [string]$Description
    )
    try {
        $user = Get-ADUser -Identity $Username -ErrorAction Stop
        Set-ADUser -Identity $user -Enabled $true
        if ($Description) { Set-ADUser -Identity $user -Description $Description }

        switch ($OUSelection) {
            "GENERAL"   { $targetOU = "OU=Internal,OU=Standard,OU=Accounts,DC=lmc-aero-up,DC=com" }
            "DP-ADMIN"  { $targetOU = "OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com" }
            "MP-ADMIN"  { $targetOU = "OU=CISRAdmins,OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com" }
        }
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $targetOU
        [System.Windows.Forms.MessageBox]::Show("User account '$Username' enabled and moved to '$OUSelection' successfully.", "Success", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error enabling or moving user account '$Username': $_", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
        $form.Close()
    }
}

function ResetExistingUserAccountPassword {
    $outputTextBox.AppendText("Resetting user account password...`r`n")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Reset Existing User Account Password"
    $form.Size = New-Object System.Drawing.Size(400, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(20, 20)
    $labelUsername.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(110, 20)
    $textBoxUsername.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($textBoxUsername)

    $labelNewPassword = New-Object System.Windows.Forms.Label
    $labelNewPassword.Text = "Password:"
    $labelNewPassword.Location = New-Object System.Drawing.Point(20, 50)
    $labelNewPassword.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($labelNewPassword)

    $textBoxNewPassword = New-Object System.Windows.Forms.TextBox
    $textBoxNewPassword.Location = New-Object System.Drawing.Point(110, 50)
    $textBoxNewPassword.Size = New-Object System.Drawing.Size(250, 20)
    $textBoxNewPassword.PasswordChar = "*"
    $form.Controls.Add($textBoxNewPassword)

    $checkBoxShowPassword = New-Object System.Windows.Forms.CheckBox
    $checkBoxShowPassword.Text = "Show Password"
    $checkBoxShowPassword.Location = New-Object System.Drawing.Point(150, 130)
    $checkBoxShowPassword.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($checkBoxShowPassword)

    $buttonReset = New-Object System.Windows.Forms.Button
    $buttonReset.Text = "Reset Password"
    $buttonReset.Location = New-Object System.Drawing.Point(150, 90)
    $buttonReset.Size = New-Object System.Drawing.Size(120, 30)
    $buttonReset.Add_Click({
        $username = $textBoxUsername.Text
        $newPassword = if ($checkBoxShowPassword.Checked) { $textBoxNewPassword.Text } else { $textBoxNewPassword.Text | ConvertTo-SecureString -AsPlainText -Force }
        ResetExistingUserAccountPasswordFunction $username $newPassword
    })
    $form.Controls.Add($buttonReset)

    $checkBoxShowPassword.Add_CheckedChanged({
        if ($checkBoxShowPassword.Checked) { $textBoxNewPassword.PasswordChar = 0 }
        else { $textBoxNewPassword.PasswordChar = "*" }
    })

    $form.ShowDialog() | Out-Null
}

function ResetExistingUserAccountPasswordFunction {
    param (
        [string]$Username,
        [securestring]$NewPassword
    )
    try {
        Set-ADAccountPassword -Identity $username -NewPassword $newPassword -Reset -PassThru | Set-ADUser -ChangePasswordAtLogon $false
        Invoke-Command -ComputerName "aadc-01.lmc-aero-up.com" -ScriptBlock {
            param ($PolicyType)
            Start-ADSyncSyncCycle -PolicyType $PolicyType
        } -ArgumentList "Delta"
        [System.Windows.Forms.MessageBox]::Show("Password reset successfully for user '$Username'.", "Success", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error resetting password for user '$Username': $_", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
        $form.Close()
    }
}

function AddUserToADGroups {
    $outputTextBox.AppendText("Adding user to AD groups...`r`n")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Add AD User to AD Groups"
    $form.Size = New-Object System.Drawing.Size(500, 400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(10, 10)
    $labelUsername.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(120, 10)
    $textBoxUsername.Size = New-Object System.Drawing.Size(250, 25)
    $form.Controls.Add($textBoxUsername)

    $labelPlane = New-Object System.Windows.Forms.Label
    $labelPlane.Text = "Mission Plane:"
    $labelPlane.Location = New-Object System.Drawing.Point(10, 45)
    $labelPlane.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($labelPlane)

    $comboBoxOU = New-Object System.Windows.Forms.ComboBox
    $comboBoxOU.Location = New-Object System.Drawing.Point(120, 45)
    $comboBoxOU.Size = New-Object System.Drawing.Size(250, 25)
    $comboBoxOU.Items.AddRange(@("DATAPLANE", "PDEV", "SHARED", "TEST", "P51", "P67", "MIGR", "MPE", "ASWL", "IFG"))
    $form.Controls.Add($comboBoxOU)

    $labelGroups = New-Object System.Windows.Forms.Label
    $labelGroups.Text = "Available AD Groups:"
    $labelGroups.Location = New-Object System.Drawing.Point(10, 80)
    $labelGroups.Size = New-Object System.Drawing.Size(150, 25)
    $form.Controls.Add($labelGroups)

    $listBoxGroups = New-Object System.Windows.Forms.ListBox
    $listBoxGroups.Location = New-Object System.Drawing.Point(10, 110)
    $listBoxGroups.Size = New-Object System.Drawing.Size(250, 220)
    $listBoxGroups.SelectionMode = "MultiSimple"
    $form.Controls.Add($listBoxGroups)

    $buttonAddToGroups = New-Object System.Windows.Forms.Button
    $buttonAddToGroups.Location = New-Object System.Drawing.Point(270, 110)
    $buttonAddToGroups.Size = New-Object System.Drawing.Size(100, 25)
    $buttonAddToGroups.Text = "Populate Groups"
    $buttonAddToGroups.Add_Click({
        $selectedOU = $comboBoxOU.SelectedItem
        $ouOptions = @{
            'DATAPLANE' = "OU=DataPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            'MPE'       = "OU=MPE,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            'PDEV'      = 'OU=PDev,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com'
            'SHARED'    = 'OU=Shared,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com'
            'TEST'      = 'OU=Test,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com'
            'P51'       = "OU=P51,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            'P67'       = "OU=P67,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            'MIGR'      = "OU=migr,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            'ASWL'      = "OU=ASWL,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
            "IFG"       = "OU=IFG,OU=MissionPlane,OU=Groups,DC=lmc-aero-up,DC=com"
        }
        $ouDN = $ouOptions[$selectedOU]
        try {
            $groups = Get-ADGroup -Filter * -SearchBase $ouDN | Select-Object -Property Name
            $listBoxGroups.Items.Clear()
            foreach ($group in $groups) { $listBoxGroups.Items.Add($group.Name) }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error occurred while retrieving groups: $_", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
            $form.Close()
        }
    })
    $form.Controls.Add($buttonAddToGroups)

    $buttonAddUserToGroups = New-Object System.Windows.Forms.Button
    $buttonAddUserToGroups.Location = New-Object System.Drawing.Point(270, 150)
    $buttonAddUserToGroups.Size = New-Object System.Drawing.Size(200, 25)
    $buttonAddUserToGroups.Text = "Add User to Selected Groups"
    $buttonAddUserToGroups.Add_Click({
        $username = $textBoxUsername.Text
        try {
            $selectedGroups = $listBoxGroups.SelectedItems
            foreach ($group in $selectedGroups) {
                Add-ADGroupMember -Identity $group -Members $username
            }
            Invoke-Command -ComputerName "aadc-01.lmc-aero-up.com" -ScriptBlock {
                param ($PolicyType)
                Start-ADSyncSyncCycle -PolicyType $PolicyType
            } -ArgumentList "Delta"
            [System.Windows.Forms.MessageBox]::Show("User '$username' added to selected groups.", "Success", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error occurred while adding user to groups: $_", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
            $form.Close()
        }
    })
    $form.Controls.Add($buttonAddUserToGroups)
    $form.ShowDialog() | Out-Null
}

function ChangeUserAccountType {
    Add-Type -AssemblyName System.Windows.Forms

    $acctType = @{
        "GENERAL"  = "OU=Internal,OU=Standard,OU=Accounts,DC=lmc-aero-up,DC=com"
        "DP-ADMIN" = "OU=DPAdmins,OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com"
        "MP-ADMIN" = "OU=MPAdmins,OU=Internal,OU=Administrator,OU=Enhanced,OU=Accounts,DC=lmc-aero-up,DC=com"
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Change User Account Type"
    $form.Size = New-Object System.Drawing.Size(400, 200)
    $form.StartPosition = "CenterScreen"

    $usernameLabel = New-Object System.Windows.Forms.Label
    $usernameLabel.Text = "Username:"
    $usernameLabel.Location = New-Object System.Drawing.Point(10, 20)
    $usernameLabel.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($usernameLabel)

    $usernameBox = New-Object System.Windows.Forms.TextBox
    $usernameBox.Location = New-Object System.Drawing.Point(120, 20)
    $usernameBox.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($usernameBox)

    $acctTypeLabel = New-Object System.Windows.Forms.Label
    $acctTypeLabel.Text = "Account Type:"
    $acctTypeLabel.Location = New-Object System.Drawing.Point(10, 60)
    $acctTypeLabel.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($acctTypeLabel)

    $acctTypeBox = New-Object System.Windows.Forms.ComboBox
    $acctTypeBox.Location = New-Object System.Drawing.Point(120, 60)
    $acctTypeBox.Size = New-Object System.Drawing.Size(250, 20)
    $acctTypeBox.DropDownStyle = "DropDownList"
    $acctTypeBox.Items.AddRange($acctType.Keys)
    $form.Controls.Add($acctTypeBox)

    $moveButton = New-Object System.Windows.Forms.Button
    $moveButton.Text = "Move User"
    $moveButton.Location = New-Object System.Drawing.Point(150, 100)
    $moveButton.Size = New-Object System.Drawing.Size(100, 30)
    $form.Controls.Add($moveButton)

    $moveButton.Add_Click({
        $username = $usernameBox.Text
        $selectedAcctType = $acctTypeBox.SelectedItem

        if (-not $username) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a username.", "Error")
            return
        }
        if (-not $selectedAcctType) {
            [System.Windows.Forms.MessageBox]::Show("Please select an account type.", "Error")
            return
        }

        $destinationOU = $acctType[$selectedAcctType]
        try {
            $user = Get-ADUser -Identity $username -Properties DistinguishedName
            if (-not $user) {
                [System.Windows.Forms.MessageBox]::Show("User '$username' not found.", "Error")
                return
            }
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $destinationOU
            [System.Windows.Forms.MessageBox]::Show("User '$username' has been successfully moved to $selectedAcctType.", "Success")
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to move user: $_", "Error")
            $form.Close()
        }
    })

    $form.ShowDialog() | Out-Null
}

function GetUserInfo {
    $outputTextBox.AppendText("Getting user info...`r`n")

    $inputForm = New-Object System.Windows.Forms.Form
    $inputForm.Text = "Enter Username"
    $inputForm.Size = New-Object System.Drawing.Size(300, 180)
    $inputForm.StartPosition = "CenterScreen"
    $inputForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $inputForm.MaximizeBox = $false

    $labelUsername = New-Object System.Windows.Forms.Label
    $labelUsername.Text = "Enter Username:"
    $labelUsername.Location = New-Object System.Drawing.Point(10, 20)
    $labelUsername.Size = New-Object System.Drawing.Size(100, 20)
    $inputForm.Controls.Add($labelUsername)

    $textBoxUsername = New-Object System.Windows.Forms.TextBox
    $textBoxUsername.Location = New-Object System.Drawing.Point(120, 20)
    $textBoxUsername.Size = New-Object System.Drawing.Size(150, 20)
    $inputForm.Controls.Add($textBoxUsername)

    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Location = New-Object System.Drawing.Point(80, 110)
    $buttonOK.Size = New-Object System.Drawing.Size(75, 23)
    $buttonOK.Text = "OK"
    $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $inputForm.AcceptButton = $buttonOK
    $inputForm.Controls.Add($buttonOK)

    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Location = New-Object System.Drawing.Point(160, 110)
    $buttonCancel.Size = New-Object System.Drawing.Size(75, 23)
    $buttonCancel.Text = "Cancel"
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $inputForm.CancelButton = $buttonCancel
    $inputForm.Controls.Add($buttonCancel)

    $result = $inputForm.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $username = $textBoxUsername.Text
        $user = Get-ADUser -Identity $username -Properties GivenName, Surname, Enabled, LockedOut, MemberOf, Description
        if ($user) {
            $outputForm = New-Object System.Windows.Forms.Form
            $outputForm.Text = "User Information"
            $outputForm.Size = New-Object System.Drawing.Size(400, 500)
            $outputForm.StartPosition = "CenterScreen"
            $outputForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $outputForm.MaximizeBox = $false

            $labelFirstName = New-Object System.Windows.Forms.Label
            $labelFirstName.Text = "First Name:"
            $labelFirstName.Location = New-Object System.Drawing.Point(10, 20)
            $labelFirstName.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelFirstName)

            $labelLastName = New-Object System.Windows.Forms.Label
            $labelLastName.Text = "Last Name:"
            $labelLastName.Location = New-Object System.Drawing.Point(10, 50)
            $labelLastName.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelLastName)

            $labelDescription = New-Object System.Windows.Forms.Label
            $labelDescription.Text = "Description:"
            $labelDescription.Location = New-Object System.Drawing.Point(10, 80)
            $labelDescription.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelDescription)

            $labelAccountStatus = New-Object System.Windows.Forms.Label
            $labelAccountStatus.Text = "Account Status:"
            $labelAccountStatus.Location = New-Object System.Drawing.Point(10, 110)
            $labelAccountStatus.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelAccountStatus)

            $labelLockoutStatus = New-Object System.Windows.Forms.Label
            $labelLockoutStatus.Text = "Lockout Status:"
            $labelLockoutStatus.Location = New-Object System.Drawing.Point(10, 140)
            $labelLockoutStatus.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelLockoutStatus)

            $labelGroups = New-Object System.Windows.Forms.Label
            $labelGroups.Text = "Groups:"
            $labelGroups.Location = New-Object System.Drawing.Point(10, 170)
            $labelGroups.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelGroups)

            $labelFirstNameValue = New-Object System.Windows.Forms.Label
            $labelFirstNameValue.Text = $user.GivenName
            $labelFirstNameValue.Location = New-Object System.Drawing.Point(120, 20)
            $labelFirstNameValue.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelFirstNameValue)

            $labelLastNameValue = New-Object System.Windows.Forms.Label
            $labelLastNameValue.Text = $user.Surname
            $labelLastNameValue.Location = New-Object System.Drawing.Point(120, 50)
            $labelLastNameValue.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelLastNameValue)

            $labelDescriptionValue = New-Object System.Windows.Forms.Label
            $labelDescriptionValue.Text = $user.Description
            $labelDescriptionValue.Location = New-Object System.Drawing.Point(120, 80)
            $labelDescriptionValue.Size = New-Object System.Drawing.Size(250, 20)
            $outputForm.Controls.Add($labelDescriptionValue)

            $labelAccountStatusValue = New-Object System.Windows.Forms.Label
            $labelAccountStatusValue.Text = ($(if ($user.Enabled) { "Enabled" } else { "Disabled" }))
            $labelAccountStatusValue.Location = New-Object System.Drawing.Point(120, 110)
            $labelAccountStatusValue.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelAccountStatusValue)

            $labelLockoutStatusValue = New-Object System.Windows.Forms.Label
            $labelLockoutStatusValue.Text = ($(if ($user.LockedOut) { "Locked" } else { "Unlocked" }))
            $labelLockoutStatusValue.Location = New-Object System.Drawing.Point(120, 140)
            $labelLockoutStatusValue.Size = New-Object System.Drawing.Size(100, 20)
            $outputForm.Controls.Add($labelLockoutStatusValue)

            $groupMemberships = $user.MemberOf | ForEach-Object {
                ($_ -split ",")[0] -replace '^CN=', ''
            }
            $groupMembershipsString = [string]::Join("`r`n", $groupMemberships)

            $textBoxGroupsValue = New-Object System.Windows.Forms.TextBox
            $textBoxGroupsValue.Multiline = $true
            $textBoxGroupsValue.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
            $textBoxGroupsValue.Location = New-Object System.Drawing.Point(120, 170)
            $textBoxGroupsValue.Size = New-Object System.Drawing.Size(250, 200)
            $textBoxGroupsValue.Text = $groupMembershipsString
            $textBoxGroupsValue.ReadOnly = $true
            $outputForm.Controls.Add($textBoxGroupsValue)

            $buttonExit = New-Object System.Windows.Forms.Button
            $buttonExit.Location = New-Object System.Drawing.Point(150, 400)
            $buttonExit.Size = New-Object System.Drawing.Size(75, 23)
            $buttonExit.Text = "Exit"
            $buttonExit.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $outputForm.AcceptButton = $buttonExit
            $outputForm.CancelButton = $buttonExit
            $outputForm.Controls.Add($buttonExit)

            $outputForm.ShowDialog() | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("User '$username' not found in Active Directory.", "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
}

# Show the main form
$form.ShowDialog() | Out-Null
