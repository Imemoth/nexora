<#
Smoke test of the native Windows shell integration of a built nexora.exe (single instance, minimize to tray,
restore, tray-menu Exit). It drives the real executable with window messages exactly as the shell does; it does not
need credentials, network or a signed-in account. Run from the repository root after `flutter build windows`.

  pwsh tool/windows_shell_smoke.ps1 [-Exe path] [-Log path]

Exit code 0: every check passed. 2: no window appeared (no interactive desktop; checks not run). 1: a check failed.
#>
param(
  [string]$Exe = 'build\windows\x64\runner\Release\nexora.exe',
  [string]$Log = ''
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NxWin {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
'@
$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$m) { Write-Host $m; $lines.Add($m) }
$failed = $false
function Check([string]$name, [bool]$ok) {
  if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:failed = $true }
}
function Wait-Until([scriptblock]$cond, [int]$seconds) {
  $end = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $end) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 300 }
  return $false
}
function Find-Main { [NxWin]::FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'nexora') }

$exePath = (Resolve-Path $Exe).Path
Get-Process nexora -ErrorAction SilentlyContinue | Stop-Process -Force
$workDir = Join-Path $env:RUNNER_TEMP ('nx-shell-smoke-' + [guid]::NewGuid().ToString('N'))
if (-not $env:RUNNER_TEMP) { $workDir = Join-Path $env:TEMP ('nx-shell-smoke-' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force $workDir | Out-Null
$env:NEXORA_DB_PATH = Join-Path $workDir 'nexora.db'   # a throw-away database: never touches a real one

$first = Start-Process -FilePath $exePath -PassThru
$hwnd = [IntPtr]::Zero
$appeared = Wait-Until { $script:hwnd = Find-Main; $script:hwnd -ne [IntPtr]::Zero -and [NxWin]::IsWindowVisible($script:hwnd) } 60
if (-not $appeared) {
  Say 'NO WINDOW: no interactive desktop or the app did not start; shell checks were not run.'
  try { $first.Kill() } catch {}
  if ($Log) { $lines | Set-Content -Path $Log -Encoding ascii }
  exit 2
}
Say "window found: $hwnd"

# 1. Single instance: a second launch exits at once and leaves exactly one process.
$second = Start-Process -FilePath $exePath -PassThru
$exited = $second.WaitForExit(15000)
Check 'second launch exits (single instance)' $exited
Check 'first instance still running after second launch' (-not $first.HasExited)
Check 'exactly one nexora process' ((Get-Process nexora -ErrorAction SilentlyContinue | Measure-Object).Count -eq 1)

# 2. Minimize goes to the tray: the window is hidden, the process keeps running.
[NxWin]::ShowWindow($hwnd, 6) | Out-Null   # SW_MINIMIZE
$hidden = Wait-Until { -not [NxWin]::IsWindowVisible($hwnd) } 10
Check 'minimize hides the window (tray)' $hidden
Check 'process keeps running while minimized to the tray' (-not $first.HasExited)

# 3. Restore: launching again (or the tray) brings the same window back, still one process.
$third = Start-Process -FilePath $exePath -PassThru
[void]$third.WaitForExit(15000)
$shown = Wait-Until { [NxWin]::IsWindowVisible($hwnd) -and -not [NxWin]::IsIconic($hwnd) } 10
Check 'activation restores the hidden window' $shown
Check 'still exactly one process after restore' ((Get-Process nexora -ErrorAction SilentlyContinue | Measure-Object).Count -eq 1)

# 4. Tray menu Exit (WM_COMMAND 1002, what the menu item sends): the app saves and terminates.
[NxWin]::PostMessageW($hwnd, 0x0111, [IntPtr]1002, [IntPtr]::Zero) | Out-Null
$ended = $first.WaitForExit(15000)
Check 'tray Exit terminates the process' $ended
Check 'no nexora process left' ((Get-Process nexora -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)

Get-Process nexora -ErrorAction SilentlyContinue | Stop-Process -Force
if ($Log) { $lines | Set-Content -Path $Log -Encoding ascii }
if ($failed) { exit 1 }
exit 0
