# Storyboard AI updater: public GitHub ZIP releases.
param(
    [string]$InstallDir = "",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/anma8802-create/AI-tool/main/latest.json",
    [string]$FallbackManifestUrl = "https://github.com/anma8802-create/AI-tool/releases/latest/download/latest.json",
    [switch]$CheckOnly,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

function Show-Msg([string]$Text, [string]$Title = "Storyboard AI Studio Pro", [string]$Icon = "Information") {
    if ($CheckOnly -or $Yes) { Write-Host "[$Title] $Text"; return }
    [System.Windows.Forms.MessageBox]::Show($Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon) | Out-Null
}

function Copy-StoryboardUpdateContent {
    param([string]$ContentDir, [string]$InstallDir, [string]$BackupDir)
    $sourceRoot = (Resolve-Path -LiteralPath $ContentDir).Path.TrimEnd('\')
    $targetRoot = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    [IO.Directory]::CreateDirectory($targetRoot) | Out-Null
    [IO.Directory]::CreateDirectory($BackupDir) | Out-Null
    $changed = New-Object 'System.Collections.Generic.List[object]'
    $skipped = 0
    try {
        foreach ($file in (Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
            $normalized = $relative.Replace('\','/')
            $target = Join-Path $targetRoot $relative
            $userDirectory = $normalized -match '^(studio/)?(productions|character_clones|inbox|scratch|checkpoints|voice_previews|\.venv)/'
            $userFile = $file.Name -in @('.env','youtube_channels.json','flow_tool.json','flow_accounts.json','accounts.json','user_config.json','settings.json')
            if ($userDirectory -or ($userFile -and (Test-Path -LiteralPath $target))) { $skipped++; continue }
            if (Test-Path -LiteralPath $target -PathType Container) { throw "File conflicts with a directory: $relative" }
            $hadOriginal = Test-Path -LiteralPath $target -PathType Leaf
            $backup = Join-Path $BackupDir $relative
            if ($hadOriginal) {
                [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
                [IO.File]::Copy($target, $backup, $true)
            }
            $changed.Add([pscustomobject]@{Target=$target;Backup=$backup;HadOriginal=$hadOriginal})
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            [IO.File]::Copy($file.FullName, $target, $true)
        }
    }
    catch {
        $copyFailure = $_
        for ($index = $changed.Count - 1; $index -ge 0; $index--) {
            $entry = $changed[$index]
            if ($entry.HadOriginal) {
                [IO.File]::Copy($entry.Backup, $entry.Target, $true)
            } elseif (Test-Path -LiteralPath $entry.Target -PathType Leaf) {
                Remove-Item -LiteralPath $entry.Target -Force
            }
        }
        throw $copyFailure
    }
    return [pscustomobject]@{Updated=$changed.Count;Protected=$skipped;BackupDir=$BackupDir}
}

function Get-StoryboardUpdateProcessIds {
    param([object[]]$Processes, [string]$InstallDir, [int]$UpdaterProcessId = $PID)
    $prefix = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\') + '\'
    foreach ($process in $Processes) {
        if ($process.ProcessId -eq $UpdaterProcessId) { continue }
        if ($process.Name -notmatch '^(Storyboard_AI_Studio|python|pythonw)\.exe$') { continue }
        $executableMatches = $process.ExecutablePath -and $process.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        $commandMatches = $process.CommandLine -and $process.CommandLine.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($executableMatches -or $commandMatches) { $process.ProcessId }
    }
}

try {
    if (-not $InstallDir) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        foreach ($candidate in @(
            (Join-Path $scriptDir '..'),
            $scriptDir,
            (Join-Path $env:LOCALAPPDATA 'Programs\StoryboardAI-AutoSetup-Test'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Storyboard AI Studio Pro'),
            'D:\STORYBOARD_AI'
        )) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'studio\web_server.py')) {
                $InstallDir = (Resolve-Path -LiteralPath $candidate).Path
                break
            }
        }
    }
    if (-not $InstallDir -or -not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        throw 'Khong tim thay thu muc cai dat Storyboard AI.'
    }
    $manifest = $null
    foreach ($url in @($ManifestUrl, $FallbackManifestUrl)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $client = New-Object Net.WebClient
            $client.Encoding = [Text.Encoding]::UTF8
            $client.Headers.Add('User-Agent','StoryboardAI-Updater/1.3.2')
            $client.Headers.Add('Cache-Control','no-cache')
            $candidateManifest = $client.DownloadString($url) | ConvertFrom-Json
            if ($candidateManifest.version -and $candidateManifest.installer) { $manifest = $candidateManifest; break }
        } catch { Write-Host ('Manifest unavailable: ' + $url) }
        finally { if ($client) { $client.Dispose() } }
    }
    if (-not $manifest) { throw 'Khong doc duoc thong tin cap nhat tu GitHub.' }
    $latestVer = [string]$manifest.version
    if ($latestVer -notmatch '^\d+\.\d+\.\d+$') { throw 'Phien ban manifest khong hop le.' }
    $installerUrl = [string]$manifest.installer
    $assetName = "Storyboard_AI_Studio_Pro_v$latestVer.zip"
    $allowedUrl = "https://github.com/anma8802-create/AI-tool/releases/latest/download/$assetName"
    if ($installerUrl -cne $allowedUrl) { throw 'URL goi cap nhat khong thuoc GitHub Releases duoc phep.' }
    $expectedBytes = [int64]$manifest.bytes
    $expectedSha = [string]$manifest.sha256
    if ($expectedBytes -lt 1000000 -or $expectedBytes -gt 2000000000) { throw 'Kich thuoc goi cap nhat khong hop le.' }
    if ($expectedSha -notmatch '^[A-Fa-f0-9]{64}$') { throw 'SHA256 manifest khong hop le.' }
    $currentVer = '0.0.0'
    $verFile = Join-Path $InstallDir 'studio\version.json'
    if (Test-Path -LiteralPath $verFile) {
        try {
            $localVersion = Get-Content -LiteralPath $verFile -Encoding UTF8 -Raw | ConvertFrom-Json
            if ([string]$localVersion.version -match '^\d+\.\d+\.\d+$') { $currentVer = [string]$localVersion.version }
        } catch {}
    }
    $available = [version]$latestVer -gt [version]$currentVer
    if ($CheckOnly) {
        [pscustomobject]@{ok=$true;current_version=$currentVer;latest_version=$latestVer;update_available=$available;installer_bytes=$expectedBytes} | ConvertTo-Json -Compress
        exit 0
    }
    if (-not $available) { Show-Msg "Ban dang dung phien ban moi nhat (v$currentVer)."; exit 0 }
    if (-not $Yes) {
        $notes = ($manifest.release_notes -join [Environment]::NewLine)
        $prompt = "Cap nhat v$currentVer len v$latestVer ?" + [Environment]::NewLine + [Environment]::NewLine + $notes
        $answer = [Windows.Forms.MessageBox]::Show(
            $prompt, 'Cap nhat Storyboard AI', [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }
    }
    $workRoot = Join-Path $env:TEMP ('StoryboardAI-Update-' + [guid]::NewGuid())
    [IO.Directory]::CreateDirectory($workRoot) | Out-Null
    $tempZip = Join-Path $workRoot $assetName
    $extractDir = Join-Path $workRoot 'package'
    Write-Host "Dang tai v$latestVer tu GitHub..."
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe --fail --location --retry 2 --connect-timeout 20 --max-time 1200 --output $tempZip $installerUrl
        if ($LASTEXITCODE -ne 0) { throw "Tai goi cap nhat that bai (curl $LASTEXITCODE)." }
    } else {
        $downloadClient = New-Object Net.WebClient
        try { $downloadClient.DownloadFile($installerUrl, $tempZip) } finally { $downloadClient.Dispose() }
    }
    if ((Get-Item -LiteralPath $tempZip).Length -ne $expectedBytes) { throw 'File tai ve chua du kich thuoc.' }
    if ((Get-FileHash -LiteralPath $tempZip -Algorithm SHA256).Hash -ine $expectedSha) { throw 'SHA256 khong khop; khong cai dat.' }
    Expand-Archive -LiteralPath $tempZip -DestinationPath $extractDir -Force
    $contentDir = $extractDir
    if (-not (Test-Path -LiteralPath (Join-Path $contentDir 'studio\web_server.py'))) {
        $subdirs = @(Get-ChildItem -LiteralPath $extractDir -Directory)
        if ($subdirs.Count -eq 1) { $contentDir = $subdirs[0].FullName }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $contentDir 'studio\web_server.py')) -or
        -not (Test-Path -LiteralPath (Join-Path $contentDir 'Storyboard_AI_Studio.exe'))) {
        throw 'Goi ZIP khong chua ung dung Storyboard AI hoan chinh.'
    }
    $backupDir = Join-Path $env:LOCALAPPDATA ('StoryboardAI\Updater\backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    $processIds = @(Get-StoryboardUpdateProcessIds -Processes @(Get-CimInstance Win32_Process) -InstallDir $InstallDir)
    foreach ($processId in $processIds) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
    if ($processIds.Count) { Start-Sleep -Seconds 2 }
    $result = Copy-StoryboardUpdateContent -ContentDir $contentDir -InstallDir $InstallDir -BackupDir $backupDir
    $versionData = @{version=$latestVer;updated_at=(Get-Date).ToString('o');release_name=$manifest.release_name} | ConvertTo-Json
    [IO.File]::WriteAllText($verFile, $versionData, (New-Object Text.UTF8Encoding($false)))
    $bundledUpdater = Join-Path $InstallDir 'tools\Update-StoryboardAI.ps1'
    if ((Test-Path -LiteralPath $bundledUpdater) -and
        -not [string]::Equals([IO.Path]::GetFullPath($bundledUpdater), [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path), [StringComparison]::OrdinalIgnoreCase)) {
        try { [IO.File]::Copy($bundledUpdater, $MyInvocation.MyCommand.Path, $true) }
        catch { Write-Host 'Can dong bo updater trong lan khoi dong sau.' }
    }
    Write-Host ("UPDATED version=$latestVer files=" + $result.Updated + " protected=" + $result.Protected + " backup=" + $backupDir)
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    $launcher = Join-Path $InstallDir 'Storyboard_AI_Studio.exe'
    Start-Process -FilePath $launcher -WorkingDirectory $InstallDir
    Show-Msg "Da cap nhat len v$latestVer. Du lieu tai khoan va du an duoc giu nguyen."
    exit 0
}
catch {
    Show-Msg ("Cap nhat that bai: " + $_.Exception.Message) 'Loi cap nhat' 'Error'
    exit 1
}
