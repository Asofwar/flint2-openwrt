#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_TEST_SUITE="${VM_TEST_SUITE:-runtime}"

if [ "$VM_TEST_SUITE" = 'all' ]; then
	SUITE_RUN_ID="${VM_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
	SUITE_RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$SUITE_RUN_ID"
	mkdir -p "$SUITE_RESULT_DIR"
	printf 'VIRTUAL_FULL_SUITE=RUNNING\n' > "$SUITE_RESULT_DIR/summary.txt"
	VM_TEST_SUITE=runtime VM_TEST_RUN_ID="$SUITE_RUN_ID-runtime" bash "$0"
	VM_AWG_OUT_TEST_RUN_ID="$SUITE_RUN_ID-awg-out" bash "$PROJECT_DIR/scripts/test-vm-awg-out.sh"
	VM_PODKOP_POLICY_TEST_RUN_ID="$SUITE_RUN_ID-podkop-policy" bash "$PROJECT_DIR/scripts/test-vm-podkop-policy.sh"
	for summary in \
		"$PROJECT_DIR/artifacts/test-results/$SUITE_RUN_ID-runtime/summary.txt" \
		"$PROJECT_DIR/artifacts/test-results/$SUITE_RUN_ID-awg-out/summary.txt" \
		"$PROJECT_DIR/artifacts/test-results/$SUITE_RUN_ID-podkop-policy/summary.txt"; do
		test -f "$summary" || { echo "VM TEST FAILED: missing suite summary: $summary" >&2; exit 1; }
		cat "$summary" >> "$SUITE_RESULT_DIR/summary.txt"
	done
	grep -Fxq 'VIRTUAL_RUNTIME_VALIDATION=PASS' "$SUITE_RESULT_DIR/summary.txt"
	grep -Fxq 'VIRTUAL_AWG_OUT_VALIDATION=PASS' "$SUITE_RESULT_DIR/summary.txt"
	grep -Fxq 'VIRTUAL_PODKOP_POLICY_VALIDATION=PASS' "$SUITE_RESULT_DIR/summary.txt"
	cat > "$SUITE_RESULT_DIR/junit.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="flint2-openwrt-vm-full-suite" tests="3" failures="0">
  <testcase name="runtime_smoke_and_reboot"/>
  <testcase name="awg_outbound"/>
  <testcase name="podkop_same_policy"/>
</testsuite>
EOF
	printf 'VIRTUAL_FULL_SUITE=PASS\n' >> "$SUITE_RESULT_DIR/summary.txt"
	echo "VM FULL SUITE PASS: $SUITE_RESULT_DIR"
	exit 0
fi

[ "$VM_TEST_SUITE" = 'runtime' ] || { echo "VM TEST FAILED: unknown VM_TEST_SUITE=$VM_TEST_SUITE" >&2; exit 1; }

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
POST_REBOOT_CONSOLE_PID=''
POST_REBOOT_REMOTE_CONSOLE_PID=''
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
	for pid in "$REMOTE_QEMU_PID" "$REMOTE_CONSOLE_PID" "$POST_REBOOT_CONSOLE_PID" "$POST_REBOOT_REMOTE_CONSOLE_PID"; do
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
	> "$RESULT_DIR/qemu.log" 2>&1 &
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

GUEST_COMMAND='set -e
modprobe amneziawg && ip link add awg_probe type amneziawg && awg show awg_probe >/dev/null && ip link del awg_probe && echo AWG_MODULE_PASS
uci set network.wan=interface
uci set network.wan.device=eth1
uci set network.wan.proto=static
uci set network.wan.ipaddr=192.0.2.1
uci set network.wan.netmask=255.255.255.0
uci commit network
ifup wan
ip link set eth1 up
ip addr replace 192.0.2.1/24 dev eth1
uci set vpn-dashboard.main.enabled=1
uci set vpn-dashboard.main.endpoint_mode=manual
uci set vpn-dashboard.main.endpoint_host=192.0.2.1
uci commit vpn-dashboard
/etc/init.d/vpn-dashboard restart
sleep 8
ifstatus awg_server | grep -q "\"up\": true" && echo AWG_SERVER_PASS
device="$(ubus call network.interface.awg_server status | jsonfilter -e "@.l3_device")"
test -n "$device"
/usr/libexec/vpn-dashboard-sync-podkop "$device"
uci -q get podkop.settings.source_network_interfaces | grep -qw "$device"
uci set podkop.main.connection_type=vpn
uci set podkop.main.interface="$device"
uci -q delete podkop.main.community_lists
uci set podkop.settings.dont_touch_dhcp=1
uci set podkop.settings.exclude_ntp=1
uci commit podkop
/usr/bin/podkop start
nft list set inet PodkopTable interfaces >/tmp/podkop-interfaces.nft
grep -qw br-lan /tmp/podkop-interfaces.nft
grep -qw "$device" /tmp/podkop-interfaces.nft
/usr/bin/podkop stop
rm -f /tmp/podkop-interfaces.nft
echo PODKOP_NFT_SOURCE_PASS
/usr/libexec/vpn-dashboard-peer create vmpeer full >/tmp/vmpeer.conf
/usr/libexec/vpn-dashboard-peer create vmpeer2 full >/tmp/vmpeer2.conf
cp /tmp/vmpeer.conf /www/vmpeer.conf
cp /tmp/vmpeer2.conf /www/vmpeer2.conf
chmod 0644 /www/vmpeer.conf
uci delete uhttpd.main.listen_http
uci add_list uhttpd.main.listen_http='192.0.2.1:8080'
uci commit uhttpd
/etc/init.d/uhttpd restart
uci set firewall.vm_peer_export=rule
uci set firewall.vm_peer_export.name='Allow-VM-peer-export'
uci set firewall.vm_peer_export.src='wan'
uci set firewall.vm_peer_export.proto='tcp'
uci set firewall.vm_peer_export.dest_port='8080'
uci set firewall.vm_peer_export.target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload
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
logger -t vpn-dashboard 'vm-safe-log-check'
logger -t vpn-dashboard 'private_key=vm-test-secret'
sleep 1
/usr/libexec/vpn-dashboard-logs all >/tmp/vpn-dashboard-logs.txt
grep -q 'vm-safe-log-check' /tmp/vpn-dashboard-logs.txt
! grep -Eqi "private_key|preshared_key|privatekey|presharedkey|password|secret" /tmp/vpn-dashboard-logs.txt
echo VPN_LOGS_SAFE_PASS
test "$(ls -ld /etc/vpn-dashboard/peers/vmpeer | awk "{print \$1}")" = '-rw-------'
test "$(ls -ld /etc/vpn-dashboard/peers/vmpeer2 | awk "{print \$1}")" = '-rw-------'
/sbin/sysupgrade -b /tmp/vm-backup.tar.gz
for backup_path in \
  etc/config/network \
  etc/config/firewall \
  etc/config/dhcp \
  etc/config/podkop \
  etc/config/vpn-dashboard \
  etc/vpn-dashboard/peers/vmpeer \
  etc/vpn-dashboard/peers/vmpeer2; do
  tar -tzf /tmp/vm-backup.tar.gz | grep -qx "$backup_path"
done
rm -f /tmp/vm-backup.tar.gz
echo BACKUP_VALIDATION_PASS
apk info -e podkop
apk info -e kmod-amneziawg
apk info -e luci-app-vpn-dashboard
apk info podkop | grep -q '^podkop-'
echo APK_PACKAGE_MANAGER_PASS
sleep 100
/usr/libexec/vpn-dashboard-peer enable vmpeer 0 && uci get vpn-dashboard.peer_vmpeer.enabled | grep -qx 0 && /usr/libexec/vpn-dashboard-peer enable vmpeer 1 && uci get vpn-dashboard.peer_vmpeer.enabled | grep -qx 1 && echo PEER_TOGGLE_PASS
echo REBOOT_REQUESTED
reboot'
(
	sleep 35
	(
		printf '\nroot\n'
		sleep 3
		printf '%s\n' "$GUEST_COMMAND" | while IFS= read -r line; do
			printf '%s\n' "$line"
			sleep 0.2
		done
		sleep 150
	) | timeout 300 nc -N 127.0.0.1 "$SERIAL_PORT"
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
  wget -qO /tmp/vmpeer.conf http://192.0.2.1:8080/vmpeer.conf && grep -q "^PrivateKey = " /tmp/vmpeer.conf && grep -q "^PresharedKey = " /tmp/vmpeer.conf && break
  sleep 2
done
grep -q "^PrivateKey = " /tmp/vmpeer.conf && grep -q "^PresharedKey = " /tmp/vmpeer.conf
! timeout 2 nc 192.0.2.1 80 </dev/null >/dev/null 2>&1
! timeout 2 nc 192.0.2.1 22 </dev/null >/dev/null 2>&1
echo FIREWALL_WAN_BLOCK_PASS
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
for attempt in $(seq 1 30); do
  wget -qO /tmp/vmpeer2.conf http://192.0.2.1:8080/vmpeer2.conf && grep -q "^PrivateKey = " /tmp/vmpeer2.conf && grep -q "^PresharedKey = " /tmp/vmpeer2.conf && break
  sleep 2
done
client_private2="$(sed -n "s/^PrivateKey = //p" /tmp/vmpeer2.conf)"
server_public2="$(sed -n "s/^PublicKey = //p" /tmp/vmpeer2.conf)"
preshared_key2="$(sed -n "s/^PresharedKey = //p" /tmp/vmpeer2.conf)"
test -n "$client_private2" && test -n "$server_public2" && test -n "$preshared_key2"
printf '%s' "$client_private2" >/tmp/vm-remote2-private.key
printf '%s' "$preshared_key2" >/tmp/vm-remote2-psk.key
ip link add awg_remote2 type amneziawg
awg set awg_remote2 private-key /tmp/vm-remote2-private.key peer "$server_public2" preshared-key /tmp/vm-remote2-psk.key allowed-ips 0.0.0.0/0 endpoint 192.0.2.1:51820 persistent-keepalive 5
ip addr add 10.77.0.3/24 dev awg_remote2
ip link set awg_remote2 up
ip route replace 10.77.0.3/32 dev awg_remote
sleep 10
awg show awg_remote2 latest-handshakes | awk "NF == 2 && \$2 > 0 { found=1 } END { exit !found }"
! ping -I awg_remote -c 1 -W 2 10.77.0.3 >/tmp/remote-isolation.txt 2>&1
echo CLIENT_ISOLATION_PASS
nslookup localhost 10.77.0.1 >/tmp/remote-dns.txt
echo REMOTE_DNS_PASS
rm -f /tmp/vmpeer.conf /tmp/vmpeer2.conf /tmp/remote-ping.txt /tmp/remote-isolation.txt /tmp/remote-dns.txt /tmp/vm-remote-private.key /tmp/vm-remote-psk.key /tmp/vm-remote2-private.key /tmp/vm-remote2-psk.key'
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
		sleep 80
	) | timeout 210 nc -N 127.0.0.1 "$REMOTE_SERIAL_PORT"
) > "$RESULT_DIR/remote.serial.log" 2>&1 &
REMOTE_CONSOLE_PID=$!

POST_REBOOT_COMMAND='set -ex
for attempt in $(seq 1 60); do
  if ifstatus awg_server | grep -q "\"up\": true"; then break; fi
  sleep 2
done
ifstatus awg_server | grep -q "\"up\": true"
uci get vpn-dashboard.peer_vmpeer.enabled | grep -qx 1
uci get vpn-dashboard.peer_vmpeer2.enabled | grep -qx 1
test -f /etc/vpn-dashboard/peers/vmpeer
test -f /etc/vpn-dashboard/peers/vmpeer2
nft list ruleset >/tmp/reboot-firewall.nft
grep -qw awg_server /tmp/reboot-firewall.nft
for attempt in $(seq 1 60); do
  awg show awg_server latest-handshakes | awk "NF == 2 && \$2 > 0 { count++ } END { exit !(count >= 2) }" && break
  sleep 2
done
echo REBOOT_PERSISTENCE_PASS'
POST_REBOOT_REMOTE_COMMAND='set -e
for attempt in $(seq 1 30); do
  ip route replace 10.77.0.1/32 dev awg_remote
  ping -I awg_remote -c 1 -W 1 10.77.0.1 >/tmp/remote-reboot-peer1.txt || true
  ip route replace 10.77.0.1/32 dev awg_remote2
  ping -I awg_remote2 -c 1 -W 1 10.77.0.1 >/tmp/remote-reboot-peer2.txt || true
  sleep 2
done
awg show awg_remote latest-handshakes | awk "NF == 2 && \$2 > 0 { found=1 } END { exit !found }"
awg show awg_remote2 latest-handshakes | awk "NF == 2 && \$2 > 0 { found=1 } END { exit !found }"
rm -f /tmp/remote-reboot-peer1.txt /tmp/remote-reboot-peer2.txt
echo REMOTE_POST_REBOOT_HANDSHAKE_PASS'
(
	sleep 250
	(
		printf '\nroot\n'
		sleep 3
		printf ': >/tmp/vm-post-reboot.sh\n'
		printf '%s' "$POST_REBOOT_COMMAND" | base64 | fold -w 60 | while IFS= read -r chunk; do
			printf 'printf %%s %s | base64 -d >>/tmp/vm-post-reboot.sh\n' "$chunk"
		done
		printf 'sh -e /tmp/vm-post-reboot.sh; status=$?; rm -f /tmp/vm-post-reboot.sh; exit $status\n'
		sleep 150
	) | timeout 180 nc -N 127.0.0.1 "$SERIAL_PORT"
) > "$RESULT_DIR/post-reboot.serial.log" 2>&1 &
POST_REBOOT_CONSOLE_PID=$!

(
	sleep 270
	(
		printf '\nroot\n'
		sleep 3
		printf ': >/tmp/vm-post-reboot-remote.sh\n'
		printf '%s' "$POST_REBOOT_REMOTE_COMMAND" | base64 | fold -w 60 | while IFS= read -r chunk; do
			printf 'printf %%s %s | base64 -d >>/tmp/vm-post-reboot-remote.sh\n' "$chunk"
		done
		printf 'sh -e /tmp/vm-post-reboot-remote.sh; status=$?; rm -f /tmp/vm-post-reboot-remote.sh; exit $status\n'
		sleep 150
	) | timeout 180 nc -N 127.0.0.1 "$REMOTE_SERIAL_PORT"
) > "$RESULT_DIR/post-reboot.remote.serial.log" 2>&1 &
POST_REBOOT_REMOTE_CONSOLE_PID=$!

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
wait "$POST_REBOOT_CONSOLE_PID" || true
wait "$POST_REBOOT_REMOTE_CONSOLE_PID" || true
tr -d '\r' < "$RESULT_DIR/openwrt.serial.log" > "$RESULT_DIR/openwrt.serial.normalized.log"
tr -d '\r' < "$RESULT_DIR/remote.serial.log" > "$RESULT_DIR/remote.serial.normalized.log"
tr -d '\r' < "$RESULT_DIR/post-reboot.serial.log" > "$RESULT_DIR/post-reboot.serial.normalized.log"
tr -d '\r' < "$RESULT_DIR/post-reboot.remote.serial.log" > "$RESULT_DIR/post-reboot.remote.serial.normalized.log"
for marker in AWG_MODULE_PASS AWG_SERVER_PASS PODKOP_NFT_SOURCE_PASS PEER_EXPORT_PASS QR_PASS STATUS_SECRET_SAFE VPN_LOGS_SAFE_PASS BACKUP_VALIDATION_PASS APK_PACKAGE_MANAGER_PASS PEER_TOGGLE_PASS REBOOT_REQUESTED; do
	grep -Fxq "$marker" "$RESULT_DIR/openwrt.serial.normalized.log" || fail "guest runtime test failed: $marker"
done
grep -Fxq REBOOT_PERSISTENCE_PASS "$RESULT_DIR/post-reboot.serial.normalized.log" || fail 'post-reboot runtime test failed'
grep -Fxq REMOTE_POST_REBOOT_HANDSHAKE_PASS "$RESULT_DIR/post-reboot.remote.serial.normalized.log" || fail 'post-reboot remote handshake test failed'
for marker in FIREWALL_WAN_BLOCK_PASS REMOTE_AWG_CONFIG_PASS REMOTE_AWG_HANDSHAKE_PASS CLIENT_ISOLATION_PASS REMOTE_DNS_PASS; do
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
record FIREWALL_WAN PASS
record CLIENT_ISOLATION PASS
record PODKOP_NFT_SOURCE_INTERFACE PASS
record PEER_MANAGEMENT PASS
record QR_GENERATION PASS
record SECRET_LEAK_TEST PASS
record VPN_LOGS_SECURITY PASS
record BACKUP_VALIDATION PASS
record APK_PACKAGE_MANAGER PASS
record REBOOT_PERSISTENCE PASS

cat > "$RESULT_DIR/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="openwrt-vm-smoke" tests="17" failures="0">
  <testcase name="vm_boot"/>
  <testcase name="luci_http"/>
  <testcase name="vpn_dashboard_assets"/>
  <testcase name="amneziawg_module"/>
  <testcase name="amneziawg_server"/>
  <testcase name="remote_awg_handshake"/>
  <testcase name="remote_dns_via_router"/>
  <testcase name="wan_blocks_http_and_ssh_while_awg_handshakes"/>
  <testcase name="awg_peer_isolation_blocks_peer_to_peer_traffic"/>
  <testcase name="podkop_nft_source_interface"/>
  <testcase name="peer_management_and_qr"/>
  <testcase name="vpn_logs_exclude_credentials"/>
  <testcase name="backup_contents_and_secret_permissions"/>
  <testcase name="apk_installed_package_database"/>
  <testcase name="reboot_persists_awg_server_peers_firewall_and_handshakes"/>
  <testcase name="dashboard_public_assets_no_secret_names"/>
  <testcase name="dashboard_status_api_no_secret_names"/>
</testsuite>
EOF
printf 'VIRTUAL_RUNTIME_VALIDATION=PASS\n' >> "$RESULT_DIR/summary.txt"
echo "VM TEST PASS: $RESULT_DIR"
