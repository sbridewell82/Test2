# GitLab Repository Importer — Windows Forms GUI
# Requires: PowerShell 5.1+, git in PATH

$DefaultGitLabUrl  = 'http://172.18.3.37'
$DefaultNamespace  = 'a-e421760'
$DefaultToken      = 'YOUR_TOKEN_HERE'   # <-- paste your glpat-... token here

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── GitLab API helpers (shared with CLI script) ───────────────────────────────

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

function New-GitLabProject {
    param([string]$Name, [int]$NamespaceId, [string]$BaseUrl, [string]$Token)
    Invoke-GitLabApi POST '/projects' -Body @{
        name                   = $Name
        namespace_id           = $NamespaceId
        visibility             = 'private'
        initialize_with_readme = $false
    } -BaseUrl $BaseUrl -Token $Token
}

# ── UI construction ───────────────────────────────────────────────────────────

$form = New-Object System.Windows.Forms.Form
$form.Text          = 'GitLab Repository Importer'
$form.Size          = New-Object System.Drawing.Size(620, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox   = $false
$form.Font          = New-Object System.Drawing.Font('Segoe UI', 9)

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 100)
    $l = New-Object System.Windows.Forms.Label
    $l.Text     = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size     = New-Object System.Drawing.Size($W, 20)
    $l.TextAlign = 'MiddleLeft'
    $l
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 380, [string]$PlaceHolder = '')
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location    = New-Object System.Drawing.Point($X, $Y)
    $t.Size        = New-Object System.Drawing.Size($W, 24)
    $t.Text        = $PlaceHolder
    $t.ForeColor   = [System.Drawing.Color]::Black
    $t.Tag = $PlaceHolder
    $t
}

$pad = 16

# Zip file row
$form.Controls.Add((New-Label 'Zip File' $pad 20 80))
$txtZip = New-TextBox ($pad + 84) 18 380
$form.Controls.Add($txtZip)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse…'
$btnBrowse.Location = New-Object System.Drawing.Point(($pad + 84 + 386), 17)
$btnBrowse.Size     = New-Object System.Drawing.Size(80, 26)
$form.Controls.Add($btnBrowse)

# GitLab URL row
$form.Controls.Add((New-Label 'GitLab URL' $pad 58 80))
$txtUrl = New-TextBox ($pad + 84) 56 466 $DefaultGitLabUrl
$form.Controls.Add($txtUrl)

# Namespace row
$form.Controls.Add((New-Label 'Namespace' $pad 96 80))
$txtNs = New-TextBox ($pad + 84) 94 466 $DefaultNamespace
$form.Controls.Add($txtNs)

# Token row
$form.Controls.Add((New-Label 'Token' $pad 134 80))
$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Location     = New-Object System.Drawing.Point(($pad + 84), 132)
$txtToken.Size         = New-Object System.Drawing.Size(466, 24)
$txtToken.PasswordChar = '*'
$txtToken.Text         = if ($env:GITLAB_TOKEN) { $env:GITLAB_TOKEN } else { $DefaultToken }
$form.Controls.Add($txtToken)

# Visibility selector
$form.Controls.Add((New-Label 'Visibility' $pad 172 80))
$cboVis = New-Object System.Windows.Forms.ComboBox
$cboVis.Location      = New-Object System.Drawing.Point(($pad + 84), 170)
$cboVis.Size          = New-Object System.Drawing.Size(140, 24)
$cboVis.DropDownStyle = 'DropDownList'
@('private','internal','public') | ForEach-Object { $cboVis.Items.Add($_) | Out-Null }
$cboVis.SelectedIndex = 0
$form.Controls.Add($cboVis)

# Import button
$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text     = 'Import'
$btnImport.Location = New-Object System.Drawing.Point(($pad + 84 + 146), 168)
$btnImport.Size     = New-Object System.Drawing.Size(100, 28)
$btnImport.BackColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$btnImport.ForeColor = [System.Drawing.Color]::White
$btnImport.FlatStyle = 'Flat'
$form.Controls.Add($btnImport)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point($pad, 210)
$progress.Size     = New-Object System.Drawing.Size(570, 18)
$progress.Style    = 'Continuous'
$form.Controls.Add($progress)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point($pad, 232)
$lblStatus.Size     = New-Object System.Drawing.Size(570, 20)
$lblStatus.Text     = 'Ready.'
$form.Controls.Add($lblStatus)

# Log output
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point($pad, 256)
$txtLog.Size       = New-Object System.Drawing.Size(570, 240)
$txtLog.ReadOnly   = $true
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor  = [System.Drawing.Color]::White
$txtLog.Font       = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.ScrollBars = 'Vertical'
$form.Controls.Add($txtLog)

# ── event handlers ────────────────────────────────────────────────────────────

function AppendLog {
    param([string]$Text, [System.Drawing.Color]$Color)
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor  = $Color
    $txtLog.AppendText("$Text`n")
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select zip file containing repositories'
    $dlg.Filter = 'Zip files (*.zip)|*.zip|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtZip.Text      = $dlg.FileName
        $txtZip.ForeColor = [System.Drawing.Color]::Black
    }
})

$btnImport.Add_Click({
    $zipFile   = $txtZip.Text.Trim()
    $gitLabUrl = $txtUrl.Text.Trim()
    $namespace = $txtNs.Text.Trim()
    $token     = $txtToken.Text.Trim()
    $visibility = $cboVis.SelectedItem

    # Basic validation
    $errors = @()
    if (-not $zipFile -or $zipFile -eq $txtZip.Tag)  { $errors += 'Select a zip file.' }
    if (-not $gitLabUrl -or $gitLabUrl -eq $txtUrl.Tag) { $errors += 'Enter the GitLab URL.' }
    if (-not $namespace -or $namespace -eq $txtNs.Tag)  { $errors += 'Enter the namespace.' }
    if (-not $token)                                      { $errors += 'Enter a GitLab token.' }
    if (-not (Test-Path $zipFile))                        { $errors += "Zip file not found: $zipFile" }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $errors += 'git not found in PATH.' }

    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(($errors -join "`n"), 'Validation Error',
            'OK', 'Warning') | Out-Null
        return
    }

    $btnImport.Enabled = $false
    $txtLog.Clear()
    $progress.Value = 0
    $lblStatus.Text = 'Starting...'

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "import_repos_$(Get-Random)"
    New-Item -ItemType Directory -Path $workDir | Out-Null

    try {
        AppendLog "Extracting $zipFile ..." ([System.Drawing.Color]::Cyan)
        Expand-Archive -Path $zipFile -DestinationPath (Join-Path $workDir 'extracted') -Force

        AppendLog "Resolving namespace '$namespace' ..." ([System.Drawing.Color]::Cyan)
        $nsId = Resolve-NamespaceId -Ns $namespace -BaseUrl $gitLabUrl -Token $token
        if (-not $nsId) {
            AppendLog "ERROR: Could not resolve namespace '$namespace'." ([System.Drawing.Color]::Red)
            $lblStatus.Text = 'Failed — namespace not found.'
            return
        }
        AppendLog "Namespace ID: $nsId" ([System.Drawing.Color]::Gray)

        $extractedRoot = Join-Path $workDir 'extracted'
        $candidates    = @(Get-ChildItem -Path $extractedRoot -Directory -Depth 1)
        $repos         = @($candidates | Where-Object {
            (Test-Path (Join-Path $_.FullName '.git')) -or
            ((Test-Path (Join-Path $_.FullName 'HEAD')) -and
             (Test-Path (Join-Path $_.FullName 'objects')) -and
             (Test-Path (Join-Path $_.FullName 'refs')))
        })

        if ($repos.Count -eq 0) {
            AppendLog 'No git repositories found in the zip.' ([System.Drawing.Color]::Yellow)
            $lblStatus.Text = 'Done — no repos found.'
            return
        }

        $progress.Maximum = $repos.Count
        $succeeded = 0; $failed = 0; $i = 0

        foreach ($dir in $repos) {
            $i++
            $isBare    = (-not (Test-Path (Join-Path $dir.FullName '.git')))
            $repoName  = $dir.Name -replace '\.git$', ''
            $lblStatus.Text = "[$i/$($repos.Count)] Importing '$repoName'..."
            AppendLog "[$i/$($repos.Count)] $repoName" ([System.Drawing.Color]::White)

            try {
                $project = Invoke-GitLabApi POST '/projects' -Body @{
                    name                   = $repoName
                    namespace_id           = $nsId
                    visibility             = $visibility
                    initialize_with_readme = $false
                } -BaseUrl $gitLabUrl -Token $token
            } catch {
                AppendLog "  x Create failed: $_" ([System.Drawing.Color]::Red)
                $failed++
                $progress.Value = $i
                continue
            }

            $pushUrl  = $project.http_url_to_repo -replace '://', "://oauth2:$token@"
            $cloneDir = Join-Path $workDir "push_$repoName"

            if ($isBare) {
                git clone --bare   $dir.FullName $cloneDir -q 2>&1 | Out-Null
            } else {
                git clone --mirror $dir.FullName $cloneDir -q 2>&1 | Out-Null
            }

            $out = git -C $cloneDir push --mirror $pushUrl 2>&1
            if ($LASTEXITCODE -eq 0) {
                AppendLog "  v $($gitLabUrl.TrimEnd('/'))/$namespace/$repoName" ([System.Drawing.Color]::LightGreen)
                $succeeded++
            } else {
                AppendLog "  x Push failed: $out" ([System.Drawing.Color]::Red)
                $failed++
            }

            Remove-Item -Recurse -Force $cloneDir -ErrorAction SilentlyContinue
            $progress.Value = $i
        }

        $summary = "Done — $succeeded succeeded, $failed failed."
        AppendLog $summary ([System.Drawing.Color]::Cyan)
        $lblStatus.Text = $summary

    } catch {
        AppendLog "FATAL: $_" ([System.Drawing.Color]::Red)
        $lblStatus.Text = 'Import failed — see log.'
    } finally {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
        $btnImport.Enabled = $true
    }
})

# ── launch ────────────────────────────────────────────────────────────────────

[System.Windows.Forms.Application]::Run($form)
