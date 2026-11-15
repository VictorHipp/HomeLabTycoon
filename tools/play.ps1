# Starts the game (first-mission test) in a window. Same as pressing F5 in the editor.
#
#   powershell -ExecutionPolicy Bypass -File tools\play.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$godot = Find-Godot
$env:GODOT_AI_DISABLE_TELEMETRY = '1'
Start-Process -FilePath $godot -WorkingDirectory $script:ProjectRoot -ArgumentList @('--path', '.', '--resolution', '1600x900')
Write-Host 'HomeLab Tycoon launching (first-mission test).'
