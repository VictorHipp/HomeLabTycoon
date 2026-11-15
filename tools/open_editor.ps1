# Opens the Godot editor on this project.
#
#   powershell -ExecutionPolicy Bypass -File tools\open_editor.ps1
#
# Why use this instead of double-clicking Godot:
#  - The editor is started with the project folder as working directory.
#    The Godot AI plugin's "Configure" button runs `claude mcp add --scope
#    project ...`, which writes .mcp.json into the *CLI's working directory*.
#  - PATH is rebuilt from the registry so `uvx` (needed by Godot AI) is found.
#  - Godot AI telemetry is disabled for this session (opt-out env var).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$godot = Find-Godot
$env:GODOT_AI_DISABLE_TELEMETRY = '1'
Start-Process -FilePath $godot -ArgumentList @('--editor', '--path', ".") -WorkingDirectory $script:ProjectRoot
Write-Host "Godot editor launching from $script:ProjectRoot"
