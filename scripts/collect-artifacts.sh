#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
IMAGE_DIR="$BUILDROOT/bin/targets/mediatek/filogic"
OUT="$PROJECT_DIR/artifacts"

fail() { echo "ARTIFACT COLLECTION FAILED: $*" >&2; exit 1; }
test -f "$BUILDROOT/.config" || fail "missing resolved .config"
test -d "$IMAGE_DIR" || fail "missing GL-MT6000 image directory"

mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -type f -delete

copy_one() {
  local pattern="$1"
  local src
  src="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name "$pattern" -print -quit)"
  test -n "$src" || fail "missing image file: $pattern"
  cp -f "$src" "$OUT/"
}

copy_one '*gl-mt6000*factory.bin'
copy_one '*gl-mt6000*sysupgrade.bin'
copy_one '*gl-mt6000*.manifest'
test -f "$IMAGE_DIR/sha256sums" || fail "missing upstream sha256sums"
# Windows filesystems are case-insensitive: keep the upstream file distinct
# from the aggregate SHA256SUMS generated below.
cp -f "$IMAGE_DIR/sha256sums" "$OUT/openwrt-sha256sums"
cp -f "$BUILDROOT/.config" "$OUT/config.buildinfo"
cp -f "$IMAGE_DIR/$(basename "$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*gl-mt6000*.manifest' -print -quit)")" "$OUT/packages.manifest"

{
  echo "openwrt=$OPENWRT_COMMIT"
  while IFS= read -r -d '' feed; do
    if [[ -d "$feed/.git" ]]; then
      printf '%s=%s\n' "feed.$(basename "$feed")" "$(git -C "$feed" rev-parse HEAD)"
    fi
  done < <(find "$BUILDROOT/feeds" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
} > "$OUT/feeds.buildinfo"

{
  echo "openwrt_version=$OPENWRT_VERSION"
  echo "openwrt_commit=$OPENWRT_COMMIT"
  echo "kernel=$OPENWRT_KERNEL"
  echo "target=mediatek/filogic"
  echo "architecture=aarch64_cortex-a53"
  echo "device=glinet_gl-mt6000"
  echo "package_format=apk"
  echo "amneziawg_feed_commit=$AMNEZIAWG_FEED_COMMIT"
  echo "podkop_commit=$PODKOP_COMMIT"
} > "$OUT/version.buildinfo"

{
  echo "Flint 2 custom OpenWrt build"
  echo "device=glinet_gl-mt6000"
  echo "target=mediatek/filogic"
  echo "architecture=aarch64_cortex-a53"
  echo "openwrt_commit=$OPENWRT_COMMIT"
  echo "kernel=$OPENWRT_KERNEL"
  echo "files=$(find "$OUT" -maxdepth 1 -type f -printf '%f ' | LC_ALL=C sort | tr '\n' ' ')"
} > "$OUT/BUILD_INFO.txt"

(
  cd "$OUT"
  find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -printf '%f\0' \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum > SHA256SUMS
)
