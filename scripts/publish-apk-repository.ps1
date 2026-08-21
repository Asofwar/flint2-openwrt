param(
    [string]$SigningKeyPath = 'C:\Users\Admin\.codex\keys\flint2-apk-repository-p256.pem'
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$key = (Resolve-Path -LiteralPath $SigningKeyPath).Path
$tagLine = Select-String -Path (Join-Path $project 'scripts\versions.env') -Pattern '^FLINT2_APK_REPOSITORY_TAG='
if ($null -eq $tagLine) { throw 'FLINT2_APK_REPOSITORY_TAG is absent' }
$tag = ($tagLine.Line -split '=', 2)[1]
$repository = 'Asofwar/flint2-openwrt'
$out = Join-Path $project 'artifacts\apk-repository'

docker run --rm --user builder `
  --mount "type=bind,src=$project,dst=/workspace" `
  --mount 'type=volume,src=flint2-openwrt-build,dst=/build' `
  --mount "type=bind,src=$key,dst=/signing/flint2-apk-repository-p256.pem,readonly" `
  --env BUILDROOT=/build/openwrt `
  --env FLINT2_APK_SIGNING_KEY=/signing/flint2-apk-repository-p256.pem `
  --workdir /workspace flint2-openwrt-builder:25.12.5 `
  bash ./scripts/prepare-apk-repository.sh

$assets = @(Get-ChildItem -LiteralPath $out -File | ForEach-Object FullName)
if ($assets.Count -eq 0) { throw 'APK repository assets were not produced' }

gh release view $tag --repo $repository *> $null
if ($LASTEXITCODE -eq 0) {
  gh release upload $tag --repo $repository --clobber $assets
} else {
  gh release create $tag --repo $repository --title "APK repository $tag" --notes 'Подписанный APK-репозиторий для Flint 2 GL-MT6000. Совместим только с указанными в REPOSITORY_INFO.txt OpenWrt и kernel.' $assets
}

gh release view $tag --repo $repository --json url,tagName,assets
