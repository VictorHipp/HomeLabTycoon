# Plays the first mission automatically through the real input path (synthetic clicks on the
# 3D world and on real buttons, commands typed key by key, camera drags) and saves one
# screenshot per step. Opens a game window for about a minute per scenario.
#
#   powershell -ExecutionPolicy Bypass -File tools\walkthrough.ps1                 # all scenarios
#   powershell -ExecutionPolicy Bypass -File tools\walkthrough.ps1 -Scenario far   # just one
#
# Scenarios (where the rack goes): basic, wall, far, blocking (game/debug/walkthrough_driver.gd).
# Output: build\walkthrough\<scenario>\NN_<step>.png and walkthrough_log.txt (not versioned).
param(
    [ValidateSet('all', 'basic', 'wall', 'far', 'blocking')]
    [string]$Scenario = 'all',
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\walkthrough'),
    [string]$Resolution = '1600x900'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$names = if ($Scenario -eq 'all') { @('basic', 'wall', 'far', 'blocking') } else { @($Scenario) }
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
    if (-not $finished) { Write-Host "  (the run did not reach its end: no 'WALKTHROUGH $name OK' line, exit code $($r.ExitCode))" }
    if ($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0 -or -not $finished) { $failed += $name }
}
if ($failed.Count -gt 0) { Write-Host "WALKTHROUGH CHECK FAILED: $($failed -join ', ')"; exit 1 }
Write-Host "WALKTHROUGH CHECK PASSED ($($names -join ', ')) -> $OutDir"
exit 0
