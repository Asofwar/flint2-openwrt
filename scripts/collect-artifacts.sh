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
SYSUPGRADE="$(find "$OUT" -maxdepth 1 -type f -name '*gl-mt6000*sysupgrade.bin' -print -quit)"
MANIFEST="$OUT/$(basename "$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*gl-mt6000*.manifest' -print -quit)")"
test -f "$IMAGE_DIR/sha256sums" || fail "missing upstream sha256sums"
# Windows filesystems are case-insensitive: keep the upstream file distinct
# from the aggregate SHA256SUMS generated below.
cp -f "$IMAGE_DIR/sha256sums" "$OUT/openwrt-sha256sums"
cp -f "$BUILDROOT/.config" "$OUT/config.buildinfo"
cp -f "$MANIFEST" "$OUT/packages.manifest"

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

manifest_version() {
  awk -v package="$1" '$1 == package && $2 == "-" { print $3; exit }' "$OUT/packages.manifest"
}

{
  echo "OPENWRT_VERSION=$OPENWRT_VERSION"
  echo "OPENWRT_COMMIT=$OPENWRT_COMMIT"
  echo "KERNEL_VERSION=$OPENWRT_KERNEL"
  echo "TARGET=mediatek"
  echo "SUBTARGET=filogic"
  echo "ARCHITECTURE=aarch64_cortex-a53"
  echo "DEVICE=glinet_gl-mt6000"
  echo "MT76_SOURCE=$OPENWRT_REPOSITORY"
  echo "MT76_COMMIT=$OPENWRT_COMMIT"
  echo "MT76_PACKAGE_VERSION=$(manifest_version kmod-mt7915e)"
  echo "MAC80211_VERSION=$(manifest_version kmod-mac80211)"
  echo "MT7986_FIRMWARE_SOURCE=$OPENWRT_REPOSITORY"
  echo "MT7986_FIRMWARE_VERSION=$(manifest_version mt7986-wo-firmware)"
  echo "PESA_REFERENCE_BRANCH=$PESA_OPENWRT_BRANCH"
  echo "PESA_REFERENCE_COMMIT=$PESA_OPENWRT_COMMIT"
  echo "AMNEZIAWG_VERSION=$AMNEZIAWG_KERNEL_MODULE_VERSION"
  echo "AMNEZIAWG_COMMIT=$AMNEZIAWG_FEED_COMMIT"
  echo "PODKOP_VERSION=$PODKOP_VERSION"
  echo "PODKOP_COMMIT=$PODKOP_COMMIT"
  echo "SING_BOX_VERSION=$(manifest_version sing-box)"
  echo "BUILD_DATE=$(git -C "$BUILDROOT" show -s --format=%cI HEAD)"
  echo "FIRMWARE_SHA256=$(sha256sum "$SYSUPGRADE" | awk '{print $1}')"
} > "$OUT/BUILD_INFO.txt"

(
  cd "$OUT"
  find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -printf '%f\0' \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum > SHA256SUMS
)
