#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
IMAGE_DIR="$BUILDROOT/bin/targets/mediatek/filogic"
OUT="$PROJECT_DIR/artifacts"

test -d "$IMAGE_DIR"
mkdir -p "$OUT"
find "$IMAGE_DIR" -maxdepth 1 -type f \( -name '*gl-mt6000*factory.bin' -o -name '*gl-mt6000*sysupgrade.bin' -o -name 'sha256sums' -o -name '*gl-mt6000*.manifest' \) -print0 | xargs -0 -r -I{} cp -f {} "$OUT/"
test -n "$(find "$OUT" -maxdepth 1 -type f -name '*gl-mt6000*sysupgrade.bin' -print -quit)"
( cd "$OUT" && sha256sum * > SHA256SUMS )

