# Validates the project from the command line, without opening the editor UI.
#
#   powershell -ExecutionPolicy Bypass -File tools\check_project.ps1
#
# Steps: (1) import resources, (2) run the smoke test, (3) check the imported
# 3D models (size, Y-up, functional markers), (4) run the unit tests, (5) run the main scene
# (title screen) and (6) a new game for a few frames and collect runtime errors. Exit code 0 only if all pass and no
# engine/script errors were printed.
param(
    [int]$RunFrames = 120,
    [switch]$ShowOutput
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\godot-common.ps1"

$steps = @(
    @{ Name = 'import';     Args = @('--headless', '--path', '.', '--import');                                  Timeout = 300 },
    @{ Name = 'smoke test'; Args = @('--headless', '--path', '.', '--script', 'res://tests/smoke_test.gd');      Timeout = 120 },
    @{ Name = 'models';     Args = @('--headless', '--path', '.', '--script', 'res://tests/check_models.gd');    Timeout = 120 },
    @{ Name = 'unit tests'; Args = @('--headless', '--path', '.', '--script', 'res://tests/run_tests.gd');       Timeout = 180 },
    @{ Name = 'run main';   Args = @('--headless', '--path', '.', '--quit-after', "$RunFrames");                 Timeout = 120 },
    # The main scene opens on the title screen: also run a new game straight away.
    @{ Name = 'run game';   Args = @('--headless', '--path', '.', '--quit-after', "$RunFrames", '--', '--new-game'); Timeout = 120 }
)

$failed = $false
foreach ($s in $steps) {
    $r = Invoke-Godot -GodotArgs $s.Args -TimeoutSec $s.Timeout
    $bad = $r.TimedOut -or $r.ExitCode -ne 0 -or $r.Errors.Count -gt 0
    $status = if ($bad) { 'FAIL' } else { 'OK  ' }
    Write-Host ("[{0}] {1} (exit {2}, errors {3}, warnings {4})" -f $status, $s.Name, $r.ExitCode, $r.Errors.Count, $r.Warnings.Count)
    if ($r.TimedOut) { Write-Host "      timed out after $($s.Timeout)s" }
    foreach ($line in $r.Errors) { Write-Host "      $line" }
    if ($ShowOutput) { Write-Host $r.StdOut; Write-Host $r.StdErr }
    if ($bad) { $failed = $true }
}
if ($failed) { Write-Host 'CHECK FAILED'; exit 1 }
Write-Host 'CHECK PASSED'
exit 0
