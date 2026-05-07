# GitLab Repository Importer - Windows Forms GUI
# Adds zip contents as a new subfolder in an existing GitLab project.
# Requires: PowerShell 5.1+, git

$DefaultGitLabUrl   = 'http://172.18.3.37'
$DefaultProjectPath = 'dataplane-admins/software-automation'
$DefaultToken       = 'YOUR_TOKEN_HERE'   # <-- paste your token here

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- helpers ----------------------------------------------------------------

function Find-Git {
    $inPath = Get-Command git -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    $candidates = @(
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files\Git\bin\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe',
        'C:\Program Files (x86)\Git\bin\git.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return ''
}

# ---- UI construction --------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'GitLab Repository Importer'
$form.Size            = New-Object System.Drawing.Size(620, 580)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 100)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.Size      = New-Object System.Drawing.Size($W, 20)
    $l.TextAlign = 'MiddleLeft'
    $l
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 380, [string]$Default = '')
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location  = New-Object System.Drawing.Point($X, $Y)
    $t.Size      = New-Object System.Drawing.Size($W, 24)
    $t.Text      = $Default
    $t.ForeColor = [System.Drawing.Color]::Black
    $t
}

$pad = 16
$lw  = 100
$tx  = $pad + $lw
$tw  = 466

# Zip File
$form.Controls.Add((New-Label 'Zip File' $pad 20 $lw))
$txtZip = New-TextBox $tx 18 370
$form.Controls.Add($txtZip)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(($tx + 376), 17)
$btnBrowse.Size     = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowse)

# Folder Name
$form.Controls.Add((New-Label 'Folder Name' $pad 58 $lw))
$txtFolderName = New-TextBox $tx 56 $tw
$form.Controls.Add($txtFolderName)

# GitLab URL
$form.Controls.Add((New-Label 'GitLab URL' $pad 96 $lw))
$txtUrl = New-TextBox $tx 94 $tw $DefaultGitLabUrl
$form.Controls.Add($txtUrl)

# Project Path
$form.Controls.Add((New-Label 'Project Path' $pad 134 $lw))
$txtProject = New-TextBox $tx 132 $tw $DefaultProjectPath
$form.Controls.Add($txtProject)

# Token
$form.Controls.Add((New-Label 'Token' $pad 172 $lw))
$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Location     = New-Object System.Drawing.Point($tx, 170)
$txtToken.Size         = New-Object System.Drawing.Size($tw, 24)
$txtToken.PasswordChar = '*'
$txtToken.Text         = if ($env:GITLAB_TOKEN) { $env:GITLAB_TOKEN } else { $DefaultToken }
$form.Controls.Add($txtToken)

# Import button
$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text      = 'Import'
$btnImport.Location  = New-Object System.Drawing.Point($tx, 208)
$btnImport.Size      = New-Object System.Drawing.Size(100, 28)
$btnImport.BackColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$btnImport.ForeColor = [System.Drawing.Color]::White
$btnImport.FlatStyle = 'Flat'
$form.Controls.Add($btnImport)

# Git Path
$form.Controls.Add((New-Label 'Git Path' $pad 248 $lw))
$txtGit = New-TextBox $tx 246 370 (Find-Git)
$form.Controls.Add($txtGit)
$btnGitBrowse = New-Object System.Windows.Forms.Button
$btnGitBrowse.Text     = 'Browse...'
$btnGitBrowse.Location = New-Object System.Drawing.Point(($tx + 376), 245)
$btnGitBrowse.Size     = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnGitBrowse)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point($pad, 288)
$progress.Size     = New-Object System.Drawing.Size(570, 18)
$progress.Style    = 'Continuous'
$form.Controls.Add($progress)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point($pad, 310)
$lblStatus.Size     = New-Object System.Drawing.Size(570, 20)
$lblStatus.Text     = 'Ready.'
$form.Controls.Add($lblStatus)

# Log output
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point($pad, 334)
$txtLog.Size       = New-Object System.Drawing.Size(570, 196)
$txtLog.ReadOnly   = $true
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor  = [System.Drawing.Color]::White
$txtLog.Font       = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.ScrollBars = 'Vertical'
$form.Controls.Add($txtLog)

# ---- event handlers ---------------------------------------------------------

function AppendLog {
    param([string]$Text, [System.Drawing.Color]$Color)
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor  = $Color
    $txtLog.AppendText("$Text`n")
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-FolderNameFromZip {
    param([string]$ZipPath)
    if (-not (Test-Path $ZipPath)) { return }
    try {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "scan_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
        $found = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if ($found) { $txtFolderName.Text = $found.Name -replace '\.git$', '' }
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    } catch { }
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select zip file'
    $dlg.Filter = 'Zip files (*.zip)|*.zip|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtZip.Text = $dlg.FileName
        Update-FolderNameFromZip $dlg.FileName
    }
})

$btnGitBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Locate git.exe'
    $dlg.Filter = 'git.exe|git.exe|All executables (*.exe)|*.exe'
    if ($dlg.ShowDialog() -eq 'OK') { $txtGit.Text = $dlg.FileName }
})

$btnImport.Add_Click({
    $zipFile     = $txtZip.Text.Trim()
    $folderName  = $txtFolderName.Text.Trim()
    $gitLabUrl   = $txtUrl.Text.Trim()
    $projectPath = $txtProject.Text.Trim()
    $token       = $txtToken.Text.Trim()
    $gitExe      = $txtGit.Text.Trim()

    $errors = @()
    if (-not $zipFile)                             { $errors += 'Select a zip file.' }
    if (-not $folderName)                          { $errors += 'Enter a folder name.' }
    if (-not $gitLabUrl)                           { $errors += 'Enter the GitLab URL.' }
    if (-not $projectPath)                         { $errors += 'Enter the project path.' }
    if (-not $token)                               { $errors += 'Enter a GitLab token.' }
    if ($zipFile -and -not (Test-Path $zipFile))   { $errors += "Zip file not found: $zipFile" }
    if (-not $gitExe -or -not (Test-Path $gitExe)) { $errors += 'git.exe not found. Set the Git Path field.' }

    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(($errors -join "`n"), 'Validation Error', 'OK', 'Warning') | Out-Null
        return
    }

    $btnImport.Enabled = $false
    $txtLog.Clear()
    $progress.Value   = 0
    $progress.Maximum = 3
    $lblStatus.Text   = 'Starting...'

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "import_repos_$(Get-Random)"
    New-Item -ItemType Directory -Path $workDir | Out-Null

    try {
        # Extract zip
        AppendLog "Extracting $zipFile ..." ([System.Drawing.Color]::Cyan)
        $extractedRoot = Join-Path $workDir 'extracted'
        Expand-Archive -Path $zipFile -DestinationPath $extractedRoot -Force
        $progress.Value = 1

        # Find the source folder inside the zip
        $srcDir = Get-ChildItem -Path $extractedRoot -Directory | Select-Object -First 1
        $srcPath = if ($srcDir) { $srcDir.FullName } else { $extractedRoot }

        # Clone the target project
        $cloneUrl = "$($gitLabUrl.TrimEnd('/'))/" + $projectPath + '.git'
        $authUrl  = $cloneUrl -replace '://', "://oauth2:$token@"
        $cloneDir = Join-Path $workDir 'repo'

        AppendLog "Cloning $cloneUrl ..." ([System.Drawing.Color]::Cyan)
        $cloneOut = & $gitExe clone $authUrl $cloneDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            AppendLog "ERROR: Clone failed: $cloneOut" ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Failed - clone error.'
            return
        }
        $progress.Value = 2

        # Check folder doesn't already exist
        $destFolder = Join-Path $cloneDir $folderName
        if (Test-Path $destFolder) {
            AppendLog "ERROR: Folder '$folderName' already exists in the project." ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Failed - folder already exists.'
            return
        }

        # Copy files into new subfolder
        AppendLog "Copying files into '$folderName' ..." ([System.Drawing.Color]::White)
        New-Item -ItemType Directory -Path $destFolder | Out-Null
        Copy-Item -Path (Join-Path $srcPath '*') -Destination $destFolder -Recurse -Force

        # Commit and push
        & $gitExe -C $cloneDir config user.email 'import@localhost' 2>&1 | Out-Null
        & $gitExe -C $cloneDir config user.name  'Importer' 2>&1 | Out-Null
        & $gitExe -C $cloneDir add --all 2>&1 | Out-Null
        & $gitExe -C $cloneDir commit -m "Add $folderName" 2>&1 | Out-Null

        AppendLog 'Pushing ...' ([System.Drawing.Color]::Cyan)
        $pushOut = & $gitExe -C $cloneDir push $authUrl 2>&1
        if ($LASTEXITCODE -eq 0) {
            $url = "$($gitLabUrl.TrimEnd('/'))/$projectPath"
            AppendLog "Done: $url" ([System.Drawing.Color]::LightGreen)
            $lblStatus.Text = "Done - '$folderName' added to $projectPath."
            $progress.Value = 3
        } else {
            AppendLog "ERROR: Push failed: $pushOut" ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Import failed - see log.'
        }

    } catch {
        AppendLog "FATAL: $_" ([System.Drawing.Color]::Red)
        $lblStatus.Text = 'Import failed - see log.'
    } finally {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
        $btnImport.Enabled = $true
    }
})

# ---- launch -----------------------------------------------------------------

[System.Windows.Forms.Application]::Run($form)
