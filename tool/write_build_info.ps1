# Writes BUILD-INFO.json: the identity of the build that is being packaged.
#
# Usage (CI, after `flutter build windows --release`, before packaging):
#   ./tool/write_build_info.ps1 -BuildType release `
#       -OutputPath build/windows/x64/runner/Release/BUILD-INFO.json
#
# The version is read from pubspec.yaml (its single source). The commit, the run
# and the checkout come from the environment the workflow set before it built:
#   NEXORA_SOURCE_COMMIT   the commit the work is on (a pull request's head commit)
#   NEXORA_BUILD_RUN       <run id>-<attempt>, to find the workflow run
#   GITHUB_SHA             the commit that was actually checked out (for a pull
#                          request this is GitHub's test merge commit)
# It contains no secrets, URLs or account data. Without a valid commit it fails:
# a CI build is never given an unknown or invented identity.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('release', 'development-test')]
    [string] $BuildType,

    [Parameter(Mandatory = $true)]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$')
if (-not $match.Success) {
    throw 'pubspec.yaml has no top-level "version: x.y.z[+n]" line'
}

$source = $env:NEXORA_SOURCE_COMMIT
if ($source -notmatch '^[0-9a-f]{40}$') {
    throw 'NEXORA_SOURCE_COMMIT is not a 40-character commit id'
}
$checkout = $env:GITHUB_SHA
if ([string]::IsNullOrEmpty($checkout)) {
    $checkout = $source
}
if ($checkout -notmatch '^[0-9a-f]{40}$') {
    throw 'GITHUB_SHA is not a 40-character commit id'
}
$run = $env:NEXORA_BUILD_RUN
if ($run -notmatch '^[0-9]+-[0-9]+$') {
    throw 'NEXORA_BUILD_RUN is not <run id>-<attempt>'
}

$info = [ordered]@{
    app            = 'nexora'
    version        = $match.Groups[1].Value
    buildNumber    = $match.Groups[2].Value
    buildType      = $BuildType
    sourceCommit   = $source
    sourceShort    = $source.Substring(0, 7)
    checkoutCommit = $checkout
    ciRun          = $run
    builtAtUtc     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$dir = Split-Path -Parent $OutputPath
if ($dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
($info | ConvertTo-Json) | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "BUILD-INFO: $($info.version)+$($info.buildNumber) $($info.buildType) commit $($info.sourceShort) run $($info.ciRun)"
