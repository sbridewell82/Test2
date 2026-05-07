# GitLab Repository Importer - Windows Forms GUI
# Requires: PowerShell 5.1+, git in PATH

$DefaultGitLabUrl  = 'http://172.18.3.37'
$DefaultNamespace  = 'a-e421760'
$DefaultToken      = 'YOUR_TOKEN_HERE'   # <-- paste your glpat-... token here

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- GitLab API helpers -----------------------------------------------------

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
    try {
        $g = Invoke-GitLabApi GET "/groups/$([Uri]::EscapeDataString($Ns))" -BaseUrl $BaseUrl -Token $Token
        if ($g.id) { return $g.id }
    } catch { }
    try {
        $u = Invoke-GitLabApi GET "/users?username=$([Uri]::EscapeDataString($Ns))" -BaseUrl $BaseUrl -Token $Token
        if ($u.Count -gt 0) { return $u[0].namespace_id }
    } catch { }
    return $null
}

# ---- UI construction --------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'GitLab Repository Importer'
$form.Size            = New-Object System.Drawing.Size(620, 600)
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
$lw  = 90   # label width
$tx  = $pad + $lw  # textbox x
$tw  = 466  # textbox width

# Row: Zip File
$form.Controls.Add((New-Label 'Zip File' $pad 20 $lw))
$txtZip = New-TextBox $tx 18 380
$form.Controls.Add($txtZip)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(($tx + 386), 17)
$btnBrowse.Size     = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowse)

# Row: Repo Name
$form.Controls.Add((New-Label 'Repo Name' $pad 58 $lw))
$txtRepoName = New-TextBox $tx 56 $tw
$form.Controls.Add($txtRepoName)

# Row: GitLab URL
$form.Controls.Add((New-Label 'GitLab URL' $pad 96 $lw))
$txtUrl = New-TextBox $tx 94 $tw $DefaultGitLabUrl
$form.Controls.Add($txtUrl)

# Row: Namespace
$form.Controls.Add((New-Label 'Namespace' $pad 134 $lw))
$txtNs = New-TextBox $tx 132 $tw $DefaultNamespace
$form.Controls.Add($txtNs)

# Row: Token
$form.Controls.Add((New-Label 'Token' $pad 172 $lw))
$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Location     = New-Object System.Drawing.Point($tx, 170)
$txtToken.Size         = New-Object System.Drawing.Size($tw, 24)
$txtToken.PasswordChar = '*'
$txtToken.Text         = if ($env:GITLAB_TOKEN) { $env:GITLAB_TOKEN } else { $DefaultToken }
$form.Controls.Add($txtToken)

# Row: Visibility + Import button
$form.Controls.Add((New-Label 'Visibility' $pad 210 $lw))
$cboVis = New-Object System.Windows.Forms.ComboBox
$cboVis.Location      = New-Object System.Drawing.Point($tx, 208)
$cboVis.Size          = New-Object System.Drawing.Size(140, 24)
$cboVis.DropDownStyle = 'DropDownList'
@('private','internal','public') | ForEach-Object { $cboVis.Items.Add($_) | Out-Null }
$cboVis.SelectedIndex = 0
$form.Controls.Add($cboVis)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text      = 'Import'
$btnImport.Location  = New-Object System.Drawing.Point(($tx + 146), 206)
$btnImport.Size      = New-Object System.Drawing.Size(100, 28)
$btnImport.BackColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$btnImport.ForeColor = [System.Drawing.Color]::White
$btnImport.FlatStyle = 'Flat'
$form.Controls.Add($btnImport)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point($pad, 250)
$progress.Size     = New-Object System.Drawing.Size(570, 18)
$progress.Style    = 'Continuous'
$form.Controls.Add($progress)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point($pad, 272)
$lblStatus.Size     = New-Object System.Drawing.Size(570, 20)
$lblStatus.Text     = 'Ready.'
$form.Controls.Add($lblStatus)

# Log output
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point($pad, 296)
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

# When a zip is selected, pre-fill Repo Name from the first repo found inside
function Update-RepoNameFromZip {
    param([string]$ZipPath)
    if (-not (Test-Path $ZipPath)) { return }
    try {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "scan_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
        $found = Get-ChildItem -Path $tmpDir -Directory -Depth 1 | Where-Object {
            (Test-Path (Join-Path $_.FullName '.git')) -or
            ((Test-Path (Join-Path $_.FullName 'HEAD')) -and
             (Test-Path (Join-Path $_.FullName 'objects')))
        } | Select-Object -First 1
        if ($found) {
            $txtRepoName.Text = $found.Name -replace '\.git$', ''
        }
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

$btnImport.Add_Click({
    $zipFile    = $txtZip.Text.Trim()
    $repoName   = $txtRepoName.Text.Trim()
    $gitLabUrl  = $txtUrl.Text.Trim()
    $namespace  = $txtNs.Text.Trim()
    $token      = $txtToken.Text.Trim()
    $visibility = $cboVis.SelectedItem

    $errors = @()
    if (-not $zipFile)                                        { $errors += 'Select a zip file.' }
    if (-not $repoName)                                       { $errors += 'Enter a repo name.' }
    if (-not $gitLabUrl)                                      { $errors += 'Enter the GitLab URL.' }
    if (-not $namespace)                                      { $errors += 'Enter the namespace.' }
    if (-not $token)                                          { $errors += 'Enter a GitLab token.' }
    if ($zipFile -and -not (Test-Path $zipFile))              { $errors += "Zip file not found: $zipFile" }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $errors += 'git not found in PATH.' }

    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(($errors -join "`n"), 'Validation Error',
            'OK', 'Warning') | Out-Null
        return
    }

    $btnImport.Enabled = $false
    $txtLog.Clear()
    $progress.Value   = 0
    $progress.Maximum = 1
    $lblStatus.Text   = 'Starting...'

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "import_repos_$(Get-Random)"
    New-Item -ItemType Directory -Path $workDir | Out-Null

    try {
        AppendLog "Extracting $zipFile ..." ([System.Drawing.Color]::Cyan)
        Expand-Archive -Path $zipFile -DestinationPath (Join-Path $workDir 'extracted') -Force

        AppendLog "Resolving namespace '$namespace' ..." ([System.Drawing.Color]::Cyan)
        $nsId = Resolve-NamespaceId -Ns $namespace -BaseUrl $gitLabUrl -Token $token
        if (-not $nsId) {
            AppendLog "ERROR: Could not resolve namespace '$namespace'." ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Failed - namespace not found.'
            return
        }
        AppendLog "Namespace ID: $nsId" ([System.Drawing.Color]::Gray)

        $extractedRoot = Join-Path $workDir 'extracted'
        $dir = Get-ChildItem -Path $extractedRoot -Directory -Depth 1 | Where-Object {
            (Test-Path (Join-Path $_.FullName '.git')) -or
            ((Test-Path (Join-Path $_.FullName 'HEAD')) -and
             (Test-Path (Join-Path $_.FullName 'objects')) -and
             (Test-Path (Join-Path $_.FullName 'refs')))
        } | Select-Object -First 1

        if (-not $dir) {
            AppendLog 'No git repository found in the zip.' ([System.Drawing.Color]::Yellow)
            $lblStatus.Text = 'Done - no repo found.'
            return
        }

        $isBare = (-not (Test-Path (Join-Path $dir.FullName '.git')))
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
            $lblStatus.Text = 'Failed - see log.'
            return
        }

        $pushUrl  = $project.http_url_to_repo -replace '://', "://oauth2:$token@"
        $cloneDir = Join-Path $workDir 'push_repo'

        if ($isBare) {
            git clone --bare   $dir.FullName $cloneDir -q 2>&1 | Out-Null
        } else {
            git clone --mirror $dir.FullName $cloneDir -q 2>&1 | Out-Null
        }

        $out = git -C $cloneDir push --mirror $pushUrl 2>&1
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
    }
})

# ---- launch -----------------------------------------------------------------

[System.Windows.Forms.Application]::Run($form)
