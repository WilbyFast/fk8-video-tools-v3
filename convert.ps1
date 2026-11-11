# FK8 Video Converter
# Converts any video into a file the Honda Display Audio head unit will play
# (10th gen Civic / FK8 Type R, Android 4.2.2, 800x480 screen).
# Works on Windows PowerShell 5.1 and later. "Make Startup Video.bat" and "Convert Film.bat" open a window
# (gui.ps1) that runs this script. Run this script on its own for a question-and-answer version.
# It only converts files you already have. It does not download anything except FFmpeg itself,
# and it cannot open copy-protected (DRM) files.

param(
    [string]$InputFile,
    [ValidateSet('ask', 'startup', 'film')][string]$Mode = 'ask',
    # Everything below is filled in by the window (gui.ps1). Leave them out and the tool asks instead.
    [ValidateSet('', 'fill', 'bars')][string]$Fit = '',
    [string]$Start = '',
    [string]$Length = '',
    [ValidateSet('', 'yes', 'no')][string]$Sound = '',
    [int]$AudioTrack = 0,
    [switch]$InstallOnly,
    [switch]$FromGui
)

# ---------------------------------------------------------------------------
# SETTINGS. Change these if your unit behaves differently.
# ---------------------------------------------------------------------------
$ScreenWidth     = 800      # head unit screen, pixels
$ScreenHeight    = 480
$StartupWidth    = 848      # startup clips: 16:9, the shape Honda Hack's own clips use
$StartupHeight   = 480
$StartupSeconds  = 20       # default startup clip length
$StartupMaxSecs  = 30       # longest startup clip the tool will make
$StartupBitrate  = 9500     # kbps, MPEG-4. Matches the clips proven on the car
$FilmQuality     = 20       # CRF for films. Lower = better picture, bigger file
$FilmMaxBitrate  = 3000     # kbps ceiling for films
$AudioBitrate    = 160      # kbps, stereo AAC
$Fat32LimitBytes = 3700000000   # keep files safely under FAT32's 4 GB limit
$FfmpegUrl       = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir  = Join-Path $Here 'tools'

function Say($text, $colour = 'Gray') { Write-Host $text -ForegroundColor $colour }

function Ask($question, $default) {
    $answer = Read-Host "$question [$default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return "$default" }
    return $answer.Trim()
}

# When the window started us, keep this black window open on failure so the message can be read.
function Finish($code) {
    if ($FromGui -and $code -ne 0) { Read-Host 'Press Enter to close this window' | Out-Null }
    exit $code
}

# Downloads a file and shows how far it has got, so a big download doesn't look frozen.
function Get-FileWithProgress($url, $dest) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request  = [Net.HttpWebRequest]::Create($url)
    $request.UserAgent = 'fk8-video-tools'
    $response = $request.GetResponse()
    $total    = $response.ContentLength
    $in       = $response.GetResponseStream()
    $out      = [IO.File]::Create($dest)
    try {
        $buffer = New-Object byte[] 1048576
        $done = 0; $lastShown = -1
        while (($read = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $out.Write($buffer, 0, $read)
            $done += $read
            $mb = [int]($done / 1MB)
            if ($mb -ne $lastShown -and ($mb % 5) -eq 0) {
                $lastShown = $mb
                if ($total -gt 0) {
                    Write-Host ("`r  {0,3}%   {1} of {2} MB   " -f [int](100 * $done / $total), $mb, [int]($total / 1MB)) -NoNewline
                } else {
                    Write-Host ("`r  {0} MB   " -f $mb) -NoNewline
                }
            }
        }
        Write-Host "`r  100%   finished downloading        "
    } finally {
        $out.Close(); $in.Close(); $response.Close()
    }
}

function Find-Tool($name) {
    $exe = $name
    if ($OnWindows) { $exe = "$name.exe" }
    $local = Join-Path $ToolsDir $exe
    if (Test-Path $local) { return $local }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-Ffmpeg {
    if (-not $OnWindows) {
        throw "FFmpeg isn't installed. On a Mac run: brew install ffmpeg"
    }
    Say ''
    Say 'FFmpeg (the free tool that does the converting) is not on this PC yet.' Yellow
    Say 'Downloading it now. About 200 MB, and it only happens once. Leave this window open.' Yellow
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zip     = Join-Path $ToolsDir 'ffmpeg.zip'
    $unpack  = Join-Path $ToolsDir 'unpack'
    Get-FileWithProgress $FfmpegUrl $zip
    Say 'Unpacking...'
    if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $unpack -Force
    foreach ($exe in 'ffmpeg.exe', 'ffprobe.exe') {
        $found = Get-ChildItem -Path $unpack -Recurse -Filter $exe | Select-Object -First 1
        if (-not $found) { throw "Couldn't find $exe in the download." }
        Copy-Item $found.FullName (Join-Path $ToolsDir $exe) -Force
    }
    # ffplay is only used for the Preview button in the window, so it is optional.
    $player = Get-ChildItem -Path $unpack -Recurse -Filter 'ffplay.exe' | Select-Object -First 1
    if ($player) { Copy-Item $player.FullName (Join-Path $ToolsDir 'ffplay.exe') -Force }
    Remove-Item $unpack -Recurse -Force
    Remove-Item $zip -Force
    Say 'FFmpeg is ready.' Green
}

function Pick-File {
    if ($OnWindows) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title  = 'Choose the video to convert'
            $dialog.Filter = 'Video files|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v;*.wmv;*.ts;*.flv|All files|*.*'
            if ($dialog.ShowDialog() -eq 'OK') { return $dialog.FileName }
            return $null
        } catch { }
    }
    $typed = Read-Host 'Drag the video into this window (or type its path), then press Enter'
    if ([string]::IsNullOrWhiteSpace($typed)) { return $null }
    return $typed.Trim().Trim('"').Trim("'")
}

function Get-Fps($rate) {
    if (-not $rate) { return 0 }
    $parts = "$rate".Split('/')
    if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0) { return [double]$parts[0] / [double]$parts[1] }
    return [double]$parts[0]
}

# Any unexpected error: say what happened in plain words and stop, instead of vanishing.
trap {
    Say ''
    Say "Something went wrong: $($_.Exception.Message)" Red
    Finish 1
}

# ---------------------------------------------------------------------------
Say ''
$banner = 'FK8 VIDEO TOOLS'
if ($Mode -eq 'startup') { $banner = 'FK8 STARTUP VIDEO MAKER' }
if ($Mode -eq 'film') { $banner = 'FK8 FILM CONVERTER' }
Say "  $banner" White
Say '  For the 10th gen Civic 7 inch head unit'
Say ''

$ffmpeg  = Find-Tool 'ffmpeg'
$ffprobe = Find-Tool 'ffprobe'
if (-not $ffmpeg -or -not $ffprobe) {
    Install-Ffmpeg
    $ffmpeg  = Find-Tool 'ffmpeg'
    $ffprobe = Find-Tool 'ffprobe'
}

if ($InstallOnly) { Finish 0 }

if (-not $InputFile) { $InputFile = Pick-File }
if (-not $InputFile) { Say 'No video chosen. Nothing to do.' Yellow; Finish 1 }
if (-not (Test-Path -LiteralPath $InputFile)) { Say "Can't find: $InputFile" Red; Finish 1 }
$InputFile = (Resolve-Path -LiteralPath $InputFile).Path

# Read the source so we can make sensible choices.
$probeJson = & $ffprobe -v error -print_format json -show_format -show_streams $InputFile | Out-String
if ($LASTEXITCODE -ne 0 -or -not $probeJson.Trim()) { Say "That file doesn't look like a video FFmpeg can read." Red; Finish 1 }
$probe = $probeJson | ConvertFrom-Json
$video = $probe.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 } | Select-Object -First 1
$audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
if (-not $video) { Say 'No picture found in that file.' Red; Finish 1 }
$duration = 0.0
if ($probe.format.duration) { $duration = [double]$probe.format.duration }
$fps = Get-Fps $video.avg_frame_rate

Say ("Source: {0}" -f (Split-Path $InputFile -Leaf)) Cyan
Say ("        {0}x{1}, {2}, {3:N0} min {4:N0} s" -f $video.width, $video.height, $video.codec_name, [math]::Floor($duration / 60), ($duration % 60))
Say ''
if ($Mode -eq 'startup') { $kind = '1' }
elseif ($Mode -eq 'film') { $kind = '2' }
else {
    Say 'What are you making?'
    Say '  1  Startup video (short clip that plays when the car starts)'
    Say '  2  Film or long video (plays from USB when parked)'
    $kind = Ask 'Type 1 or 2' '1'
}

if ($Fit -eq 'fill') { $fitChoice = '1' }
elseif ($Fit -eq 'bars') { $fitChoice = '2' }
else {
    Say ''
    Say 'How should it fit the screen?'
    Say '  1  Fill the screen (trims the edges if the shape is different)'
    Say '  2  Show the whole picture (adds black bars)'
    $fitDefault = '1'
    if ($kind -eq '2') { $fitDefault = '2' }
    $fitChoice = Ask 'Type 1 or 2' $fitDefault
}

$size = "${ScreenWidth}:${ScreenHeight}"
if ($kind -ne '2') { $size = "${StartupWidth}:${StartupHeight}" }
if ($fitChoice -eq '1') {
    $filter = "scale=${size}:force_original_aspect_ratio=increase,crop=${size},setsar=1"
} else {
    $filter = "scale=${size}:force_original_aspect_ratio=decrease,pad=${size}:(ow-iw)/2:(oh-ih)/2,setsar=1"
}

$folder = Split-Path $InputFile -Parent
$name   = [IO.Path]::GetFileNameWithoutExtension($InputFile)
$ffArgs = @('-hide_banner', '-loglevel', 'warning', '-stats', '-y')

if ($kind -eq '2') {
    # ---------------- FILM ----------------
    $output = Join-Path $folder "${name}_car.mp4"
    $audioPick = -1
    if ($audio.Count -gt 0) {
        $audioPick = 0
        for ($i = 0; $i -lt $audio.Count; $i++) {
            if ($audio[$i].tags.language -eq 'eng') { $audioPick = $i; break }
        }
        if ($AudioTrack -ge 1 -and $AudioTrack -le $audio.Count) {
            $audioPick = $AudioTrack - 1
        } elseif ($audio.Count -gt 1) {
            Say ''
            Say 'This file has more than one soundtrack:'
            for ($i = 0; $i -lt $audio.Count; $i++) {
                Say ("  {0}  {1}  {2}  {3} channels  {4}" -f ($i + 1), $audio[$i].tags.language, $audio[$i].codec_name, $audio[$i].channels, $audio[$i].tags.title)
            }
            $choice = Ask 'Which one' ($audioPick + 1)
            $n = 0
            if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $audio.Count) { $audioPick = $n - 1 }
        }
    }
    # Keep the file under the FAT32 limit by lowering the ceiling on long films.
    $maxRate = $FilmMaxBitrate
    if ($duration -gt 0) {
        $fits = [math]::Floor(($Fat32LimitBytes * 8 / $duration / 1000) - $AudioBitrate)
        if ($fits -lt $maxRate) {
            $maxRate = [int]$fits
            Say ''
            Say ("Long film: lowering the bitrate to {0} kbps so the file stays under 4 GB." -f $maxRate) Yellow
        }
    }
    if ($fps -gt 30.5) { $filter = "$filter,fps=30" }
    $ffArgs += @('-i', $InputFile, '-map', '0:v:0')
    if ($audioPick -ge 0) { $ffArgs += @('-map', "0:a:$audioPick") }
    $ffArgs += @('-vf', $filter, '-c:v', 'libx264', '-profile:v', 'baseline', '-level', '3.1',
                 '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', "$FilmQuality",
                 '-maxrate', "${maxRate}k", '-bufsize', "$($maxRate * 2)k")
    if ($audioPick -ge 0) { $ffArgs += @('-c:a', 'aac', '-b:a', "${AudioBitrate}k", '-ac', '2', '-ar', '48000') }
} else {
    # ---------------- STARTUP VIDEO ----------------
    $output = Join-Path $folder "${name}_startup.mp4"
    Say ''
    $clipStart = $Start
    if (-not $clipStart) { $clipStart = Ask 'Start the clip at (seconds, or mm:ss)' '0' }
    $clipLength = $Length
    if (-not $clipLength) { $clipLength = Ask "Clip length in seconds (max $StartupMaxSecs)" $StartupSeconds }
    $secs = 0.0
    if (-not [double]::TryParse($clipLength, [ref]$secs) -or $secs -le 0) { $secs = $StartupSeconds }
    if ($secs -gt $StartupMaxSecs) { $secs = $StartupMaxSecs }
    $soundAnswer = $Sound
    if (-not $soundAnswer) { $soundAnswer = Ask 'Keep the sound? (y/n)' 'y' }
    $ffArgs += @('-ss', $clipStart, '-i', $InputFile, '-t', "$secs", '-map', '0:v:0')
    $keepSound = ($soundAnswer -match '^[yY]') -and ($audio.Count -gt 0)
    if ($keepSound) { $ffArgs += @('-map', '0:a:0') }
    if ($fps -gt 30.5) { $filter = "$filter,fps=30" }
    # MPEG-4 Simple Profile at a high bitrate: the format of the startup clips proven on the car.
    $ffArgs += @('-vf', $filter, '-c:v', 'mpeg4', '-vtag', 'mp4v', '-bf', '0', '-pix_fmt', 'yuv420p',
                 '-b:v', "${StartupBitrate}k", '-maxrate', "$([int]($StartupBitrate * 1.2))k", '-bufsize', "$($StartupBitrate * 2)k")
    if ($keepSound) { $ffArgs += @('-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-ar', '44100') }
}
$ffArgs += @('-sn', '-dn', '-map_chapters', '-1', '-map_metadata', '-1', '-movflags', '+faststart', $output)

Say ''
Say 'Converting. A film can take a while; a startup clip takes seconds.' Cyan
& $ffmpeg @ffArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    Say ''
    Say 'The conversion failed. The message above says why.' Red
    Finish 1
}

$outSize = (Get-Item -LiteralPath $output).Length
Say ''
Say 'Done.' Green
Say ("Saved: {0}  ({1:N1} MB)" -f $output, ($outSize / 1MB)) Green
if ($outSize -ge 4294967295) {
    Say 'Warning: this file is over 4 GB and will not fit on a FAT32 stick.' Red
    Say 'Lower $FilmMaxBitrate at the top of convert.ps1 and run it again.' Red
}
Say ''
Say 'Next:'
Say '  1. Copy the file to a USB stick formatted as FAT32.'
if ($kind -eq '2') {
    Say '  2. Plug it into the car and open it from the USB source while parked with the handbrake on.'
} else {
    Say '  2. Plug it into the car, open Honda Hack, and choose it in the startup video menu.'
    Say '  3. In Honda Hack, set the maximum play time longer than your clip, or it cuts off early.'
}
Say ''
if ($OnWindows) { Start-Process explorer.exe "/select,`"$output`"" }
Finish 0
