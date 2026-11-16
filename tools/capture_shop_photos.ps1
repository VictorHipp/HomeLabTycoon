# Renders the shop's product photos from the game's own models (opens a game window briefly).
#
#   powershell -ExecutionPolicy Bypass -File tools\capture_shop_photos.ps1
#
# Output: assets\shop\<item id>_1.png (front three-quarter) and _2.png (rear, or the plug of a
# cable). Run tools\check_project.ps1 afterwards so Godot imports them.
param([string]$Resolution = '640x480')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$r = Invoke-Godot -GodotArgs @('--path', '.', '--resolution', $Resolution,
    'res://game/showcase/shop_photo_studio.tscn') -TimeoutSec 180
($r.StdOut -split "\r?\n") | Where-Object { $_ -match '^SHOP PHOTO' }
foreach ($line in $r.Errors) { Write-Host "  $line" }
if ($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0 -or -not ($r.StdOut -match 'SHOP PHOTOS \d+ saved')) { Write-Host 'CAPTURE FAILED'; exit 1 }
Write-Host 'CAPTURE OK -> assets\shop'
exit 0
