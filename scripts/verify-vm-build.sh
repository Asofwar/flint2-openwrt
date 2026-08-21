#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${VM_BUILDROOT:-$PROJECT_DIR/.work/openwrt-vm}"
ARTIFACT_DIR="${VM_ARTIFACT_DIR:-$PROJECT_DIR/artifacts/vm}"
if [ -f "$BUILDROOT/.config" ] && [ -d "$BUILDROOT/bin/targets/x86/64" ]; then
	IMAGE_DIR="$BUILDROOT/bin/targets/x86/64"
	CONFIG="$BUILDROOT/.config"
else
	IMAGE_DIR="$ARTIFACT_DIR"
	CONFIG="$ARTIFACT_DIR/config.buildinfo"
fi

fail() { echo "VM BUILD VERIFY FAILED: $*" >&2; exit 1; }
config_enabled() { grep -qx "CONFIG_PACKAGE_$1=y" "$CONFIG" || fail "package not selected: $1"; }
manifest_has() { grep -q "^$1 - " "$MANIFEST" || fail "image manifest lacks package: $1"; }

test -f "$CONFIG" || fail "missing resolved x86_64 config or artifact buildinfo"
test -d "$IMAGE_DIR" || fail "missing x86/64 image directory or artifact directory"
MANIFEST="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*.manifest' -print -quit)"
IMAGE="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*combined*.img.gz' -print -quit)"
test -n "$MANIFEST" || fail "x86_64 manifest is absent"
test -n "$IMAGE" || fail "x86_64 QEMU disk image is absent"

grep -qx 'CONFIG_TARGET_x86=y' "$CONFIG" || fail "wrong virtual target"
grep -qx 'CONFIG_TARGET_x86_64=y' "$CONFIG" || fail "wrong virtual subtarget"
for package in luci luci-ssl-openssl rpcd uhttpd firewall4 nftables-json kmod-nft-tproxy \
  kmod-amneziawg amneziawg-tools luci-proto-amneziawg kmod-wireguard wireguard-tools \
  podkop luci-app-podkop sing-box luci-app-vpn-dashboard ddns-scripts luci-app-ddns qrencode; do
  config_enabled "$package"
  manifest_has "$package"
done

echo "VM BUILD VERIFY PASSED: x86_64 test image has the required VPN userspace and target-matched AmneziaWG module."
