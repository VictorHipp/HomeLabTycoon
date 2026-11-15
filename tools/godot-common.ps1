# Shared helpers for the tools\*.ps1 scripts. Dot-source it: . "$PSScriptRoot\godot-common.ps1"
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

function Update-PathFromRegistry {
    # winget adds its shims to the *persistent* PATH; a shell that was open
    # before the install does not see them until PATH is rebuilt.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Find-Godot {
    param([switch]$Console)
    Update-PathFromRegistry
    $override = if ($Console) { $env:GODOT_CONSOLE_BIN } else { $env:GODOT_BIN }
    if ($override -and (Test-Path $override)) { return $override }
    $name = if ($Console) { 'godot_console' } else { 'godot' }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $pattern = if ($Console) { 'Godot_v*_win64_console.exe' } else { 'Godot_v*_win64.exe' }
    $pkg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $found = Get-ChildItem -Path $pkg -Recurse -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Godot not found. Install it with: winget install --id GodotEngine.GodotEngine --exact"
}

function Invoke-Godot {
    <#
      Runs Godot (console build) with a timeout and captures stdout and stderr
      separately, which `2>&1` cannot do reliably in Windows PowerShell 5.1.
      Returns an object: ExitCode, TimedOut, StdOut, StdErr, Errors (lines that
      look like engine/script errors), Warnings.
    #>
    param(
        [Parameter(Mandatory)][string[]]$GodotArgs,
        [int]$TimeoutSec = 180
    )
    $exe = Find-Godot -Console
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $script:ProjectRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['GODOT_AI_DISABLE_TELEMETRY'] = '1'

    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $timedOut = -not $proc.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) { try { $proc.Kill() } catch { } }
    $proc.WaitForExit()
    $stdout = $outTask.Result
    $stderr = $errTask.Result

    $all = ($stdout + "`n" + $stderr) -split "\r?\n"
    [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { $proc.ExitCode }
        TimedOut = $timedOut
        StdOut   = $stdout
        StdErr   = $stderr
        Errors   = @($all | Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR|SMOKE FAIL|TEST FAIL|MODELS FAIL):|Parse Error' })
        Warnings = @($all | Where-Object { $_ -match '^\s*WARNING:' })
    }
}
