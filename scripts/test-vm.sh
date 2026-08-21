#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${VM_IMAGE:-$(find "$PROJECT_DIR/artifacts/vm" -maxdepth 1 -type f -name '*squashfs-combined.img.gz' -print -quit)}"
RUN_ID="${VM_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$RUN_ID"
HTTP_PORT="${VM_HTTP_PORT:-18080}"
SERIAL_PORT="${VM_SERIAL_PORT:-19001}"
VM_IP='10.0.2.15'
QEMU_PID=''
CONSOLE_PID=''
VM_DISK=''

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
	if [ -n "$VM_DISK" ]; then
		rm -f "$VM_DISK"
	fi
}
trap cleanup EXIT

test -n "$IMAGE" && test -f "$IMAGE" || fail 'x86_64 combined image is absent; run build-vm first'
command -v qemu-system-x86_64 >/dev/null || fail 'qemu-system-x86_64 is required'
command -v curl >/dev/null || fail 'curl is required'

mkdir -p "$RESULT_DIR"
printf 'VIRTUAL_RUNTIME_VALIDATION=RUNNING\n' > "$RESULT_DIR/summary.txt"
VM_DISK="$(mktemp "${TMPDIR:-/tmp}/flint2-vm-${RUN_ID}.XXXXXX.img")"
gzip -cd "$IMAGE" > "$VM_DISK"

qemu-system-x86_64 \
	-machine q35 -m 768M -smp 2 -display none -monitor none \
	-drive "file=$VM_DISK,format=raw,if=virtio" \
	-netdev "user,id=wan,net=10.0.2.0/24,hostfwd=tcp::$HTTP_PORT-$VM_IP:80" \
	-device e1000,netdev=wan \
	-serial "tcp:127.0.0.1:$SERIAL_PORT,server=on,wait=off" \
	-no-reboot > "$RESULT_DIR/qemu.log" 2>&1 &
QEMU_PID=$!

GUEST_COMMAND='modprobe amneziawg && ip link add awg_probe type amneziawg && awg show awg_probe >/dev/null && ip link del awg_probe && echo AWG_MODULE_PASS
uci set vpn-dashboard.main.enabled=1
uci set vpn-dashboard.main.endpoint_mode=manual
uci set vpn-dashboard.main.endpoint_host=198.51.100.2
uci commit vpn-dashboard
/etc/init.d/vpn-dashboard restart
sleep 8
ifstatus awg_server | grep -q "\"up\": true" && echo AWG_SERVER_PASS
device="$(ubus call network.interface.awg_server status | jsonfilter -e "@.l3_device")"
test -n "$device" && /usr/libexec/vpn-dashboard-sync-podkop "$device" && uci -q get podkop.settings.source_network_interfaces | grep -qw "$device" && echo PODKOP_SOURCE_PASS
/usr/libexec/vpn-dashboard-peer create vmpeer full >/tmp/vmpeer.conf
sed -e "/^PrivateKey = /d" -e "/^PresharedKey = /d" /tmp/vmpeer.conf >/tmp/vmpeer.safe
echo CLIENT_CONFIG_SAFE_BEGIN
cat /tmp/vmpeer.safe
echo CLIENT_CONFIG_SAFE_END
awk -F " = " "/^[A-Za-z]/{print \$1}" /tmp/vmpeer.conf >/tmp/vmpeer.fields
grep -qx PrivateKey /tmp/vmpeer.fields && grep -qx Address /tmp/vmpeer.fields
grep -qx DNS /tmp/vmpeer.fields && grep -qx MTU /tmp/vmpeer.fields
grep -qx PublicKey /tmp/vmpeer.fields && grep -qx PresharedKey /tmp/vmpeer.fields
grep -qx Endpoint /tmp/vmpeer.fields && grep -qx AllowedIPs /tmp/vmpeer.fields
grep -q "^DNS = 10.77.0.1" /tmp/vmpeer.safe && grep -q "^Endpoint = 198.51.100.2:51820" /tmp/vmpeer.safe && grep -q "^AllowedIPs = 0.0.0.0/0" /tmp/vmpeer.safe && echo PEER_EXPORT_PASS
/usr/libexec/vpn-dashboard-peer qr vmpeer >/tmp/vmpeer.qr && test -s /tmp/vmpeer.qr && echo QR_PASS
echo DASHBOARD_API_BEGIN
/usr/libexec/vpn-dashboard-peer dashboard
echo DASHBOARD_API_END
/usr/libexec/vpn-dashboard-peer status >/tmp/vmpeer.status && ! grep -Eqi "private_key|preshared_key|privatekey|presharedkey|password|secret" /tmp/vmpeer.status && echo STATUS_SECRET_SAFE
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
		sleep 45
	) | timeout 120 nc -N 127.0.0.1 "$SERIAL_PORT"
) > "$RESULT_DIR/openwrt.serial.log" 2>&1 &
CONSOLE_PID=$!

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
tr -d '\r' < "$RESULT_DIR/openwrt.serial.log" > "$RESULT_DIR/openwrt.serial.normalized.log"
for marker in AWG_MODULE_PASS AWG_SERVER_PASS PODKOP_SOURCE_PASS PEER_EXPORT_PASS QR_PASS STATUS_SECRET_SAFE PEER_TOGGLE_PASS PEER_DELETE_PASS GUEST_TEST_COMPLETE; do
	grep -Fxq "$marker" "$RESULT_DIR/openwrt.serial.normalized.log" || fail "guest runtime test failed: $marker"
done
awk '/^DASHBOARD_API_BEGIN$/{inside=1;next} /^DASHBOARD_API_END$/{inside=0} inside && /^\{.*\}$/{print}' "$RESULT_DIR/openwrt.serial.normalized.log" > "$RESULT_DIR/dashboard-api.json"
test -s "$RESULT_DIR/dashboard-api.json" || fail 'Dashboard status API response is absent'
if grep -Eqi 'private_key|preshared_key|privatekey|presharedkey|password|secret' "$RESULT_DIR/dashboard-api.json"; then
	fail 'Dashboard status API contains a secret field name'
fi
record VPN_DASHBOARD PASS
record AWG_MODULE PASS
record AWG_SERVER PASS
record PODKOP_SOURCE_INTERFACE PASS
record PEER_MANAGEMENT PASS
record QR_GENERATION PASS
record SECRET_LEAK_TEST PASS

cat > "$RESULT_DIR/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="openwrt-vm-smoke" tests="9" failures="0">
  <testcase name="vm_boot"/>
  <testcase name="luci_http"/>
  <testcase name="vpn_dashboard_assets"/>
  <testcase name="amneziawg_module"/>
  <testcase name="amneziawg_server"/>
  <testcase name="podkop_source_interface"/>
  <testcase name="peer_management_and_qr"/>
  <testcase name="dashboard_public_assets_no_secret_names"/>
  <testcase name="dashboard_status_api_no_secret_names"/>
</testsuite>
EOF
printf 'VIRTUAL_RUNTIME_VALIDATION=PASS\n' >> "$RESULT_DIR/summary.txt"
echo "VM TEST PASS: $RESULT_DIR"
