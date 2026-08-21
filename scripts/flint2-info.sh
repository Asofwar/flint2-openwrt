#!/usr/bin/env bash
set -Eeuo pipefail
ROUTER="${1:?usage: $0 root@router-address}"
ssh -o StrictHostKeyChecking=accept-new "$ROUTER" 'ubus call system board; cat /proc/cpuinfo; ip -br link; wifi status; dmesg | grep -Ei "mt79|mt798|rtl822|wed|ppe" || true'

