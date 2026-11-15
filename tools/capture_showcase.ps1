# Renders the model showcase from its 4 views and saves PNGs (opens a game window briefly).
#
#   powershell -ExecutionPolicy Bypass -File tools\capture_showcase.ps1
#
# Output: docs\images\showcase\showcase_<view>.png
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\images\showcase'),
    [string]$Resolution = '1600x900'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$out = (New-Item -ItemType Directory -Force -Path $OutDir).FullName
$r = Invoke-Godot -GodotArgs @('--path', '.', '--resolution', $Resolution,
    'res://game/showcase/model_showcase.tscn', '--', "--capture=$out") -TimeoutSec 180
($r.StdOut -split "\r?\n") | Where-Object { $_ -match '^CAPTURE' }
foreach ($line in $r.Errors) { Write-Host "  $line" }
if ($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0) { Write-Host 'CAPTURE FAILED'; exit 1 }
Write-Host "CAPTURE OK -> $out"
exit 0
