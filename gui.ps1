# FK8 Video Tools: the window. It collects your choices, then hands the work to convert.ps1.
# If the window can't open for any reason, it falls back to the question-and-answer version.

param(
    [ValidateSet('startup', 'film')][string]$Mode = 'startup',
    [string]$InputFile
)

$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Engine   = Join-Path $Here 'convert.ps1'
$ToolsDir = Join-Path $Here 'tools'
$script:Proc = $null
$script:File = $null

function Find-Tool($name) {
    $local = Join-Path $ToolsDir "$name.exe"
    if (Test-Path $local) { return $local }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Runs convert.ps1 in its own black window so progress is visible.
function Start-Engine($arguments, [switch]$Wait) {
    $line = "-NoProfile -ExecutionPolicy Bypass -File `"$Engine`" -FromGui $arguments"
    if ($Wait) { return Start-Process powershell.exe -ArgumentList $line -Wait -PassThru }
    return Start-Process powershell.exe -ArgumentList $line -PassThru
}

function Start-Fallback {
    $line = "-NoProfile -ExecutionPolicy Bypass -File `"$Engine`" -Mode $Mode"
    if ($InputFile) { $line += " -InputFile `"$InputFile`"" }
    Start-Process powershell.exe -ArgumentList "-NoExit $line"
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # First run: fetch FFmpeg before showing the window.
    if (-not (Find-Tool 'ffmpeg') -or -not (Find-Tool 'ffprobe')) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "This tool needs FFmpeg, the free program that does the converting.`n`nIt will download now (about 200 MB). This only happens once.",
            'FK8 Video Tools', 'OKCancel', 'Information')
        if ($answer -ne 'OK') { exit 0 }
        Start-Engine '-InstallOnly' -Wait | Out-Null
        if (-not (Find-Tool 'ffmpeg') -or -not (Find-Tool 'ffprobe')) {
            [System.Windows.Forms.MessageBox]::Show("FFmpeg didn't download. Check your internet connection and try again.", 'FK8 Video Tools', 'OK', 'Error') | Out-Null
            exit 1
        }
    }
    $ffprobe = Find-Tool 'ffprobe'
    $ffplay  = Find-Tool 'ffplay'

    $font      = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontBold  = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'FK8 Video Tools'
    $form.ClientSize = New-Object System.Drawing.Size(520, 470)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.Font = $font
    $form.AllowDrop = $true

    function Add-Control($parent, $type, $text, $x, $y, $w, $h) {
        $c = New-Object "System.Windows.Forms.$type"
        if ($null -ne $text) { $c.Text = $text }
        $c.Location = New-Object System.Drawing.Point($x, $y)
        $c.Size = New-Object System.Drawing.Size($w, $h)
        $parent.Controls.Add($c)
        return $c
    }

    $title = Add-Control $form 'Label' 'FK8 Video Tools' 20 14 480 32
    $title.Font = $fontTitle

    # --- which tool
    $boxTool    = Add-Control $form 'GroupBox' 'What are you making?' 20 54 480 62
    $radStartup = Add-Control $boxTool 'RadioButton' 'Startup video' 16 26 200 26
    $radFilm    = Add-Control $boxTool 'RadioButton' 'Film for USB' 240 26 200 26

    # --- the file
    $btnChoose = Add-Control $form 'Button' 'Choose video...' 20 128 140 34
    $lblFile   = Add-Control $form 'Label' 'No video chosen yet. You can also drag one onto this window.' 172 128 328 34
    $lblFile.TextAlign = 'MiddleLeft'
    $lblFile.AutoEllipsis = $true

    # --- fit
    $boxFit  = Add-Control $form 'GroupBox' 'How should it fit the screen?' 20 174 480 62
    $radFill = Add-Control $boxFit 'RadioButton' 'Fill the screen' 16 26 200 26
    $radBars = Add-Control $boxFit 'RadioButton' 'Whole picture, black bars' 240 26 220 26

    # --- startup options
    $panStartup = Add-Control $form 'Panel' $null 20 246 480 110
    $l1 = Add-Control $panStartup 'Label' 'Start at (minutes:seconds)' 0 6 200 26
    $txtStart = Add-Control $panStartup 'TextBox' '0:00' 210 3 80 26
    $l2 = Add-Control $panStartup 'Label' 'Clip length (seconds)' 0 40 200 26
    $numLength = Add-Control $panStartup 'NumericUpDown' $null 210 37 80 26
    $numLength.Minimum = 3; $numLength.Maximum = 30; $numLength.Value = 20
    $chkSound = Add-Control $panStartup 'CheckBox' 'Keep the sound' 0 74 200 26
    $chkSound.Checked = $true
    $btnPreview = Add-Control $panStartup 'Button' 'Preview clip' 330 20 140 34
    if (-not $ffplay) { $btnPreview.Visible = $false }

    # --- film options
    $panFilm = Add-Control $form 'Panel' $null 20 246 480 110
    $l3 = Add-Control $panFilm 'Label' 'Soundtrack' 0 6 100 26
    $cmbAudio = Add-Control $panFilm 'ComboBox' $null 110 3 360 26
    $cmbAudio.DropDownStyle = 'DropDownList'
    $l4 = Add-Control $panFilm 'Label' 'A full film can take 20 minutes or more to convert. A black window shows the progress.' 0 44 470 44

    # --- go
    $btnGo = Add-Control $form 'Button' 'Convert' 20 368 480 44
    $btnGo.Font = $fontBold
    $lblStatus = Add-Control $form 'Label' '' 20 420 480 40

    function Update-Mode {
        $isStartup = $radStartup.Checked
        $panStartup.Visible = $isStartup
        $panFilm.Visible = -not $isStartup
        if ($isStartup) { $btnGo.Text = 'Make startup video' } else { $btnGo.Text = 'Convert film' }
    }

    function Set-File($path) {
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
        $script:File = $path
        $lblFile.Text = Split-Path $path -Leaf
        $lblStatus.Text = ''
        $cmbAudio.Items.Clear()
        try {
            $json = & $ffprobe -v error -print_format json -show_streams -select_streams a $path | Out-String
            $streams = @(($json | ConvertFrom-Json).streams)
            $pick = 0; $i = 0
            foreach ($s in $streams) {
                if (-not $s) { continue }
                $lang = $s.tags.language; if (-not $lang) { $lang = 'unknown language' }
                [void]$cmbAudio.Items.Add(("{0}.  {1}, {2}, {3} channels  {4}" -f ($i + 1), $lang, $s.codec_name, $s.channels, $s.tags.title))
                if ($lang -eq 'eng' -and $pick -eq 0) { $pick = $i }
                $i++
            }
            if ($cmbAudio.Items.Count -gt 0) { $cmbAudio.SelectedIndex = $pick } else { [void]$cmbAudio.Items.Add('No sound in this file'); $cmbAudio.SelectedIndex = 0 }
        } catch {
            [void]$cmbAudio.Items.Add('First soundtrack'); $cmbAudio.SelectedIndex = 0
        }
    }

    function Test-Start {
        if ($txtStart.Text.Trim() -match '^\d+(:\d{1,2}){0,2}(\.\d+)?$') { return $true }
        [System.Windows.Forms.MessageBox]::Show('Type the start time as minutes:seconds, like 1:30, or just seconds, like 90.', 'FK8 Video Tools', 'OK', 'Warning') | Out-Null
        return $false
    }

    $radStartup.Add_CheckedChanged({ if ($radStartup.Checked) { $radFill.Checked = $true }; Update-Mode })
    $radFilm.Add_CheckedChanged({ if ($radFilm.Checked) { $radBars.Checked = $true }; Update-Mode })

    $btnChoose.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Choose the video'
        $dialog.Filter = 'Video files|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v;*.wmv;*.ts;*.flv|All files|*.*'
        if ($dialog.ShowDialog() -eq 'OK') { Set-File $dialog.FileName }
    })

    $form.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } })
    $form.Add_DragDrop({ param($s, $e) $dropped = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop); if ($dropped) { Set-File $dropped[0] } })

    $btnPreview.Add_Click({
        if (-not $script:File) { $lblStatus.Text = 'Choose a video first.'; return }
        if (-not (Test-Start)) { return }
        $line = "-hide_banner -loglevel error -autoexit -window_title `"Preview (close this window when done)`" -x 848 -y 480 -ss $($txtStart.Text.Trim()) -t $([int]$numLength.Value)"
        if (-not $chkSound.Checked) { $line += ' -an' }
        Start-Process $ffplay -ArgumentList "$line `"$($script:File)`""
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Add_Tick({
        if ($script:Proc -and $script:Proc.HasExited) {
            $timer.Stop()
            $btnGo.Enabled = $true
            if ($script:Proc.ExitCode -eq 0) {
                $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
                $lblStatus.Text = 'Done. The new file is next to your original, and its folder has opened. Copy it to your USB stick.'
            } else {
                $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
                $lblStatus.Text = "That didn't work. The black window said why."
            }
            $script:Proc = $null
        }
    })

    $btnGo.Add_Click({
        if (-not $script:File) { $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick; $lblStatus.Text = 'Choose a video first.'; return }
        $fit = 'bars'; if ($radFill.Checked) { $fit = 'fill' }
        $arguments = "-InputFile `"$($script:File)`" -Fit $fit"
        if ($radStartup.Checked) {
            if (-not (Test-Start)) { return }
            $sound = 'no'; if ($chkSound.Checked) { $sound = 'yes' }
            $arguments += " -Mode startup -Start $($txtStart.Text.Trim()) -Length $([int]$numLength.Value) -Sound $sound"
        } else {
            $arguments += " -Mode film -AudioTrack $($cmbAudio.SelectedIndex + 1)"
        }
        $btnGo.Enabled = $false
        $lblStatus.ForeColor = [System.Drawing.Color]::Black
        $lblStatus.Text = 'Converting. Watch the black window for progress, and leave it open.'
        $script:Proc = Start-Engine $arguments
        $timer.Start()
    })

    if ($Mode -eq 'film') { $radFilm.Checked = $true } else { $radStartup.Checked = $true }
    Update-Mode
    if ($InputFile) { Set-File $InputFile }

    [void]$form.ShowDialog()
} catch {
    # The window failed. Use the plain question-and-answer version instead.
    try { [System.Windows.Forms.MessageBox]::Show("The window couldn't open, so the tool will ask its questions in a text window instead.`n`n$($_.Exception.Message)", 'FK8 Video Tools', 'OK', 'Warning') | Out-Null } catch { }
    Start-Fallback
}
