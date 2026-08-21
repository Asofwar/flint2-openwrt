#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
JOBS="${JOBS:-$(nproc)}"
CUSTOM_WIRELESS_REGDB="${CUSTOM_WIRELESS_REGDB:-0}"

case "$CUSTOM_WIRELESS_REGDB" in
  0|1) ;;
  *) echo "CUSTOM_WIRELESS_REGDB must be 0 or 1" >&2; exit 2;;
esac
export CUSTOM_WIRELESS_REGDB

require() { command -v "$1" >/dev/null || { echo "missing required command: $1" >&2; exit 1; }; }
require git
require make
require sha256sum

if [[ ! -d "$BUILDROOT/.git" ]]; then
  mkdir -p "$(dirname "$BUILDROOT")"
  git clone "$OPENWRT_REPOSITORY" "$BUILDROOT"
fi

git -C "$BUILDROOT" fetch --tags --force "$OPENWRT_REPOSITORY"
git -C "$BUILDROOT" checkout --detach "$OPENWRT_COMMIT"
if [[ "$(git -C "$BUILDROOT" rev-parse HEAD)" != "$OPENWRT_COMMIT" ]]; then
  echo "OpenWrt checkout does not match the pinned commit" >&2
  exit 1
fi

REGDB_PACKAGE_DIR="$BUILDROOT/package/firmware/wireless-regdb"
REGDB_PATCH="$PROJECT_DIR/patches/openwrt/0001-wireless-regdb-run-customizer.patch"
if [[ "$CUSTOM_WIRELESS_REGDB" = 1 ]]; then
  install -D -m 0755 "$PROJECT_DIR/scripts/customize-wireless-regdb.py" "$REGDB_PACKAGE_DIR/customize-wireless-regdb.py"
  if git -C "$BUILDROOT" apply --ignore-space-change --reverse --check "$REGDB_PATCH" 2>/dev/null; then
    :
  elif git -C "$BUILDROOT" apply --ignore-space-change --check "$REGDB_PATCH" 2>/dev/null; then
    git -C "$BUILDROOT" apply --ignore-space-change "$REGDB_PATCH"
  else
    echo "wireless-regdb customization patch does not apply to the pinned OpenWrt source" >&2
    exit 1
  fi
elif git -C "$BUILDROOT" apply --ignore-space-change --reverse --check "$REGDB_PATCH" 2>/dev/null; then
  git -C "$BUILDROOT" apply --ignore-space-change --reverse "$REGDB_PATCH"
fi

if ! grep -Fqx "src-git-full awg $AMNEZIAWG_FEED_REPOSITORY^$AMNEZIAWG_FEED_COMMIT" "$BUILDROOT/feeds.conf.default"; then
cat >> "$BUILDROOT/feeds.conf.default" <<EOF
src-git-full awg $AMNEZIAWG_FEED_REPOSITORY^$AMNEZIAWG_FEED_COMMIT
src-git-full podkop $PODKOP_REPOSITORY^$PODKOP_COMMIT
EOF
fi

pushd "$BUILDROOT" >/dev/null
./scripts/feeds update -a
SINGBOX_PATCH="$PROJECT_DIR/patches/packages/0001-sing-box-tiny-do-not-provide-full-variant.patch"
if git -C feeds/packages apply --reverse --check "$SINGBOX_PATCH" 2>/dev/null; then
  :
elif git -C feeds/packages apply --check "$SINGBOX_PATCH" 2>/dev/null; then
  git -C feeds/packages apply "$SINGBOX_PATCH"
else
  echo "sing-box compatibility patch does not apply to the pinned source" >&2
  exit 1
fi
PODKOP_PATCH="$PROJECT_DIR/patches/podkop/0001-luci-25.12-single-buildpackage.patch"
if git -C feeds/podkop apply --reverse --check "$PODKOP_PATCH" 2>/dev/null; then
  :
elif git -C feeds/podkop apply --check "$PODKOP_PATCH" 2>/dev/null; then
  git -C feeds/podkop apply "$PODKOP_PATCH"
else
  echo "Podkop compatibility patch does not apply to the pinned source" >&2
  exit 1
fi
./scripts/feeds install -a -p awg
./scripts/feeds install -a -p podkop
./scripts/feeds install luci luci-ssl-openssl luci-app-firewall luci-app-package-manager luci-app-ttyd luci-app-commands luci-app-statistics luci-app-sqm luci-app-upnp luci-proto-wireguard luci-proto-ppp mtr-json iputils-ping iputils-tracepath
cp "$PROJECT_DIR/configs/gl-mt6000.config" .config
make defconfig
mkdir -p files
cp -a "$PROJECT_DIR/files/." files/
install -D -m 0755 "$PROJECT_DIR/scripts/flint2-info.sh" files/usr/bin/flint2-info
mkdir -p files/etc/apk/repositories.d
cat > files/etc/apk/repositories.d/distfeeds.list <<EOF
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/targets/mediatek/filogic/packages/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/packages/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/routing/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/telephony/packages.adb
https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}/packages/aarch64_cortex-a53/video/packages.adb
$FLINT2_APK_REPOSITORY_BASE_URL/flint2-target-packages.adb
$FLINT2_APK_REPOSITORY_BASE_URL/flint2-awg-packages.adb
$FLINT2_APK_REPOSITORY_BASE_URL/flint2-podkop-packages.adb
EOF
cat > files/etc/flint2-build-info <<EOF
OPENWRT_VERSION=$OPENWRT_VERSION
OPENWRT_COMMIT=$OPENWRT_COMMIT
KERNEL_VERSION=$OPENWRT_KERNEL
TARGET=mediatek
SUBTARGET=filogic
DEVICE=glinet_gl-mt6000
MT76_SOURCE=$OPENWRT_REPOSITORY
MT76_COMMIT=$OPENWRT_COMMIT
MT7986_FIRMWARE_SOURCE=$OPENWRT_REPOSITORY
PESA_REFERENCE_BRANCH=$PESA_OPENWRT_BRANCH
PESA_REFERENCE_COMMIT=$PESA_OPENWRT_COMMIT
AMNEZIAWG_VERSION=$AMNEZIAWG_KERNEL_MODULE_VERSION
AMNEZIAWG_COMMIT=$AMNEZIAWG_FEED_COMMIT
PODKOP_VERSION=$PODKOP_VERSION
PODKOP_COMMIT=$PODKOP_COMMIT
CUSTOM_WIRELESS_REGDB=$CUSTOM_WIRELESS_REGDB
EOF
make download -j"$JOBS"
make -j"$JOBS" V=s
popd >/dev/null

if [[ "$CUSTOM_WIRELESS_REGDB" = 1 ]]; then
  BUILDROOT="$BUILDROOT" bash "$PROJECT_DIR/scripts/verify-custom-regdb.sh"
fi
BUILDROOT="$BUILDROOT" "$PROJECT_DIR/scripts/collect-artifacts.sh"
BUILDROOT="$BUILDROOT" "$PROJECT_DIR/scripts/verify-build.sh"
