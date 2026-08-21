#!/usr/bin/env bash
# Run from a trusted Linux host after flashing a GL-MT6000.
# The only state change is a temporary awg-test interface, removed by trap.
set -Eeuo pipefail

ROUTER="${1:?usage: $0 root@router-address}"

ssh -o StrictHostKeyChecking=yes "$ROUTER" 'sh -s' <<'REMOTE'
set -eu

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "RUNTIME TEST FAILED: command is missing: $1" >&2
    exit 1
  }
}

require_command ubus
require_command apk
require_command nft
require_command fw4
require_command awg
require_command sing-box
require_command podkop
require_command iw
require_command iwinfo
require_command wifi
require_command flint2-info

ubus call system board
uname -a
flint2-info
for package in luci luci-ssl-openssl luci-app-package-manager firewall4 nftables-json kmod-wireguard wireguard-tools luci-proto-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru podkop luci-app-podkop luci-i18n-podkop-ru sing-box kmod-nft-tproxy ppp ppp-mod-pppoe luci-proto-ppp wpad-openssl kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware; do
  apk info -e "$package" >/dev/null 2>&1 || {
    echo "RUNTIME TEST FAILED: APK is missing: $package" >&2
    exit 1
  }
done

modprobe amneziawg
lsmod | grep -qi '^amneziawg' || {
  echo 'RUNTIME TEST FAILED: amneziawg module is not loaded' >&2
  exit 1
}
awg --version
ip link del awg-test 2>/dev/null || true
trap 'ip link del awg-test 2>/dev/null || true' EXIT
ip link add awg-test type amneziawg
ip link show awg-test

test -f /usr/share/luci/menu.d/luci-proto-amneziawg.json
test -f /usr/share/luci/menu.d/luci-app-podkop.json
test -f /usr/lib/lua/luci/i18n/amneziawg.ru.lmo
test -f /usr/lib/lua/luci/i18n/podkop.ru.lmo

podkop show_version
sing-box version
/etc/init.d/podkop status || true
nft list ruleset >/dev/null
fw4 print >/dev/null
uci -q show network | grep -q '=interface' || {
  echo 'RUNTIME TEST FAILED: no UCI network interface sections' >&2
  exit 1
}

ip -br link
iw dev
iw phy
iwinfo
ubus call network.wireless status
dmesg | grep -Ei 'mt76|mt7915|mt7986|wed|wifi' || true
cat /proc/interrupts
cat /proc/softirqs

echo 'RUNTIME TEST PASSED: core package presence, AWG kernel module, LuCI assets, Podkop and wireless diagnostics.'
REMOTE
