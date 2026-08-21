#!/bin/sh
set -eu

pkg_version() {
  pkg="$1"
  if command -v apk >/dev/null 2>&1; then
    if apk info -e "$pkg" >/dev/null 2>&1; then
      apk info -v "$pkg" 2>/dev/null | sed -n '1p'
    else
      printf 'not installed'
    fi
  else
    printf 'unknown (APK is unavailable)'
  fi
}

module_state() {
  if grep -q "^$1 " /proc/modules 2>/dev/null; then
    printf 'loaded'
  else
    printf 'not loaded or built-in'
  fi
}

uci_value() {
  uci -q get "$1" 2>/dev/null || printf 'not set'
}

if [ -r /etc/flint2-build-info ]; then
  . /etc/flint2-build-info
else
  OPENWRT_VERSION="$(. /etc/openwrt_release 2>/dev/null; printf '%s' "${DISTRIB_RELEASE:-unknown}")"
  KERNEL_VERSION="$(uname -r)"
  TARGET=unknown
  SUBTARGET=unknown
  DEVICE=unknown
fi

printf '%s\n' '=== FLINT 2 INFO ==='
printf 'OpenWrt: %s\n' "$OPENWRT_VERSION"
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Target: %s/%s\n' "$TARGET" "$SUBTARGET"
printf 'Device: %s\n' "$DEVICE"
printf 'mt76: %s\n' "$(pkg_version kmod-mt7915e)"
printf 'Wi-Fi firmware: %s\n' "$(pkg_version mt7986-wo-firmware)"
printf 'mac80211: %s\n' "$(pkg_version kmod-mac80211)"
printf 'wpad/hostapd: %s\n' "$(pkg_version wpad-openssl)"
printf 'AmneziaWG: %s\n' "$(pkg_version amneziawg-tools)"
printf 'Podkop: %s\n' "$(pkg_version podkop)"
printf 'sing-box: %s\n' "$(pkg_version sing-box)"
printf 'WED module: %s\n' "$(module_state mtk_wed)"
printf 'PPE module: %s\n' "$(module_state mtk_ppe_offload)"
printf 'Flow offload: %s\n' "$(uci_value firewall.@defaults[0].flow_offloading)"
printf 'Hardware flow offload: %s\n' "$(uci_value firewall.@defaults[0].flow_offloading_hw)"
