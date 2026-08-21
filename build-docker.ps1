[CmdletBinding()]
param(
    [ValidateRange(1, 32)]
    [int]$Jobs = 8,
    [string]$VolumeName = 'flint2-openwrt-build'
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path $PSScriptRoot).Path

& docker build --tag flint2-openwrt-builder:25.12.5 $ProjectPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& docker volume create $VolumeName | Out-Null
& docker run --rm --user root `
    "--mount=type=volume,src=$VolumeName,dst=/build" `
    flint2-openwrt-builder:25.12.5 sh -c 'mkdir -p /build && chown -R builder:builder /build'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& docker run --rm --user builder `
    "--mount=type=bind,src=$ProjectPath,dst=/workspace" `
    "--mount=type=volume,src=$VolumeName,dst=/build" `
    --env "BUILDROOT=/build/openwrt" `
    --env "JOBS=$Jobs" `
    flint2-openwrt-builder:25.12.5 ./build.sh
exit $LASTEXITCODE
