# Cross-process persistence check (automated part of SAVE-PERSIST-01).
#
# Runs two separate Dart processes against one database file. The first process
# writes a project and a task and exits. A second, new process must read them back
# intact. The check uses the production path resolver with NEXORA_DB_PATH, so the
# user's real database is never touched.
#
# This does not replace the manual Windows acceptance of the packaged app, which
# is recorded in docs/operations/phase-2a-windows-acceptance.md.
#
# Usage: ./tool/persistence/restart_check.ps1 [-Dart <path to dart>]

[CmdletBinding()]
param(
    [string] $Dart = 'dart'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('nexora-restart-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$previousDbPath = $env:NEXORA_DB_PATH
$env:NEXORA_DB_PATH = Join-Path $tempDir 'nexora.db'
try {
    Push-Location $repoRoot
    try {
        & $Dart run tool/persistence/restart_write.dart
        if ($LASTEXITCODE -ne 0) {
            throw "write process exited with code $LASTEXITCODE"
        }
        Write-Output 'Process 1 finished. Starting a new process to read the data back.'
        & $Dart run tool/persistence/restart_read.dart
        if ($LASTEXITCODE -ne 0) {
            throw "read process after restart exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:NEXORA_DB_PATH = $previousDbPath
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'RESTART PASS: data written by one process was read back by a new process'
