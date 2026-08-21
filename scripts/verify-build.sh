#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
IMAGE_DIR="$BUILDROOT/bin/targets/mediatek/filogic"
CONFIG="$BUILDROOT/.config"

fail() { echo "VERIFY FAILED: $*" >&2; exit 1; }
has_apk() {
  test -n "$(find "$BUILDROOT/bin" -type f -name "$1" -print -quit)" || fail "missing built APK: $1"
}

test -f "$CONFIG" || fail "missing resolved .config"
test -d "$IMAGE_DIR" || fail "missing filogic image directory"
grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt6000=y' "$CONFIG" || fail "wrong device"
grep -qx 'CONFIG_PACKAGE_kmod-amneziawg=y' "$CONFIG" || fail "AmneziaWG kmod was not selected"
grep -qx 'CONFIG_PACKAGE_luci-proto-amneziawg=y' "$CONFIG" || fail "AmneziaWG LuCI protocol was not selected"
grep -qx 'CONFIG_PACKAGE_luci-i18n-amneziawg-ru=y' "$CONFIG" || fail "AmneziaWG Russian translation was not selected"
grep -qx 'CONFIG_PACKAGE_podkop=y' "$CONFIG" || fail "Podkop was not selected"
grep -qx 'CONFIG_PACKAGE_luci-app-podkop=y' "$CONFIG" || fail "Podkop LuCI was not selected"
grep -qx 'CONFIG_LUCI_LANG_ru=y' "$CONFIG" || fail "Russian LuCI language was not selected"
grep -qx 'CONFIG_PACKAGE_luci-i18n-podkop-ru=y' "$CONFIG" || fail "Podkop Russian translation was not selected"
grep -qx 'CONFIG_PACKAGE_sing-box=y' "$CONFIG" || fail "full sing-box was not selected"
grep -q '^# CONFIG_PACKAGE_sing-box-tiny is not set$' "$CONFIG" || fail "sing-box-tiny must not replace the full variant"
has_apk 'kmod-amneziawg-*.apk'
has_apk 'luci-proto-amneziawg-*.apk'
has_apk 'luci-i18n-amneziawg-ru-*.apk'
has_apk 'podkop-*.apk'
has_apk 'luci-app-podkop-*.apk'
has_apk 'luci-i18n-podkop-ru-*.apk'
has_apk 'sing-box-*.apk'
test -n "$(find "$IMAGE_DIR" -maxdepth 1 -name '*gl-mt6000*sysupgrade.bin' -print -quit)" || fail "sysupgrade image absent"
test -n "$(find "$IMAGE_DIR" -maxdepth 1 -name '*gl-mt6000*factory.bin' -print -quit)" || fail "factory image absent"
test -f "$IMAGE_DIR/sha256sums" || fail "upstream SHA256 file absent"
echo "VERIFY PASSED: GL-MT6000 images and required selected packages are present."
