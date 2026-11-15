# Plays the first mission automatically (synthetic clicks) and saves one screenshot per step.
# Opens a game window for about a minute.
#
#   powershell -ExecutionPolicy Bypass -File tools\walkthrough.ps1
#
# Output: docs\images\walkthrough\NN_<step>.png and walkthrough_log.txt
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\images\walkthrough'),
    [string]$Resolution = '1600x900'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

if (Test-Path $OutDir) { Get-ChildItem $OutDir -Filter *.png | Remove-Item }
$out = (New-Item -ItemType Directory -Force -Path $OutDir).FullName
$r = Invoke-Godot -GodotArgs @('--path', '.', '--resolution', $Resolution,
    'res://game/main/main.tscn', '--', "--walkthrough=$out") -TimeoutSec 300
($r.StdOut -split "\r?\n") | Where-Object { $_ -match '^WALK' }
foreach ($line in $r.Errors) { Write-Host "  $line" }
if ($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0) { Write-Host 'WALKTHROUGH CHECK FAILED'; exit 1 }
Write-Host "WALKTHROUGH CHECK PASSED -> $out"
exit 0
