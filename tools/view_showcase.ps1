# Opens the model showcase in a game window to look around.
#
#   powershell -ExecutionPolicy Bypass -File tools\view_showcase.ps1
#
# Controls: 1-5 change view · on view 1: Q/E (or arrows) orbit, mouse wheel zoom · Esc closes.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$godot = Find-Godot
$env:GODOT_AI_DISABLE_TELEMETRY = '1'
Start-Process -FilePath $godot -WorkingDirectory $script:ProjectRoot `
    -ArgumentList @('--path', '.', '--resolution', '1600x900', 'res://game/showcase/model_showcase.tscn')
Write-Host 'Showcase window launching (1-5 views, Q/E orbit, wheel zoom, Esc to close).'
