#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${VM_IMAGE:-$(find "$PROJECT_DIR/artifacts/vm" -maxdepth 1 -type f -name '*squashfs-combined.img.gz' -print -quit)}"
RUN_ID="${VM_PODKOP_POLICY_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$RUN_ID"
BASE_DISK=''
ROUTER_DISK=''
EXTERNAL_DISK=''
LAN_DISK=''
REMOTE_DISK=''
PIDS=()
CONSOLE_PIDS=()

fail() { echo "VM PODKOP POLICY TEST FAILED: $*" >&2; exit 1; }
record() { printf '%s=%s\n' "$1" "$2" >> "$RESULT_DIR/summary.txt"; }
stop() { kill -0 "$1" 2>/dev/null && kill "$1" 2>/dev/null || true; }
cleanup() {
  for pid in "${PIDS[@]:-}"; do stop "$pid"; done
  for disk in "$BASE_DISK" "$ROUTER_DISK" "$EXTERNAL_DISK" "$LAN_DISK" "$REMOTE_DISK"; do [ -n "$disk" ] && rm -f "$disk"; done
}
trap cleanup EXIT

run_guest() {
  local delay="$1" hold="$2" port="$3" command="$4" log="$5"
  (
    sleep "$delay"
    (
      printf '\nroot\n'
      sleep 3
      printf ': >/tmp/vm-policy.sh\n'
      printf '%s' "$command" | base64 | fold -w 60 | while IFS= read -r chunk; do
        printf 'printf %%s %s | base64 -d >>/tmp/vm-policy.sh\n' "$chunk"
        sleep 0.05
      done
      printf 'sh -e /tmp/vm-policy.sh; status=$?; rm -f /tmp/vm-policy.sh; exit $status\n'
      sleep "$hold"
    ) | timeout "$((hold + 30))" nc -N 127.0.0.1 "$port"
  ) >"$log" 2>&1 &
  CONSOLE_PIDS+=("$!")
}

test -n "$IMAGE" && test -f "$IMAGE" || fail 'x86_64 combined image is absent; run build-vm first'
command -v qemu-system-x86_64 >/dev/null || fail 'qemu-system-x86_64 is required'
mkdir -p "$RESULT_DIR"
printf 'VIRTUAL_PODKOP_POLICY_VALIDATION=RUNNING\n' >"$RESULT_DIR/summary.txt"
BASE_DISK="$(mktemp "${TMPDIR:-/tmp}/flint2-policy-${RUN_ID}.XXXXXX.img")"
ROUTER_DISK="${BASE_DISK%.img}-router.qcow2"
EXTERNAL_DISK="${BASE_DISK%.img}-external.qcow2"
LAN_DISK="${BASE_DISK%.img}-lan.qcow2"
REMOTE_DISK="${BASE_DISK%.img}-remote.qcow2"
gzip -cd "$IMAGE" >"$BASE_DISK"
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$ROUTER_DISK" >/dev/null
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$EXTERNAL_DISK" >/dev/null
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$LAN_DISK" >/dev/null
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$REMOTE_DISK" >/dev/null

qemu-system-x86_64 -machine q35 -m 1024M -smp 2 -display none -monitor none \
  -drive "file=$ROUTER_DISK,format=qcow2,if=virtio" \
  -netdev 'user,id=wan,net=10.0.2.0/24' -device e1000,netdev=wan \
  -netdev 'socket,id=external,listen=127.0.0.1:19210' -device e1000,netdev=external,mac=52:54:00:bb:10:01 \
  -netdev 'socket,id=lan,listen=127.0.0.1:19211' -device e1000,netdev=lan,mac=52:54:00:bb:10:02 \
  -netdev 'socket,id=remote,listen=127.0.0.1:19212' -device e1000,netdev=remote,mac=52:54:00:bb:10:03 \
  -serial 'tcp:127.0.0.1:19201,server=on,wait=off' -no-reboot >"$RESULT_DIR/router-qemu.log" 2>&1 &
PIDS+=("$!")

read -r -d '' LAN_COMMAND <<'EOF' || true
set -e
ip link set br-lan down || true
ip link set eth0 nomaster
ip addr flush dev eth0
ip addr add 192.168.50.2/24 dev eth0
ip link set eth0 up
ip route add default via 192.168.50.1
for i in $(seq 1 80); do
  nslookup direct-test.example 192.168.50.1 >/tmp/direct.dns && nslookup vpn-test.example 192.168.50.1 >/tmp/vpn.dns && grep -Eq '198\.(18|19)\.' /tmp/vpn.dns && break
  sleep 2
done
direct_ip="$(awk '$NF ~ /^198\.(18|19)\./ { print $NF; exit }' /tmp/direct.dns)"
vpn_ip="$(awk '$NF ~ /^198\.(18|19)\./ { print $NF; exit }' /tmp/vpn.dns)"
test -n "$direct_ip"
test -n "$vpn_ip"
wget -T 10 -qO /tmp/direct --header='Host: direct-test.example' "http://$direct_ip/direct/"
grep -qx 'ROUTE=DIRECT' /tmp/direct
wget -T 10 -qO /tmp/vpn --header='Host: vpn-test.example' "http://$vpn_ip/vpn/"
grep -qx 'ROUTE=VPN' /tmp/vpn
echo LAN_SAME_POLICY_PASS
EOF

read -r -d '' REMOTE_COMMAND <<'EOF' || true
set -e
ifdown lan || true
ip link set br-lan down || true
ip link set eth0 nomaster
ip addr flush dev eth0
uci set network.remotelink=interface
uci set network.remotelink.device=eth0
uci set network.remotelink.proto=static
uci set network.remotelink.ipaddr=192.0.3.2
uci set network.remotelink.netmask=255.255.255.0
uci commit network
ifup remotelink
ip addr replace 192.0.3.2/24 dev eth0
ip link set eth0 up
uci set firewall.@defaults[0].input=ACCEPT
uci set firewall.@defaults[0].output=ACCEPT
uci set firewall.@defaults[0].forward=ACCEPT
uci commit firewall
/etc/init.d/firewall reload
umask 077
modprobe amneziawg
awg genkey | head -c 44 >/tmp/remote.key
awg pubkey </tmp/remote.key >/www/remote.pub
chmod 644 /www/remote.pub
uci set uhttpd.main.listen_http='192.0.3.2:80'
uci commit uhttpd
/etc/init.d/uhttpd restart
for i in $(seq 1 80); do
  wget -qO /tmp/server.pub http://192.0.3.1/server.pub && break
  sleep 2
done
test "$(wc -c </tmp/server.pub)" -eq 45
ip link add awg_remote type amneziawg
awg set awg_remote private-key /tmp/remote.key peer "$(sed -n '1p' /tmp/server.pub)" allowed-ips 0.0.0.0/0 endpoint 192.0.3.1:51820 persistent-keepalive 5
ip addr add 10.77.0.2/24 dev awg_remote
ip link set awg_remote up
ip route replace 198.18.0.0/15 dev awg_remote
for i in $(seq 1 80); do
  nslookup direct-test.example 10.77.0.1 >/tmp/direct.dns && nslookup vpn-test.example 10.77.0.1 >/tmp/vpn.dns && grep -Eq '198\.(18|19)\.' /tmp/vpn.dns && break
  sleep 2
done
direct_ip="$(awk '$NF ~ /^198\.(18|19)\./ { print $NF; exit }' /tmp/direct.dns)"
vpn_ip="$(awk '$NF ~ /^198\.(18|19)\./ { print $NF; exit }' /tmp/vpn.dns)"
test -n "$direct_ip"
test -n "$vpn_ip"
wget -T 10 -qO /tmp/direct --header='Host: direct-test.example' "http://$direct_ip/direct/"
grep -qx 'ROUTE=DIRECT' /tmp/direct
wget -T 10 -qO /tmp/vpn --header='Host: vpn-test.example' "http://$vpn_ip/vpn/"
grep -qx 'ROUTE=VPN' /tmp/vpn
echo REMOTE_SAME_POLICY_PASS
EOF

read -r -d '' EXTERNAL_COMMAND <<'EOF' || true
set -e
ifdown lan || true
ip link set br-lan down || true
ip link set eth0 nomaster
ip addr flush dev eth0
uci set network.outlink=interface
uci set network.outlink.device=eth0
uci set network.outlink.proto=static
uci set network.outlink.ipaddr=192.0.2.2
uci set network.outlink.netmask=255.255.255.0
uci commit network
ifup outlink
ip addr replace 192.0.2.2/24 dev eth0
ip link set eth0 up
uci set firewall.@defaults[0].input=ACCEPT
uci set firewall.@defaults[0].output=ACCEPT
uci set firewall.@defaults[0].forward=ACCEPT
uci commit firewall
/etc/init.d/firewall reload
uci set uhttpd.main.listen_http='192.0.2.2:80'
uci commit uhttpd
uci set dhcp.@dnsmasq[0].interface=outlink
uci add_list dhcp.@dnsmasq[0].address='/direct-test.example/100.64.0.1'
uci add_list dhcp.@dnsmasq[0].address='/vpn-test.example/10.78.0.1'
uci add_list dhcp.@dnsmasq[0].address='/openwrt.org/100.64.0.3'
uci commit dhcp
/etc/init.d/dnsmasq restart
/etc/init.d/uhttpd restart
mkdir -p /www/direct /www/vpn
printf 'ROUTE=DIRECT\n' >/www/direct/index.html
printf 'ROUTE=VPN\n' >/www/vpn/index.html
chmod 755 /www/direct /www/vpn
chmod 644 /www/direct/index.html /www/vpn/index.html
umask 077
modprobe amneziawg
awg genkey | head -c 44 >/tmp/ext.key
awg pubkey </tmp/ext.key >/www/ext.pub
awg genkey | head -c 44 >/tmp/remote.key
awg pubkey </tmp/remote.key >/www/remote.pub
chmod 644 /www/ext.pub /www/remote.pub
ip addr add 100.64.0.1/32 dev eth0
for i in $(seq 1 80); do
  wget -qO /tmp/out.pub http://192.0.2.1/out.pub && wget -qO /tmp/server.pub http://192.0.2.1/server.pub && break
  sleep 2
done
test "$(wc -c </tmp/out.pub)" -eq 45
test "$(wc -c </tmp/server.pub)" -eq 45
ip link add awg_external type amneziawg
awg set awg_external private-key /tmp/ext.key listen-port 51821 peer "$(sed -n '1p' /tmp/out.pub)" allowed-ips 0.0.0.0/0
ip addr add 10.78.0.1/24 dev awg_external
ip link set awg_external up
ip route replace 192.168.50.0/24 dev awg_external table 100
ip route replace 10.77.0.0/24 dev awg_external table 100
ip rule add from 10.78.0.1/32 table 100 priority 100
ip route replace 192.168.50.0/24 via 192.0.2.1 dev eth0
ip route replace 10.77.0.0/24 via 192.0.2.1 dev eth0 table 101
ip rule add from 100.64.0.1/32 table 101 priority 101
uci delete uhttpd.main.listen_http
uci add_list uhttpd.main.listen_http='0.0.0.0:80'
uci commit uhttpd
/etc/init.d/uhttpd restart
echo EXTERNAL_READY
EOF

read -r -d '' ROUTER_COMMAND <<'EOF' || true
set -e
modprobe amneziawg
uci set network.outlink=interface
uci set network.outlink.device=eth1
uci set network.outlink.proto=static
uci set network.outlink.ipaddr=192.0.2.1
uci set network.outlink.netmask=255.255.255.0
uci commit network
ifup outlink
ip link set eth1 up
ip addr replace 192.0.2.1/24 dev eth1
ip route replace default via 10.0.2.2 dev br-lan
ip link set eth2 up
ip link set eth3 up
uci set network.remotelink=interface
uci set network.remotelink.device=eth3
uci set network.remotelink.proto=static
uci set network.remotelink.ipaddr=192.0.3.1
uci set network.remotelink.netmask=255.255.255.0
uci commit network
ifup remotelink
ip addr replace 192.0.3.1/24 dev eth3
uci set network.testlan_device=device
uci set network.testlan_device.name=br-testlan
uci set network.testlan_device.type=bridge
uci add_list network.testlan_device.ports=eth2
uci set network.testlan=interface
uci set network.testlan.device=br-testlan
uci set network.testlan.proto=static
uci set network.testlan.ipaddr=192.168.50.1
uci set network.testlan.netmask=255.255.255.0
uci commit network
ifup testlan
uci set firewall.@defaults[0].input=ACCEPT
uci set firewall.@defaults[0].output=ACCEPT
uci set firewall.@defaults[0].forward=ACCEPT
uci commit firewall
/etc/init.d/firewall reload
uci delete uhttpd.main.listen_http
uci add_list uhttpd.main.listen_http='0.0.0.0:80'
uci commit uhttpd
/etc/init.d/uhttpd restart
umask 077
awg genkey | head -c 44 >/tmp/out.key
awg pubkey </tmp/out.key >/www/out.pub
awg genkey | head -c 44 >/tmp/server.key
awg pubkey </tmp/server.key >/www/server.pub
chmod 644 /www/out.pub /www/server.pub
for i in $(seq 1 80); do
  wget -qO /tmp/ext.pub http://192.0.2.2/ext.pub && wget -qO /tmp/remote.pub http://192.0.3.2/remote.pub && break
  sleep 2
done
test "$(wc -c </tmp/ext.pub)" -eq 45
test "$(wc -c </tmp/remote.pub)" -eq 45
ip link add awg_out type amneziawg
awg set awg_out private-key /tmp/out.key peer "$(sed -n '1p' /tmp/ext.pub)" allowed-ips 0.0.0.0/0 endpoint 192.0.2.2:51821 persistent-keepalive 5
ip addr add 10.78.0.2/24 dev awg_out
ip link set awg_out up
ip route replace 10.78.0.1/32 dev awg_out src 10.78.0.2
ip link add awg_server type amneziawg
awg set awg_server private-key /tmp/server.key listen-port 51820 peer "$(sed -n '1p' /tmp/remote.pub)" allowed-ips 10.77.0.2/32
uci set network.awgserver=interface
uci set network.awgserver.device=awg_server
uci set network.awgserver.proto=static
uci set network.awgserver.ipaddr=10.77.0.1
uci set network.awgserver.netmask=255.255.255.0
uci commit network
ifup awgserver
ip route add 100.64.0.1/32 via 192.0.2.2
for i in $(seq 1 30); do
  wget -qO /tmp/awg-preflight http://10.78.0.1/vpn/ && grep -qx 'ROUTE=VPN' /tmp/awg-preflight && break
  sleep 1
done
grep -qx 'ROUTE=VPN' /tmp/awg-preflight
awg show awg_out latest-handshakes | awk 'NF == 2 && $2 > 0 { found=1 } END { exit !found }'
for i in $(seq 1 10); do
  curl -fsS --interface awg_out --connect-timeout 3 http://10.78.0.1/vpn/ >/tmp/awg-bound-preflight && grep -qx 'ROUTE=VPN' /tmp/awg-bound-preflight && break
  sleep 1
done
grep -qx 'ROUTE=VPN' /tmp/awg-bound-preflight
for source_address in 192.168.50.1 10.77.0.1; do
  curl -fsS --interface "$source_address" --connect-timeout 3 http://10.78.0.1/vpn/ >"/tmp/awg-source-$source_address"
  grep -qx 'ROUTE=VPN' "/tmp/awg-source-$source_address"
done
uci add_list dhcp.@dnsmasq[0].interface='testlan'
uci add_list dhcp.@dnsmasq[0].interface='awgserver'
uci commit dhcp
/etc/init.d/dnsmasq restart
for i in $(seq 1 30); do
  nslookup openwrt.org 192.0.2.2 >/tmp/podkop-dns-preflight && grep -q '100.64.0.3' /tmp/podkop-dns-preflight && break
  sleep 1
done
grep -q '100.64.0.3' /tmp/podkop-dns-preflight
uci set podkop.settings.source_network_interfaces='br-testlan awg_server'
uci set podkop.settings.dont_touch_dhcp=0
uci set podkop.settings.shutdown_correctly=1
uci set podkop.settings.enable_output_network_interface=1
uci set podkop.settings.output_network_interface=eth1
uci set podkop.settings.dns_type=udp
uci set podkop.settings.dns_server=192.0.2.2
uci set podkop.settings.bootstrap_dns_server=192.0.2.2
uci set podkop.main.connection_type=vpn
uci set podkop.main.interface=awg_out
uci delete podkop.main.community_lists
uci set podkop.main.user_domain_list_type=text
uci set podkop.main.user_domains_text=vpn-test.example
uci set podkop.direct=section
uci set podkop.direct.connection_type=exclusion
uci set podkop.direct.user_domain_list_type=text
uci set podkop.direct.user_domains_text=direct-test.example
uci commit podkop
/usr/bin/podkop start
SINGBOX_CONFIG="$(uci get sing-box.main.conffile)"
test -s "$SINGBOX_CONFIG"
sing-box -c "$SINGBOX_CONFIG" check
jq -e '.outbounds[] | select(.tag == "direct-out") | .bind_interface == "eth1"' "$SINGBOX_CONFIG" >/dev/null
jq -e '(.outbounds[] | select(.tag == "main-out") | .bind_interface == "awg_out")' "$SINGBOX_CONFIG" >/dev/null
jq -e '(.route | has("default_interface")) | not' "$SINGBOX_CONFIG" >/dev/null
/usr/bin/podkop check_sing_box | tee /tmp/sing-box-status.json
grep -Eq '"sing_box_installed":[[:space:]]*1' /tmp/sing-box-status.json
grep -Eq '"sing_box_process_running":[[:space:]]*1' /tmp/sing-box-status.json
grep -Eq '"sing_box_ports_listening":[[:space:]]*1' /tmp/sing-box-status.json
test "$(uci get dhcp.@dnsmasq[0].server)" = '127.0.0.42'
for i in $(seq 1 30); do
  nslookup vpn-test.example 127.0.0.1 >/tmp/router-vpn.dns && grep -Eq '198\.(18|19)\.' /tmp/router-vpn.dns && break
  sleep 1
done
grep -Eq '198\.(18|19)\.' /tmp/router-vpn.dns
echo ROUTER_PODKOP_DNS_READY
nft list set inet PodkopTable interfaces >/tmp/interfaces.nft
grep -qw br-testlan /tmp/interfaces.nft
grep -qw awg_server /tmp/interfaces.nft
echo ROUTER_POLICY_READY
EOF
sleep 2
qemu-system-x86_64 -machine q35 -m 768M -smp 2 -display none -monitor none \
  -drive "file=$EXTERNAL_DISK,format=qcow2,if=virtio" \
  -netdev 'socket,id=external,connect=127.0.0.1:19210' -device e1000,netdev=external,mac=52:54:00:bb:10:11 \
  -serial 'tcp:127.0.0.1:19202,server=on,wait=off' -no-reboot >"$RESULT_DIR/external-qemu.log" 2>&1 &
PIDS+=("$!")
qemu-system-x86_64 -machine q35 -m 512M -smp 2 -display none -monitor none \
  -drive "file=$LAN_DISK,format=qcow2,if=virtio" \
  -netdev 'socket,id=lan,connect=127.0.0.1:19211' -device e1000,netdev=lan,mac=52:54:00:bb:10:21 \
  -serial 'tcp:127.0.0.1:19203,server=on,wait=off' -no-reboot >"$RESULT_DIR/lan-qemu.log" 2>&1 &
PIDS+=("$!")
qemu-system-x86_64 -machine q35 -m 512M -smp 2 -display none -monitor none \
  -drive "file=$REMOTE_DISK,format=qcow2,if=virtio" \
  -netdev 'socket,id=remote,connect=127.0.0.1:19212' -device e1000,netdev=remote,mac=52:54:00:bb:10:31 \
  -serial 'tcp:127.0.0.1:19204,server=on,wait=off' -no-reboot >"$RESULT_DIR/remote-qemu.log" 2>&1 &
PIDS+=("$!")
run_guest 40 70 19202 "$EXTERNAL_COMMAND" "$RESULT_DIR/external.serial.log"
run_guest 50 180 19201 "$ROUTER_COMMAND" "$RESULT_DIR/router.serial.log"
run_guest 110 80 19203 "$LAN_COMMAND" "$RESULT_DIR/lan.serial.log"
run_guest 40 180 19204 "$REMOTE_COMMAND" "$RESULT_DIR/remote.serial.log"
for pid in "${CONSOLE_PIDS[@]}"; do wait "$pid" || true; done
for file in router external lan remote; do tr -d '\r' <"$RESULT_DIR/$file.serial.log" >"$RESULT_DIR/$file.serial.normalized.log"; done
for marker in ROUTER_PODKOP_DNS_READY ROUTER_POLICY_READY LAN_SAME_POLICY_PASS REMOTE_SAME_POLICY_PASS; do grep -R -Fxq "$marker" "$RESULT_DIR"/*.normalized.log || fail "missing marker: $marker"; done
record PODKOP_POLICY_LAN PASS
record PODKOP_POLICY_REMOTE_AWG PASS
record PODKOP_POLICY_SAME PASS
printf 'VIRTUAL_PODKOP_POLICY_VALIDATION=PASS\n' >>"$RESULT_DIR/summary.txt"
