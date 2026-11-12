# Packages the Windows release bundle as a portable ZIP and smoke-tests it.
#
# Usage (after `flutter build windows --release`):
#   ./tool/package_windows.ps1 -OutputDir ./dist
#
# Steps:
#   1. Verify the complete Release bundle exists (exe, engine DLL, data/).
#   2. Create dist/nexora-windows-portable.zip from the FULL Release directory.
#   3. Verify the ZIP lists every required runtime file.
#   4. Extract to a temp path containing spaces and non-ASCII characters,
#      launch nexora.exe, check it stays running, close it via WM_CLOSE and
#      require exit code 0.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputDir,

    [int] $SmokeSeconds = 8
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$zipName = 'nexora-windows-portable.zip'
$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'

# Runtime files a release bundle must contain (relative to the Release folder).
# sqlite3.dll is the native asset of the sqlite3 package (Phase 2A local
# persistence). Without it the app cannot open its database.
$requiredFiles = @(
    'nexora.exe',
    'flutter_windows.dll',
    'sqlite3.dll',
    'data\app.so',
    'data\icudtl.dat'
)

function Assert-File([string] $path, [string] $what) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing $what : $path"
    }
}

# 1. Verify the bundle.
if (-not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
    throw "Release directory not found: $releaseDir. Run 'flutter build windows --release' first."
}
foreach ($rel in $requiredFiles) {
    Assert-File (Join-Path $releaseDir $rel) "release bundle file"
}
Write-Output "OK: release bundle complete at $releaseDir"

# 2. Create the ZIP from the full Release directory.
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputFull = (Resolve-Path -LiteralPath $OutputDir).Path
$zipPath = Join-Path $outputFull $zipName
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Assert-File $zipPath 'packaged ZIP'

# 3. Verify ZIP entries.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = $archive.Entries | ForEach-Object { $_.FullName.Replace('/', '\') }
} finally {
    $archive.Dispose()
}
foreach ($rel in $requiredFiles) {
    if ($entries -notcontains $rel) {
        throw "ZIP is missing required entry: $rel"
    }
}
Write-Output "OK: ZIP contains $($entries.Count) entries including all required runtime files"

# 4. Extract and smoke-test from a path with spaces and non-ASCII characters.
# Non-ASCII characters are built from code points so this file stays ASCII.
$unicodePart = [string]::Concat([char]0x00E9, [char]0x6D4B, [char]0x8BD5) # e-acute, two CJK chars
$stageName = 'nexora smoke ' + $unicodePart + ' ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) $stageName
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stageRoot -Force
    $exe = Join-Path $stageRoot 'nexora.exe'
    Assert-File $exe 'extracted executable'

    $proc = Start-Process -FilePath $exe -WorkingDirectory $stageRoot -PassThru
    Start-Sleep -Seconds $SmokeSeconds

    if ($proc.HasExited) {
        throw "nexora.exe exited early with code $($proc.ExitCode)"
    }
    if (-not $proc.CloseMainWindow()) {
        $proc.Kill()
        throw 'nexora.exe has no main window to close'
    }
    if (-not $proc.WaitForExit(20000)) {
        $proc.Kill()
        throw 'nexora.exe did not exit after the close request'
    }
    if ($proc.ExitCode -ne 0) {
        throw "nexora.exe exited with code $($proc.ExitCode)"
    }
    Write-Output "SMOKE PASS: launched from '$stageRoot', closed cleanly (exit 0)"
} finally {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "PACKAGE PASS: $zipPath"
