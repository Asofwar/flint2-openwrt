#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${VM_IMAGE:-$(find "$PROJECT_DIR/artifacts/vm" -maxdepth 1 -type f -name '*squashfs-combined.img.gz' -print -quit)}"
RUN_ID="${VM_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$RUN_ID"
HTTP_PORT="${VM_HTTP_PORT:-18080}"
SERIAL_PORT="${VM_SERIAL_PORT:-19001}"
REMOTE_SERIAL_PORT="${VM_REMOTE_SERIAL_PORT:-19002}"
PEER_LINK_PORT="${VM_PEER_LINK_PORT:-19010}"
VM_IP='10.0.2.15'
QEMU_PID=''
CONSOLE_PID=''
REMOTE_QEMU_PID=''
REMOTE_CONSOLE_PID=''
VM_BASE_DISK=''
VM_ROUTER_DISK=''
VM_REMOTE_DISK=''

fail() { echo "VM TEST FAILED: $*" >&2; exit 1; }
record() { printf '%s=%s\n' "$1" "$2" >> "$RESULT_DIR/summary.txt"; }
cleanup() {
	if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
		kill "$QEMU_PID" 2>/dev/null || true
		wait "$QEMU_PID" 2>/dev/null || true
	fi
	if [ -n "$CONSOLE_PID" ] && kill -0 "$CONSOLE_PID" 2>/dev/null; then
		kill "$CONSOLE_PID" 2>/dev/null || true
		wait "$CONSOLE_PID" 2>/dev/null || true
	fi
	for pid in "$REMOTE_QEMU_PID" "$REMOTE_CONSOLE_PID"; do
		[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
	done
	for disk in "$VM_BASE_DISK" "$VM_ROUTER_DISK" "$VM_REMOTE_DISK"; do
		[ -n "$disk" ] && rm -f "$disk"
	done
}
trap cleanup EXIT

test -n "$IMAGE" && test -f "$IMAGE" || fail 'x86_64 combined image is absent; run build-vm first'
command -v qemu-system-x86_64 >/dev/null || fail 'qemu-system-x86_64 is required'
command -v qemu-img >/dev/null || fail 'qemu-img is required'
command -v curl >/dev/null || fail 'curl is required'

mkdir -p "$RESULT_DIR"
printf 'VIRTUAL_RUNTIME_VALIDATION=RUNNING\n' > "$RESULT_DIR/summary.txt"
VM_BASE_DISK="$(mktemp "${TMPDIR:-/tmp}/flint2-vm-${RUN_ID}.XXXXXX.img")"
VM_ROUTER_DISK="${VM_BASE_DISK%.img}-router.qcow2"
VM_REMOTE_DISK="${VM_BASE_DISK%.img}-remote.qcow2"
gzip -cd "$IMAGE" > "$VM_BASE_DISK"
qemu-img create -f qcow2 -b "$VM_BASE_DISK" -F raw "$VM_ROUTER_DISK" >/dev/null
qemu-img create -f qcow2 -b "$VM_BASE_DISK" -F raw "$VM_REMOTE_DISK" >/dev/null

qemu-system-x86_64 \
	-machine q35 -m 768M -smp 2 -display none -monitor none \
	-drive "file=$VM_ROUTER_DISK,format=qcow2,if=virtio" \
	-netdev "user,id=wan,net=10.0.2.0/24,hostfwd=tcp::$HTTP_PORT-$VM_IP:80" \
	-device e1000,netdev=wan \
	-netdev "socket,id=peerlink,listen=127.0.0.1:$PEER_LINK_PORT" \
	-device e1000,netdev=peerlink \
	-serial "tcp:127.0.0.1:$SERIAL_PORT,server=on,wait=off" \
	-no-reboot > "$RESULT_DIR/qemu.log" 2>&1 &
QEMU_PID=$!

sleep 2
kill -0 "$QEMU_PID" 2>/dev/null || fail 'QEMU router did not start the peer link'
qemu-system-x86_64 \
	-machine q35 -m 512M -smp 2 -display none -monitor none \
	-drive "file=$VM_REMOTE_DISK,format=qcow2,if=virtio" \
	-netdev "socket,id=peerlink,connect=127.0.0.1:$PEER_LINK_PORT" \
	-device e1000,netdev=peerlink \
	-serial "tcp:127.0.0.1:$REMOTE_SERIAL_PORT,server=on,wait=off" \
	-no-reboot > "$RESULT_DIR/remote-qemu.log" 2>&1 &
REMOTE_QEMU_PID=$!

GUEST_COMMAND='modprobe amneziawg && ip link add awg_probe type amneziawg && awg show awg_probe >/dev/null && ip link del awg_probe && echo AWG_MODULE_PASS
uci set network.peerlink=interface
uci set network.peerlink.device=eth1
uci set network.peerlink.proto=static
uci set network.peerlink.ipaddr=192.0.2.1
uci set network.peerlink.netmask=255.255.255.0
uci commit network
ifup peerlink
ip link set eth1 up
ip addr replace 192.0.2.1/24 dev eth1
uci set firewall.vm_peerlink=zone
uci set firewall.vm_peerlink.name=vm_peerlink
uci set firewall.vm_peerlink.network=peerlink
uci set firewall.vm_peerlink.input=ACCEPT
uci set firewall.vm_peerlink.output=ACCEPT
uci set firewall.vm_peerlink.forward=REJECT
uci set firewall.vm_peerlink_awg_server=rule
uci set firewall.vm_peerlink_awg_server.name=Allow-AmneziaWG-from-VM-peer
uci set firewall.vm_peerlink_awg_server.src=vm_peerlink
uci set firewall.vm_peerlink_awg_server.proto=udp
uci set firewall.vm_peerlink_awg_server.dest_port=51820
uci set firewall.vm_peerlink_awg_server.target=ACCEPT
uci commit firewall
/etc/init.d/firewall reload
uci set vpn-dashboard.main.enabled=1
uci set vpn-dashboard.main.endpoint_mode=manual
uci set vpn-dashboard.main.endpoint_host=192.0.2.1
uci commit vpn-dashboard
/etc/init.d/vpn-dashboard restart
sleep 8
ifstatus awg_server | grep -q "\"up\": true" && echo AWG_SERVER_PASS
device="$(ubus call network.interface.awg_server status | jsonfilter -e "@.l3_device")"
test -n "$device" && /usr/libexec/vpn-dashboard-sync-podkop "$device" && uci -q get podkop.settings.source_network_interfaces | grep -qw "$device" && echo PODKOP_SOURCE_PASS
/usr/libexec/vpn-dashboard-peer create vmpeer full >/tmp/vmpeer.conf
cp /tmp/vmpeer.conf /www/vmpeer.conf
chmod 0644 /www/vmpeer.conf
echo REMOTE_EXPORT_READY
sed -e "/^PrivateKey = /d" -e "/^PresharedKey = /d" /tmp/vmpeer.conf >/tmp/vmpeer.safe
echo CLIENT_CONFIG_SAFE_BEGIN
cat /tmp/vmpeer.safe
echo CLIENT_CONFIG_SAFE_END
awk -F " = " "/^[A-Za-z]/{print \$1}" /tmp/vmpeer.conf >/tmp/vmpeer.fields
grep -qx PrivateKey /tmp/vmpeer.fields && grep -qx Address /tmp/vmpeer.fields
grep -qx DNS /tmp/vmpeer.fields && grep -qx MTU /tmp/vmpeer.fields
grep -qx PublicKey /tmp/vmpeer.fields && grep -qx PresharedKey /tmp/vmpeer.fields
grep -qx Endpoint /tmp/vmpeer.fields && grep -qx AllowedIPs /tmp/vmpeer.fields
grep -q "^DNS = 10.77.0.1" /tmp/vmpeer.safe && grep -q "^Endpoint = 192.0.2.1:51820" /tmp/vmpeer.safe && grep -q "^AllowedIPs = 0.0.0.0/0" /tmp/vmpeer.safe && echo PEER_EXPORT_PASS
/usr/libexec/vpn-dashboard-peer qr vmpeer >/tmp/vmpeer.qr && test -s /tmp/vmpeer.qr && echo QR_PASS
echo DASHBOARD_API_BEGIN
/usr/libexec/vpn-dashboard-peer dashboard
echo DASHBOARD_API_END
/usr/libexec/vpn-dashboard-peer status >/tmp/vmpeer.status && ! grep -Eqi "private_key|preshared_key|privatekey|presharedkey|password|secret" /tmp/vmpeer.status && echo STATUS_SECRET_SAFE
sleep 55
/usr/libexec/vpn-dashboard-peer enable vmpeer 0 && uci get vpn-dashboard.peer_vmpeer.enabled | grep -qx 0 && /usr/libexec/vpn-dashboard-peer enable vmpeer 1 && uci get vpn-dashboard.peer_vmpeer.enabled | grep -qx 1 && echo PEER_TOGGLE_PASS
/usr/libexec/vpn-dashboard-peer delete vmpeer && ! uci -q get vpn-dashboard.peer_vmpeer && test ! -e /etc/vpn-dashboard/peers/vmpeer && echo PEER_DELETE_PASS
rm -f /tmp/vmpeer.conf /tmp/vmpeer.safe /tmp/vmpeer.fields /tmp/vmpeer.qr /tmp/vmpeer.status
echo GUEST_TEST_COMPLETE'
(
	sleep 35
	(
		printf '\nroot\n'
		sleep 3
		printf '%s\n' "$GUEST_COMMAND" | while IFS= read -r line; do
			printf '%s\n' "$line"
			sleep 0.2
		done
		sleep 130
	) | timeout 210 nc -N 127.0.0.1 "$SERIAL_PORT"
) > "$RESULT_DIR/openwrt.serial.log" 2>&1 &
CONSOLE_PID=$!

REMOTE_GUEST_COMMAND='set -e
ip link set br-lan down
ip link set eth0 nomaster
ip addr flush dev eth0
ip addr add 192.0.2.2/24 dev eth0
ip link set eth0 up
sleep 3
for attempt in $(seq 1 30); do
  wget -qO /tmp/vmpeer.conf http://192.0.2.1/vmpeer.conf && grep -q "^PrivateKey = " /tmp/vmpeer.conf && grep -q "^PresharedKey = " /tmp/vmpeer.conf && break
  sleep 2
done
grep -q "^PrivateKey = " /tmp/vmpeer.conf && grep -q "^PresharedKey = " /tmp/vmpeer.conf
client_private="$(sed -n "s/^PrivateKey = //p" /tmp/vmpeer.conf)"
server_public="$(sed -n "s/^PublicKey = //p" /tmp/vmpeer.conf)"
preshared_key="$(sed -n "s/^PresharedKey = //p" /tmp/vmpeer.conf)"
test -n "$client_private" && test -n "$server_public" && test -n "$preshared_key"
modprobe amneziawg
printf '%s' "$client_private" >/tmp/vm-remote-private.key
printf '%s' "$preshared_key" >/tmp/vm-remote-psk.key
private_length="$(wc -c </tmp/vm-remote-private.key)"
psk_length="$(wc -c </tmp/vm-remote-psk.key)"
echo REMOTE_KEY_LENGTHS="$private_length,$psk_length"
[ "$private_length" -eq 44 ]
[ "$psk_length" -eq 44 ]
ip link add awg_remote type amneziawg
awg set awg_remote private-key /tmp/vm-remote-private.key peer "$server_public" preshared-key /tmp/vm-remote-psk.key allowed-ips 0.0.0.0/0 endpoint 192.0.2.1:51820 persistent-keepalive 5
ip addr add 10.77.0.2/24 dev awg_remote
ip link set awg_remote up
echo REMOTE_AWG_CONFIG_PASS
ip route replace 10.77.0.1/32 dev awg_remote
ping -c 1 -W 2 10.77.0.1 >/tmp/remote-ping.txt || true
sleep 10
awg show awg_remote latest-handshakes | awk "NF == 2 && \$2 > 0 { found=1 } END { exit !found }"
echo REMOTE_AWG_HANDSHAKE_PASS
nslookup localhost 10.77.0.1 >/tmp/remote-dns.txt
echo REMOTE_DNS_PASS
rm -f /tmp/vmpeer.conf /tmp/remote-ping.txt /tmp/remote-dns.txt /tmp/vm-remote-private.key /tmp/vm-remote-psk.key'
(
	sleep 62
	(
		printf '\nroot\n'
		sleep 3
		printf ': >/tmp/vm-remote-test.sh\n'
		printf '%s' "$REMOTE_GUEST_COMMAND" | base64 | fold -w 60 | while IFS= read -r chunk; do
			printf 'printf %%s %s | base64 -d >>/tmp/vm-remote-test.sh\n' "$chunk"
		done
		printf 'sh -e /tmp/vm-remote-test.sh; status=$?; rm -f /tmp/vm-remote-test.sh; exit $status\n'
		sleep 25
	) | timeout 130 nc -N 127.0.0.1 "$REMOTE_SERIAL_PORT"
) > "$RESULT_DIR/remote.serial.log" 2>&1 &
REMOTE_CONSOLE_PID=$!

LUCI_STATUS='000'
for attempt in $(seq 1 90); do
	LUCI_STATUS="$(curl --silent --show-error --output "$RESULT_DIR/luci.html" --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:$HTTP_PORT/cgi-bin/luci/" || true)"
	if [ "$LUCI_STATUS" = '200' ] || [ "$LUCI_STATUS" = '403' ]; then
		break
	fi
	sleep 2
done
test -s "$RESULT_DIR/luci.html" || fail 'LuCI did not respond within 180 seconds'
case "$LUCI_STATUS" in
	200|403) ;;
	*) fail "LuCI returned unexpected HTTP status $LUCI_STATUS" ;;
esac
grep -Eqi '<title>.*(OpenWrt|LuCI)' "$RESULT_DIR/luci.html" || fail 'LuCI response does not contain the expected page title'
record VM_BOOT PASS
record LUCI PASS

curl --silent --show-error --fail --max-time 10 "http://127.0.0.1:$HTTP_PORT/luci-static/resources/view/vpn-dashboard/dashboard.js" > "$RESULT_DIR/dashboard.js"
curl --silent --show-error --fail --max-time 10 "http://127.0.0.1:$HTTP_PORT/luci-static/resources/view/vpn-dashboard/clients.js" > "$RESULT_DIR/clients.js"
test -s "$RESULT_DIR/dashboard.js" || fail 'VPN Dashboard JavaScript is absent from the running image'
test -s "$RESULT_DIR/clients.js" || fail 'peer-management JavaScript is absent from the running image'
if grep -Eqi 'private_key|preshared_key|privatekey|presharedkey' "$RESULT_DIR/dashboard.js" "$RESULT_DIR/clients.js"; then
	fail 'public Dashboard assets contain a secret field name'
fi
wait "$CONSOLE_PID" || true
wait "$REMOTE_CONSOLE_PID" || true
tr -d '\r' < "$RESULT_DIR/openwrt.serial.log" > "$RESULT_DIR/openwrt.serial.normalized.log"
tr -d '\r' < "$RESULT_DIR/remote.serial.log" > "$RESULT_DIR/remote.serial.normalized.log"
for marker in AWG_MODULE_PASS AWG_SERVER_PASS PODKOP_SOURCE_PASS PEER_EXPORT_PASS QR_PASS STATUS_SECRET_SAFE PEER_TOGGLE_PASS PEER_DELETE_PASS GUEST_TEST_COMPLETE; do
	grep -Fxq "$marker" "$RESULT_DIR/openwrt.serial.normalized.log" || fail "guest runtime test failed: $marker"
done
for marker in REMOTE_AWG_CONFIG_PASS REMOTE_AWG_HANDSHAKE_PASS REMOTE_DNS_PASS; do
	grep -Fxq "$marker" "$RESULT_DIR/remote.serial.normalized.log" || fail "remote guest runtime test failed: $marker"
done
awk '/^DASHBOARD_API_BEGIN$/{inside=1;next} /^DASHBOARD_API_END$/{inside=0} inside && /^\{.*\}$/{print}' "$RESULT_DIR/openwrt.serial.normalized.log" > "$RESULT_DIR/dashboard-api.json"
test -s "$RESULT_DIR/dashboard-api.json" || fail 'Dashboard status API response is absent'
if grep -Eqi 'private_key|preshared_key|privatekey|presharedkey|password|secret' "$RESULT_DIR/dashboard-api.json"; then
	fail 'Dashboard status API contains a secret field name'
fi
record VPN_DASHBOARD PASS
record AWG_MODULE PASS
record AWG_SERVER PASS
record REMOTE_AWG_HANDSHAKE PASS
record REMOTE_DNS PASS
record PODKOP_SOURCE_INTERFACE PASS
record PEER_MANAGEMENT PASS
record QR_GENERATION PASS
record SECRET_LEAK_TEST PASS

cat > "$RESULT_DIR/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="openwrt-vm-smoke" tests="11" failures="0">
  <testcase name="vm_boot"/>
  <testcase name="luci_http"/>
  <testcase name="vpn_dashboard_assets"/>
  <testcase name="amneziawg_module"/>
  <testcase name="amneziawg_server"/>
  <testcase name="remote_awg_handshake"/>
  <testcase name="remote_dns_via_router"/>
  <testcase name="podkop_source_interface"/>
  <testcase name="peer_management_and_qr"/>
  <testcase name="dashboard_public_assets_no_secret_names"/>
  <testcase name="dashboard_status_api_no_secret_names"/>
</testsuite>
EOF
printf 'VIRTUAL_RUNTIME_VALIDATION=PASS\n' >> "$RESULT_DIR/summary.txt"
echo "VM TEST PASS: $RESULT_DIR"
