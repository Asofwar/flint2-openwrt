#!/usr/bin/env bash
# Run from a trusted Linux host after flashing. It changes only a temporary AWG link.
set -Eeuo pipefail

ROUTER="${1:?usage: $0 root@router-address}"
ssh -o StrictHostKeyChecking=accept-new "$ROUTER" 'sh -s' <<'REMOTE'
set -eu
ubus call system board
uname -a
opkg list-installed 2>/dev/null || apk list --installed
modprobe amneziawg
lsmod | grep -i amnezia
awg --version
ip link add awg-test type amneziawg
ip link show awg-test
ip link del awg-test
wifi status
ip -br link
fw4 print >/dev/null
nft list ruleset >/dev/null
REMOTE

