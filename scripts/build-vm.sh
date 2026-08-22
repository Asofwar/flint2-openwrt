#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${VM_BUILDROOT:-$PROJECT_DIR/.work/openwrt-vm}"
JOBS="${JOBS:-$(nproc)}"
OUT="$PROJECT_DIR/artifacts/vm"

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
[[ "$(git -C "$BUILDROOT" rev-parse HEAD)" = "$OPENWRT_COMMIT" ]] || { echo "OpenWrt checkout does not match the pinned commit" >&2; exit 1; }

add_feed() {
	local line="$1"
	grep -Fqx "$line" "$BUILDROOT/feeds.conf.default" || printf '%s\n' "$line" >> "$BUILDROOT/feeds.conf.default"
}

add_feed "src-git-full awg $AMNEZIAWG_FEED_REPOSITORY^$AMNEZIAWG_FEED_COMMIT"
add_feed "src-git-full podkop $PODKOP_REPOSITORY^$PODKOP_COMMIT"
add_feed "src-link flint2 $PROJECT_DIR/packages"

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
PODKOP_EGRESS_PATCH="$PROJECT_DIR/patches/podkop/0002-bind-direct-outbound-to-configured-egress.patch"
if git -C feeds/podkop apply --reverse --check "$PODKOP_EGRESS_PATCH" 2>/dev/null; then
	:
elif git -C feeds/podkop apply --check "$PODKOP_EGRESS_PATCH" 2>/dev/null; then
	git -C feeds/podkop apply "$PODKOP_EGRESS_PATCH"
else
	echo "Podkop egress patch does not apply to the pinned source" >&2
	exit 1
fi
./scripts/feeds install -a -p awg
./scripts/feeds install -a -p podkop
./scripts/feeds install luci luci-ssl-openssl luci-app-firewall luci-app-package-manager luci-app-ttyd luci-app-commands luci-app-statistics luci-app-sqm luci-app-upnp luci-app-ddns luci-app-vpn-dashboard luci-proto-wireguard luci-proto-ppp mtr-json iputils-ping iputils-tracepath qrencode
cp "$PROJECT_DIR/configs/vm-x86_64.config" .config
mkdir -p files
install -D -m 0755 "$PROJECT_DIR/files/vm/etc/uci-defaults/99-vm-network" files/etc/uci-defaults/99-vm-network
make defconfig
if [[ "${VM_PREPARE_ONLY:-0}" = "1" ]]; then
	grep -qx 'CONFIG_TARGET_x86=y' .config
	grep -qx 'CONFIG_TARGET_x86_64=y' .config
	popd >/dev/null
	echo "VM PREPARE SUCCESS: x86_64 configuration resolved without building a flash artifact."
	exit 0
fi
make download -j"$JOBS"
make -j"$JOBS" V=s
popd >/dev/null

VM_BUILDROOT="$BUILDROOT" "$PROJECT_DIR/scripts/verify-vm-build.sh"
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -type f -delete
IMAGE_DIR="$BUILDROOT/bin/targets/x86/64"
find "$IMAGE_DIR" -maxdepth 1 -type f \( -name '*combined*.img.gz' -o -name '*.manifest' -o -name 'sha256sums' \) -exec cp -f {} "$OUT" \;
cp -f "$BUILDROOT/.config" "$OUT/config.buildinfo"
sha256sum "$OUT"/* > "$OUT/SHA256SUMS"

echo "VM BUILD SUCCESS: x86_64/QEMU integration image is in $OUT and is never a GL-MT6000 flash artifact."
