# GitLab Repository Importer - Windows Forms GUI
# Requires: PowerShell 5.1+, git

$DefaultGitLabUrl  = 'http://172.18.3.37'
$DefaultNamespace  = 'dataplane-admins/software-automation'
$DefaultToken      = 'YOUR_TOKEN_HERE'   # <-- paste your glpat-... token here

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

function Invoke-GitLabApi {
    param([string]$Method, [string]$ApiPath, [hashtable]$Body = @{},
          [string]$BaseUrl, [string]$Token)
    $uri     = "$($BaseUrl.TrimEnd('/'))/api/v4$ApiPath"
    $headers = @{ 'PRIVATE-TOKEN' = $Token }
    $params  = @{ Method = $Method; Uri = $uri; Headers = $headers }
    if ($Body.Count -gt 0) {
        $params['Body']        = ($Body | ConvertTo-Json -Depth 5)
        $params['ContentType'] = 'application/json'
    }
    Invoke-RestMethod @params
}

function Resolve-NamespaceId {
    param([string]$Ns, [string]$BaseUrl, [string]$Token)
    if ($Ns -match '^\d+$') { return [int]$Ns }
    $leaf = $Ns.Split('/')[-1]
    try {
        $r = Invoke-GitLabApi GET "/namespaces?search=$([Uri]::EscapeDataString($leaf))" -BaseUrl $BaseUrl -Token $Token
        $m = $r | Where-Object { $_.full_path -eq $Ns } | Select-Object -First 1
        if ($m) { return $m.id }
    } catch { }
    try {
        $r = Invoke-GitLabApi GET "/groups?search=$([Uri]::EscapeDataString($leaf))" -BaseUrl $BaseUrl -Token $Token
        $m = $r | Where-Object { $_.full_path -eq $Ns } | Select-Object -First 1
        if ($m) { return $m.id }
    } catch { }
    try {
        $encoded = $Ns -replace '/', '%2F'
        $uri     = "$($BaseUrl.TrimEnd('/'))/api/v4/groups/$encoded"
        $g = Invoke-WebRequest -Uri $uri -Headers @{ 'PRIVATE-TOKEN' = $Token } -UseBasicParsing | ConvertFrom-Json
        if ($g.id) { return $g.id }
    } catch { }
    return $null
}

# ---- UI construction --------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'GitLab Repository Importer'
$form.Size            = New-Object System.Drawing.Size(620, 640)
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
$lw  = 90
$tx  = $pad + $lw
$tw  = 466

# Zip File
$form.Controls.Add((New-Label 'Zip File' $pad 20 $lw))
$txtZip = New-TextBox $tx 18 380
$form.Controls.Add($txtZip)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(($tx + 386), 17)
$btnBrowse.Size     = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowse)

# Repo Name
$form.Controls.Add((New-Label 'Repo Name' $pad 58 $lw))
$txtRepoName = New-TextBox $tx 56 $tw
$form.Controls.Add($txtRepoName)

# GitLab URL
$form.Controls.Add((New-Label 'GitLab URL' $pad 96 $lw))
$txtUrl = New-TextBox $tx 94 $tw $DefaultGitLabUrl
$form.Controls.Add($txtUrl)

# Namespace
$form.Controls.Add((New-Label 'Namespace' $pad 134 $lw))
$txtNs = New-TextBox $tx 132 ($tw - 90) $DefaultNamespace
$form.Controls.Add($txtNs)
$nsHint = New-Object System.Windows.Forms.Label
$nsHint.Text      = '(path or numeric ID)'
$nsHint.Location  = New-Object System.Drawing.Point(($tx + $tw - 84), 136)
$nsHint.Size      = New-Object System.Drawing.Size(160, 16)
$nsHint.ForeColor = [System.Drawing.Color]::Gray
$nsHint.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$form.Controls.Add($nsHint)

# Token
$form.Controls.Add((New-Label 'Token' $pad 172 $lw))
$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Location     = New-Object System.Drawing.Point($tx, 170)
$txtToken.Size         = New-Object System.Drawing.Size($tw, 24)
$txtToken.PasswordChar = '*'
$txtToken.Text         = if ($env:GITLAB_TOKEN) { $env:GITLAB_TOKEN } else { $DefaultToken }
$form.Controls.Add($txtToken)

# Visibility + Import button + Test button
$form.Controls.Add((New-Label 'Visibility' $pad 210 $lw))
$cboVis = New-Object System.Windows.Forms.ComboBox
$cboVis.Location      = New-Object System.Drawing.Point($tx, 208)
$cboVis.Size          = New-Object System.Drawing.Size(120, 24)
$cboVis.DropDownStyle = 'DropDownList'
@('private','internal','public') | ForEach-Object { $cboVis.Items.Add($_) | Out-Null }
$cboVis.SelectedIndex = 0
$form.Controls.Add($cboVis)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text      = 'Test Connection'
$btnTest.Location  = New-Object System.Drawing.Point(($tx + 126), 206)
$btnTest.Size      = New-Object System.Drawing.Size(110, 28)
$btnTest.FlatStyle = 'Flat'
$form.Controls.Add($btnTest)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text      = 'Import'
$btnImport.Location  = New-Object System.Drawing.Point(($tx + 242), 206)
$btnImport.Size      = New-Object System.Drawing.Size(100, 28)
$btnImport.BackColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$btnImport.ForeColor = [System.Drawing.Color]::White
$btnImport.FlatStyle = 'Flat'
$form.Controls.Add($btnImport)

# Git Path
$form.Controls.Add((New-Label 'Git Path' $pad 248 $lw))
$txtGit = New-TextBox $tx 246 380 (Find-Git)
$form.Controls.Add($txtGit)
$btnGitBrowse = New-Object System.Windows.Forms.Button
$btnGitBrowse.Text     = 'Browse...'
$btnGitBrowse.Location = New-Object System.Drawing.Point(($tx + 386), 245)
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
$txtLog.Size       = New-Object System.Drawing.Size(570, 250)
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

function Update-RepoNameFromZip {
    param([string]$ZipPath)
    if (-not (Test-Path $ZipPath)) { return }
    try {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "scan_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
        $found = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if ($found) { $txtRepoName.Text = $found.Name -replace '\.git$', '' }
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    } catch { }
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select zip file containing repositories'
    $dlg.Filter = 'Zip files (*.zip)|*.zip|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtZip.Text = $dlg.FileName
        Update-RepoNameFromZip $dlg.FileName
    }
})

$btnGitBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Locate git.exe'
    $dlg.Filter = 'git.exe|git.exe|All executables (*.exe)|*.exe'
    if ($dlg.ShowDialog() -eq 'OK') { $txtGit.Text = $dlg.FileName }
})

$btnTest.Add_Click({
    $gitLabUrl = $txtUrl.Text.Trim()
    $token     = $txtToken.Text.Trim()
    if (-not $gitLabUrl -or -not $token) {
        [System.Windows.Forms.MessageBox]::Show('Enter GitLab URL and Token first.', 'Test Connection', 'OK', 'Warning') | Out-Null
        return
    }
    $txtLog.Clear()
    $lblStatus.Text = 'Testing connection...'
    [System.Windows.Forms.Application]::DoEvents()

    # Who am I?
    try {
        $me = Invoke-GitLabApi GET '/user' -BaseUrl $gitLabUrl -Token $token
        AppendLog "Authenticated as: $($me.username) (id=$($me.id))" ([System.Drawing.Color]::LightGreen)
    } catch {
        AppendLog "AUTH FAILED: $_" ([System.Drawing.Color]::Red)
        AppendLog 'Token is invalid or has no API access.' ([System.Drawing.Color]::Yellow)
        $lblStatus.Text = 'Connection failed.'
        return
    }

    # Namespaces
    try {
        $nsList = Invoke-GitLabApi GET '/namespaces' -BaseUrl $gitLabUrl -Token $token
        AppendLog "`nAccessible namespaces ($($nsList.Count)):" ([System.Drawing.Color]::Cyan)
        foreach ($n in $nsList) {
            AppendLog "  id=$($n.id)  kind=$($n.kind)  full_path=$($n.full_path)" ([System.Drawing.Color]::White)
        }
    } catch {
        AppendLog "`nCould not list namespaces: $_" ([System.Drawing.Color]::Yellow)
    }

    # Groups
    try {
        $grpList = Invoke-GitLabApi GET '/groups' -BaseUrl $gitLabUrl -Token $token
        AppendLog "`nAccessible groups ($($grpList.Count)):" ([System.Drawing.Color]::Cyan)
        foreach ($g in $grpList) {
            AppendLog "  id=$($g.id)  full_path=$($g.full_path)" ([System.Drawing.Color]::White)
        }
    } catch {
        AppendLog "`nCould not list groups: $_" ([System.Drawing.Color]::Yellow)
    }

    $lblStatus.Text = 'Connection test complete - see log.'
})

$btnImport.Add_Click({
    $zipFile    = $txtZip.Text.Trim()
    $repoName   = $txtRepoName.Text.Trim()
    $gitLabUrl  = $txtUrl.Text.Trim()
    $namespace  = $txtNs.Text.Trim()
    $token      = $txtToken.Text.Trim()
    $visibility = $cboVis.SelectedItem
    $gitExe     = $txtGit.Text.Trim()

    $errors = @()
    if (-not $zipFile)                             { $errors += 'Select a zip file.' }
    if (-not $repoName)                            { $errors += 'Enter a repo name.' }
    if (-not $gitLabUrl)                           { $errors += 'Enter the GitLab URL.' }
    if (-not $namespace)                           { $errors += 'Enter the namespace.' }
    if (-not $token)                               { $errors += 'Enter a GitLab token.' }
    if ($zipFile -and -not (Test-Path $zipFile))   { $errors += "Zip file not found: $zipFile" }
    if (-not $gitExe -or -not (Test-Path $gitExe)) { $errors += 'git.exe not found. Set the Git Path field.' }

    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(($errors -join "`n"), 'Validation Error', 'OK', 'Warning') | Out-Null
        return
    }

    $btnImport.Enabled = $false
    $btnTest.Enabled   = $false
    $txtLog.Clear()
    $progress.Value   = 0
    $progress.Maximum = 1
    $lblStatus.Text   = 'Starting...'

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "import_repos_$(Get-Random)"
    New-Item -ItemType Directory -Path $workDir | Out-Null

    try {
        AppendLog "Extracting $zipFile ..." ([System.Drawing.Color]::Cyan)
        $extractedRoot = Join-Path $workDir 'extracted'
        Expand-Archive -Path $zipFile -DestinationPath $extractedRoot -Force

        AppendLog "Resolving namespace '$namespace' ..." ([System.Drawing.Color]::Cyan)
        $nsId = Resolve-NamespaceId -Ns $namespace -BaseUrl $gitLabUrl -Token $token
        if (-not $nsId) {
            AppendLog "ERROR: Could not resolve namespace '$namespace'." ([System.Drawing.Color]::Red)
            AppendLog 'Use Test Connection to see available namespaces and their IDs.' ([System.Drawing.Color]::Yellow)
            $lblStatus.Text = 'Failed - namespace not found.'
            return
        }
        AppendLog "Namespace ID: $nsId" ([System.Drawing.Color]::Gray)

        $allDirs = @(Get-ChildItem -Path $extractedRoot -Directory)
        $dir = $allDirs | Where-Object {
            (Test-Path (Join-Path $_.FullName '.git')) -or
            ((Test-Path (Join-Path $_.FullName 'HEAD')) -and
             (Test-Path (Join-Path $_.FullName 'objects')) -and
             (Test-Path (Join-Path $_.FullName 'refs')))
        } | Select-Object -First 1

        $isWorkingTree = $false
        if (-not $dir) {
            $dir = $allDirs | Select-Object -First 1
            if (-not $dir) { $dir = [PSCustomObject]@{ FullName = $extractedRoot } }
            $isWorkingTree = $true
            AppendLog 'No git repo structure found - importing as new repo from source files.' ([System.Drawing.Color]::Yellow)
        }

        $isBare = (-not $isWorkingTree) -and (-not (Test-Path (Join-Path $dir.FullName '.git')))
        AppendLog "Importing as '$repoName' ..." ([System.Drawing.Color]::White)

        try {
            $project = Invoke-GitLabApi POST '/projects' -Body @{
                name                   = $repoName
                namespace_id           = $nsId
                visibility             = $visibility
                initialize_with_readme = $false
            } -BaseUrl $gitLabUrl -Token $token
        } catch {
            AppendLog "ERROR: Could not create project '$repoName': $_" ([System.Drawing.Color]::Red)
            AppendLog 'If error is "namespace is not valid", use Test Connection to find the correct namespace ID.' ([System.Drawing.Color]::Yellow)
            $lblStatus.Text = 'Failed - see log.'
            return
        }

        $pushUrl  = $project.http_url_to_repo -replace '://', "://oauth2:$token@"
        $cloneDir = Join-Path $workDir 'push_repo'

        if ($isWorkingTree) {
            New-Item -ItemType Directory -Path $cloneDir | Out-Null
            & $gitExe -C $cloneDir init -b main 2>&1 | Out-Null
            & $gitExe -C $cloneDir config user.email 'import@localhost' 2>&1 | Out-Null
            & $gitExe -C $cloneDir config user.name  'Importer' 2>&1 | Out-Null
            Copy-Item -Path (Join-Path $dir.FullName '*') -Destination $cloneDir -Recurse -Force
            & $gitExe -C $cloneDir add --all 2>&1 | Out-Null
            & $gitExe -C $cloneDir commit -m 'Initial import' 2>&1 | Out-Null
            $out = & $gitExe -C $cloneDir push $pushUrl main 2>&1
        } elseif ($isBare) {
            & $gitExe clone --bare   $dir.FullName $cloneDir -q 2>&1 | Out-Null
            $out = & $gitExe -C $cloneDir push --mirror $pushUrl 2>&1
        } else {
            & $gitExe clone --mirror $dir.FullName $cloneDir -q 2>&1 | Out-Null
            $out = & $gitExe -C $cloneDir push --mirror $pushUrl 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            $url = "$($gitLabUrl.TrimEnd('/'))/$namespace/$repoName"
            AppendLog "Done: $url" ([System.Drawing.Color]::LightGreen)
            $lblStatus.Text = "Done - imported as '$repoName'."
            $progress.Value = 1
        } else {
            AppendLog "ERROR: Push failed: $out" ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Import failed - see log.'
        }

        Remove-Item -Recurse -Force $cloneDir -ErrorAction SilentlyContinue

    } catch {
        AppendLog "FATAL: $_" ([System.Drawing.Color]::Red)
        $lblStatus.Text = 'Import failed - see log.'
    } finally {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
        $btnImport.Enabled = $true
        $btnTest.Enabled   = $true
    }
})

# ---- launch -----------------------------------------------------------------

[System.Windows.Forms.Application]::Run($form)
