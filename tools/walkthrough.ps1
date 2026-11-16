# Plays the first mission automatically through the real input path (synthetic clicks on the
# 3D world and on real buttons, commands typed key by key, camera drags) and saves one
# screenshot per step. Opens a game window for about a minute per scenario.
#
#   powershell -ExecutionPolicy Bypass -File tools\walkthrough.ps1                 # all scenarios
#   powershell -ExecutionPolicy Bypass -File tools\walkthrough.ps1 -Scenario far   # just one
#
# Scenarios: basic, wall, far, blocking (where the rack goes), furniture (rearranging the room), menu (title screen, character creator, save and load from the title) and manual (takes the annotated
# screenshots of the in-game manual into assets\manual\; not part of 'all'). See game/debug/walkthrough_driver.gd.
# Output: build\walkthrough\<scenario>\NN_<step>.png and walkthrough_log.txt (not versioned).
param(
    [ValidateSet('all', 'basic', 'wall', 'far', 'blocking', 'furniture', 'menu', 'manual')]
    [string]$Scenario = 'all',
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\walkthrough'),
    [string]$Resolution = '1600x900'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

# Screenshots are not game resources: keep Godot from importing them.
$buildRoot = Split-Path $OutDir -Parent
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
if (-not (Test-Path (Join-Path $buildRoot '.gdignore'))) { New-Item -ItemType File -Path (Join-Path $buildRoot '.gdignore') | Out-Null }

$names = if ($Scenario -eq 'all') { @('basic', 'wall', 'far', 'blocking', 'furniture', 'menu') } else { @($Scenario) }
$failed = @()
foreach ($name in $names) {
    $dir = Join-Path $OutDir $name
    if (Test-Path $dir) { Get-ChildItem $dir -File | Remove-Item }
    $out = (New-Item -ItemType Directory -Force -Path $dir).FullName
    Write-Host "=== Scenario: $name ==="
    $r = Invoke-Godot -GodotArgs @('--path', '.', '--resolution', $Resolution,
        'res://game/main/main.tscn', '--', "--walkthrough=$out", "--scenario=$name") -TimeoutSec 300
    ($r.StdOut -split "\r?\n") | Where-Object { $_ -match '^WALK' }
    foreach ($line in $r.Errors) { Write-Host "  $line" }
    # Exit code 0 alone is not enough: closing the window also exits with 0.
    $finished = $r.StdOut -match "WALKTHROUGH $name OK"
    if (-not $finished) {
        Write-Host "  (the run did not reach its end: no 'WALKTHROUGH $name OK' line, exit code $($r.ExitCode))"
        Write-Host '  --- last lines of stdout ---'
        ($r.StdOut -split "\r?\n") | Where-Object { $_ -ne '' } | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
        Write-Host '  --- last lines of stderr ---'
        ($r.StdErr -split "\r?\n") | Where-Object { $_ -ne '' } | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
    }
    if ($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0 -or -not $finished) { $failed += $name }
}
if ($failed.Count -gt 0) { Write-Host "WALKTHROUGH CHECK FAILED: $($failed -join ', ')"; exit 1 }
Write-Host "WALKTHROUGH CHECK PASSED ($($names -join ', ')) -> $OutDir"
exit 0
