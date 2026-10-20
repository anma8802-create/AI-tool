param([string]$UpdaterPath = (Join-Path $PSScriptRoot '..\Update-StoryboardAI.ps1'))
$ErrorActionPreference = 'Stop'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $UpdaterPath), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
foreach ($name in @('Copy-StoryboardUpdateContent','Get-StoryboardUpdateProcessIds')) {
    $node = $ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    if (-not $node) { throw "Missing tested updater function: $name" }
    Invoke-Expression $node.Extent.Text
}
function Assert-Equal($Actual, $Expected, $Label) {
    if ($Actual -ne $Expected) { throw "$Label expected [$Expected], got [$Actual]" }
}
function Put-File($Path, $Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
$testRoot = Join-Path $env:TEMP ('StoryboardUpdaterTests-' + [guid]::NewGuid())
try {
    $src = Join-Path $testRoot 'overlay\src'
    $dest = Join-Path $testRoot 'overlay\app'
    Put-File "$src\studio\web\static\app.js" 'new-ui'
    Put-File "$dest\studio\web\static\app.js" 'old-ui'
    Put-File "$src\studio\.env" 'package-default'
    Put-File "$dest\studio\.env" 'user-setting'
    Put-File "$src\studio\flow_tool.json" 'package-path'
    Put-File "$dest\studio\flow_tool.json" 'korea-path'
    Put-File "$src\studio\youtube_channels.json" 'package-channel'
    Put-File "$dest\studio\youtube_channels.json" 'user-channel'
    Put-File "$src\studio\productions\project.json" 'package-project'
    Put-File "$dest\studio\productions\project.json" 'user-project'
    Put-File "$src\studio\web_server.py" 'new-server'
    $result = Copy-StoryboardUpdateContent -ContentDir $src -InstallDir $dest -BackupDir "$testRoot\overlay\backup"
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\web\static\app.js")) 'new-ui' 'Existing nested UI must update'
    Assert-Equal (Test-Path "$dest\studio\web\web") $false 'No nested duplicate web directory'
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\.env")) 'user-setting' 'Account settings preserved'
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\flow_tool.json")) 'korea-path' 'Local Flow path preserved'
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\youtube_channels.json")) 'user-channel' 'YouTube account preserved'
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\productions\project.json")) 'user-project' 'Project preserved'
    Assert-Equal ([IO.File]::ReadAllText("$dest\studio\web_server.py")) 'new-server' 'New program code installed'
    Assert-Equal ([IO.File]::ReadAllText("$testRoot\overlay\backup\studio\web\static\app.js")) 'old-ui' 'Previous code backed up'
    Write-Output 'PASS overlay updates nested UI and preserves local data'
    $src2 = Join-Path $testRoot 'rollback\src'
    $dest2 = Join-Path $testRoot 'rollback\app'
    Put-File "$src2\0-created.txt" 'created'
    Put-File "$src2\a.txt" 'new'
    Put-File "$dest2\a.txt" 'old'
    Put-File "$src2\b.txt" 'cannot-overwrite-directory'
    [IO.Directory]::CreateDirectory("$dest2\b.txt") | Out-Null
    $failed = $false
    try { Copy-StoryboardUpdateContent -ContentDir $src2 -InstallDir $dest2 -BackupDir "$testRoot\rollback\backup" | Out-Null }
    catch { $failed = $true }
    Assert-Equal $failed $true 'Copy conflict must fail'
    Assert-Equal ([IO.File]::ReadAllText("$dest2\a.txt")) 'old' 'Failed install restores previous files'
    Assert-Equal (Test-Path "$dest2\0-created.txt") $false 'Failed install removes only newly created program files'
    Write-Output 'PASS failed overlay rolls back file changes'
    $rootPrefix = $dest.TrimEnd('\') + '\'
    $processes = @(
        [pscustomobject]@{ProcessId=101;Name='Storyboard_AI_Studio.exe';ExecutablePath=($rootPrefix+'Storyboard_AI_Studio.exe');CommandLine=''},
        [pscustomobject]@{ProcessId=102;Name='python.exe';ExecutablePath='C:\Python\python.exe';CommandLine=('python "'+$rootPrefix+'studio\web_server.py"')},
        [pscustomobject]@{ProcessId=103;Name='Storyboard_AI_Studio.exe';ExecutablePath=($dest+'-other\Storyboard_AI_Studio.exe');CommandLine=''},
        [pscustomobject]@{ProcessId=104;Name='chrome.exe';ExecutablePath=($rootPrefix+'chrome.exe');CommandLine=''},
        [pscustomobject]@{ProcessId=777;Name='python.exe';ExecutablePath=($rootPrefix+'runtime\python.exe');CommandLine=''}
    )
    $ids = @(Get-StoryboardUpdateProcessIds -Processes $processes -InstallDir $dest -UpdaterProcessId 777)
    Assert-Equal (($ids | Sort-Object) -join ',') '101,102' 'Only the selected install stops'
    Write-Output 'PASS process selection excludes other installs, Chrome and updater'
    Write-Output 'ALL_UPDATER_TESTS_PASS'
}
finally { if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
