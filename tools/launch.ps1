param([switch]$Editor, [switch]$Check)
$ErrorActionPreference = 'Stop'
$projectFolder = Split-Path -Parent $PSScriptRoot
$engineCandidates = [System.Collections.Generic.List[string]]::new()
if ($env:GODOT_EXE) { $engineCandidates.Add($env:GODOT_EXE) }
foreach ($commandName in @('godot', 'godot4')) {
    $engineCommand = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($engineCommand) { $engineCandidates.Add($engineCommand.Source) }
}
$desktopFolder = [Environment]::GetFolderPath('Desktop')
$shortcutFiles = Get-ChildItem -LiteralPath $desktopFolder -Filter '*Godot*.lnk' -ErrorAction SilentlyContinue
if ($shortcutFiles) {
    $shortcutReader = New-Object -ComObject WScript.Shell
    foreach ($shortcutFile in $shortcutFiles) {
        $engineCandidates.Add($shortcutReader.CreateShortcut($shortcutFile.FullName).TargetPath)
    }
}
$engineCandidates.Add('D:\godot\Godot\Godot_v4.7.2-stable_win64.exe')
$enginePath = $engineCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $enginePath) {
    Write-Host 'Godot was not found. Import project.godot with Godot 4.7.2, or set GODOT_EXE to its executable path.'
    Read-Host 'Press Enter to close'
    exit 1
}
if ($Check) {
    & $enginePath --headless --path $projectFolder --script res://tests/keyboard_movement_checks.gd
    exit $LASTEXITCODE
}
$launchArguments = @('--path', ('"' + $projectFolder + '"'))
if ($Editor) { $launchArguments += '--editor' }
Start-Process -FilePath $enginePath -ArgumentList $launchArguments -WorkingDirectory $projectFolder
