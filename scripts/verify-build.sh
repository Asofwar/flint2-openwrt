#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
IMAGE_DIR="$BUILDROOT/bin/targets/mediatek/filogic"
CONFIG="$BUILDROOT/.config"
OUT="$PROJECT_DIR/artifacts"

fail() { echo "VERIFY FAILED: $*" >&2; exit 1; }
config_enabled() {
  grep -qx "CONFIG_PACKAGE_$1=y" "$CONFIG" || fail "package not selected: $1"
}
has_apk() {
  test -n "$(find "$BUILDROOT/bin" -type f -name "$1" -print -quit)" || fail "missing built APK: $1"
}
manifest_has() {
  grep -q "^$1 - " "$MANIFEST" || fail "image manifest lacks package: $1"
}

test -f "$CONFIG" || fail "missing resolved .config"
test -d "$IMAGE_DIR" || fail "missing filogic image directory"
MANIFEST="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*gl-mt6000*.manifest' -print -quit)"
SYSUPGRADE="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*gl-mt6000*sysupgrade.bin' -print -quit)"
FACTORY="$(find "$IMAGE_DIR" -maxdepth 1 -type f -name '*gl-mt6000*factory.bin' -print -quit)"
KERNEL_CONFIG="$(find "$BUILDROOT/build_dir" -path "*/linux-mediatek_filogic/linux-$OPENWRT_KERNEL/.config" -print -quit)"
FLINT2_INFO="$(find "$BUILDROOT/build_dir" -path '*/root-mediatek/usr/bin/flint2-info' -type f -print -quit)"
APK_REPOS="$(find "$BUILDROOT/build_dir" -path '*/root-mediatek/etc/apk/repositories.d/distfeeds.list' -type f -print -quit)"
ROOTFS="$(find "$BUILDROOT/build_dir" -type d -path '*/root-mediatek' -print -quit)"
test -n "$MANIFEST" || fail "GL-MT6000 manifest absent"
test -n "$SYSUPGRADE" || fail "GL-MT6000 sysupgrade image absent"
test -n "$FACTORY" || fail "GL-MT6000 factory image absent"
test -n "$KERNEL_CONFIG" || fail "resolved kernel config absent"
test -n "$FLINT2_INFO" || fail "flint2-info is absent from the root filesystem"
test -n "$APK_REPOS" || fail "official APK repository list is absent from the root filesystem"
test -n "$ROOTFS" || fail "target root filesystem is absent"
test -f "$IMAGE_DIR/sha256sums" || fail "upstream SHA256 file absent"

grep -qx 'CONFIG_TARGET_mediatek=y' "$CONFIG" || fail "wrong target"
grep -qx 'CONFIG_TARGET_mediatek_filogic=y' "$CONFIG" || fail "wrong subtarget"
grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt6000=y' "$CONFIG" || fail "wrong device"
rootfs_mib="$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=\([0-9][0-9]*\)$/\1/p' "$CONFIG")"
test -n "$rootfs_mib" || fail "rootfs size limit is undefined"
test "$(stat -c '%s' "$SYSUPGRADE")" -le "$((rootfs_mib * 1024 * 1024))" || fail "sysupgrade image exceeds configured rootfs size"

config_enabled luci
config_enabled luci-ssl-openssl
config_enabled luci-app-firewall
config_enabled luci-app-package-manager
config_enabled luci-app-ttyd
config_enabled luci-app-commands
config_enabled luci-app-statistics
config_enabled luci-app-sqm
config_enabled luci-app-upnp
config_enabled ddns-scripts
config_enabled luci-app-ddns
config_enabled luci-app-vpn-dashboard
config_enabled qrencode
config_enabled uhttpd
config_enabled uhttpd-mod-ubus
config_enabled rpcd
grep -qx 'CONFIG_LUCI_LANG_ru=y' "$CONFIG" || fail "Russian LuCI language was not selected"
config_enabled firewall4
config_enabled nftables-json
config_enabled kmod-nft-tproxy
config_enabled kmod-wireguard
config_enabled wireguard-tools
config_enabled luci-proto-wireguard
config_enabled kmod-amneziawg
config_enabled amneziawg-tools
config_enabled luci-proto-amneziawg
config_enabled luci-i18n-amneziawg-ru
config_enabled podkop
config_enabled luci-app-podkop
config_enabled luci-i18n-podkop-ru
config_enabled sing-box
grep -q '^# CONFIG_PACKAGE_sing-box-tiny is not set$' "$CONFIG" || fail "sing-box-tiny replaced full sing-box"
config_enabled kmod-mt7915e
config_enabled kmod-mt7986-firmware
config_enabled mt7986-wo-firmware
config_enabled ppp
config_enabled ppp-mod-pppoe
config_enabled luci-proto-ppp
config_enabled dnsmasq-full
config_enabled odhcpd-ipv6only
config_enabled wpad-openssl
config_enabled ip-full
config_enabled ip-bridge
config_enabled ethtool
config_enabled tcpdump-mini
config_enabled mtr-json
config_enabled iputils-ping
config_enabled iputils-tracepath
config_enabled bind-dig
config_enabled ca-bundle
config_enabled ca-certificates
config_enabled curl
config_enabled jq
config_enabled coreutils-base64
grep -qx 'CONFIG_BRIDGE_VLAN_FILTERING=y' "$KERNEL_CONFIG" || fail "kernel bridge VLAN filtering is disabled"
grep -qx 'CONFIG_VLAN_8021Q=y' "$KERNEL_CONFIG" || fail "kernel 802.1Q VLAN support is disabled"

official_apk_base="https://downloads.openwrt.org/releases/${OPENWRT_VERSION#v}"
for repository in \
  "$official_apk_base/targets/mediatek/filogic/packages/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/base/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/luci/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/packages/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/routing/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/telephony/packages.adb" \
  "$official_apk_base/packages/aarch64_cortex-a53/video/packages.adb"; do
  grep -Fqx "$repository" "$APK_REPOS" || fail "official APK repository is missing: $repository"
done
for repository in \
  "$FLINT2_APK_REPOSITORY_BASE_URL/flint2-target-packages.adb" \
  "$FLINT2_APK_REPOSITORY_BASE_URL/flint2-awg-packages.adb" \
  "$FLINT2_APK_REPOSITORY_BASE_URL/flint2-podkop-packages.adb"; do
  grep -Fqx "$repository" "$APK_REPOS" || fail "custom remote APK repository is missing: $repository"
done
test -f "$(dirname "$APK_REPOS")/../keys/flint2-custom-repository.pem" || fail "custom APK repository public key is absent"
test "$(grep -vc '^[[:space:]]*\(#\|$\)' "$APK_REPOS")" -eq 10 || fail "APK repository list is incomplete or contains unexpected entries"

has_apk "kmod-amneziawg-${OPENWRT_KERNEL}*.apk"
has_apk 'amneziawg-tools-*.apk'
has_apk 'luci-proto-amneziawg-*.apk'
has_apk 'luci-i18n-amneziawg-ru-*.apk'
has_apk 'podkop-*.apk'
has_apk 'luci-app-podkop-*.apk'
has_apk 'luci-i18n-podkop-ru-*.apk'
has_apk 'sing-box-*.apk'
has_apk 'luci-app-vpn-dashboard-*.apk'
has_apk 'qrencode-*.apk'

for package in \
  kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru \
  podkop luci-app-podkop luci-i18n-podkop-ru sing-box kmod-nft-tproxy \
  kmod-wireguard wireguard-tools luci-app-package-manager firewall4 nftables-json kmod-mt7915e \
  kmod-mt7986-firmware mt7986-wo-firmware wpad-openssl ppp ppp-mod-pppoe luci-proto-ppp \
  luci luci-ssl-openssl luci-app-firewall luci-app-package-manager luci-app-ttyd luci-app-commands \
  luci-app-statistics luci-app-sqm luci-app-upnp uhttpd uhttpd-mod-ubus rpcd dnsmasq-full odhcpd-ipv6only \
  ddns-scripts luci-app-ddns luci-app-vpn-dashboard qrencode \
  ip-full ip-bridge ethtool tcpdump-mini mtr-json iputils-ping iputils-tracepath bind-dig ca-bundle ca-certificates \
  curl jq coreutils-base64; do
  manifest_has "$package"
done

for required in \
  usr/share/luci/menu.d/luci-app-vpn-dashboard.json \
  usr/share/rpcd/acl.d/luci-app-vpn-dashboard.json \
  www/luci-static/resources/view/vpn-dashboard/dashboard.js \
  www/luci-static/resources/view/vpn-dashboard/amneziawg-server.js \
  www/luci-static/resources/view/vpn-dashboard/clients.js \
  www/luci-static/resources/view/vpn-dashboard/logs.js \
  etc/config/vpn-dashboard \
  etc/init.d/vpn-dashboard \
  lib/upgrade/keep.d/vpn-dashboard \
  usr/libexec/vpn-dashboard-sync-podkop \
  usr/libexec/vpn-dashboard-peer \
  usr/libexec/vpn-dashboard-logs \
  usr/libexec/vpn-dashboard-tunnel; do
  test -f "$ROOTFS/$required" || fail "VPN Dashboard rootfs file is absent: $required"
done
test -f "$ROOTFS/usr/lib/lua/luci/i18n/vpn-dashboard.ru.lmo" || fail "VPN Dashboard Russian translation is absent"
! grep -q 'private_key\|preshared_key' "$ROOTFS/etc/config/vpn-dashboard" || fail "VPN Dashboard default config contains a secret"
for executable in etc/init.d/vpn-dashboard etc/hotplug.d/iface/90-vpn-dashboard usr/libexec/vpn-dashboard-sync-podkop usr/libexec/vpn-dashboard-peer usr/libexec/vpn-dashboard-logs usr/libexec/vpn-dashboard-tunnel; do
  test -x "$ROOTFS/$executable" || fail "VPN Dashboard executable is not executable: $executable"
  ! grep -q "$(printf '\r')" "$ROOTFS/$executable" || fail "VPN Dashboard executable has CRLF line endings: $executable"
done

for required in config.buildinfo feeds.buildinfo version.buildinfo packages.manifest openwrt-sha256sums BUILD_INFO.txt SBOM.spdx SHA256SUMS; do
  test -f "$OUT/$required" || fail "missing collected artifact: $required"
done
grep -qx 'SPDXVersion: SPDX-2.3' "$OUT/SBOM.spdx" || fail "SBOM SPDX version is invalid"
test "$(awk '$2 == "-" { count++ } END { print count + 0 }' "$OUT/packages.manifest")" -eq "$(grep -c '^PackageName: ' "$OUT/SBOM.spdx")" || fail "SBOM package count differs from image manifest"
for field in OPENWRT_VERSION OPENWRT_COMMIT KERNEL_VERSION TARGET SUBTARGET DEVICE MT76_SOURCE MT76_COMMIT MT76_PACKAGE_VERSION MAC80211_VERSION MT7986_FIRMWARE_SOURCE MT7986_FIRMWARE_VERSION PESA_REFERENCE_BRANCH PESA_REFERENCE_COMMIT AMNEZIAWG_VERSION AMNEZIAWG_COMMIT PODKOP_VERSION PODKOP_COMMIT VPN_DASHBOARD_VERSION SING_BOX_VERSION BUILD_DATE FIRMWARE_SHA256; do
  grep -q "^$field=" "$OUT/BUILD_INFO.txt" || fail "BUILD_INFO is missing field: $field"
done
(cd "$OUT" && sha256sum -c SHA256SUMS >/dev/null) || fail "artifact SHA256SUMS mismatch"

echo "VERIFY PASSED: GL-MT6000 image, package set, kernel ABI package and collected metadata are consistent."
