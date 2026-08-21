[CmdletBinding()]
param(
    [ValidateRange(1, 32)]
    [int]$Jobs = 8,
    [string]$VolumeName = 'flint2-openwrt-vm-build',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path $PSScriptRoot).Path
$EnvironmentArguments = @(
    '--env', "VM_BUILDROOT=/build/openwrt-vm",
    '--env', "JOBS=$Jobs"
)
if ($PrepareOnly) {
    $EnvironmentArguments += @('--env', 'VM_PREPARE_ONLY=1')
}

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
    @EnvironmentArguments `
    flint2-openwrt-builder:25.12.5 bash ./scripts/build-vm.sh
exit $LASTEXITCODE
