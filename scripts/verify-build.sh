#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
IMAGE_DIR="$BUILDROOT/bin/targets/mediatek/filogic"
CONFIG="$BUILDROOT/.config"

fail() { echo "VERIFY FAILED: $*" >&2; exit 1; }
test -f "$CONFIG" || fail "missing resolved .config"
test -d "$IMAGE_DIR" || fail "missing filogic image directory"
grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt6000=y' "$CONFIG" || fail "wrong device"
grep -qx 'CONFIG_PACKAGE_kmod-amneziawg=y' "$CONFIG" || fail "AmneziaWG kmod was not selected"
grep -qx 'CONFIG_PACKAGE_luci-proto-amneziawg=y' "$CONFIG" || fail "AmneziaWG LuCI protocol was not selected"
grep -qx 'CONFIG_PACKAGE_podkop=y' "$CONFIG" || fail "Podkop was not selected"
grep -qx 'CONFIG_PACKAGE_luci-app-podkop=y' "$CONFIG" || fail "Podkop LuCI was not selected"
test -n "$(find "$IMAGE_DIR" -maxdepth 1 -name '*gl-mt6000*sysupgrade.bin' -print -quit)" || fail "sysupgrade image absent"
test -n "$(find "$IMAGE_DIR" -maxdepth 1 -name '*gl-mt6000*factory.bin' -print -quit)" || fail "factory image absent"
test -f "$IMAGE_DIR/sha256sums" || fail "upstream SHA256 file absent"
echo "VERIFY PASSED: GL-MT6000 images and required selected packages are present."

