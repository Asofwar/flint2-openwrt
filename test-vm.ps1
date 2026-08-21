[CmdletBinding()]
param(
    [string]$TestImage = 'flint2-openwrt-vm-test:25.12.5',
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path $PSScriptRoot).Path
$EnvironmentArguments = @()
if ($RunId) {
    $EnvironmentArguments += @('--env', "VM_TEST_RUN_ID=$RunId")
}

& docker build --file "$ProjectPath\Dockerfile.vm-test" --tag $TestImage $ProjectPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& docker run --rm `
    "--mount=type=bind,src=$ProjectPath,dst=/workspace" `
    @EnvironmentArguments `
    $TestImage bash ./scripts/test-vm.sh
exit $LASTEXITCODE
