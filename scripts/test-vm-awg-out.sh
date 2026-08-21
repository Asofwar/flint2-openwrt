#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${VM_IMAGE:-$(find "$PROJECT_DIR/artifacts/vm" -maxdepth 1 -type f -name '*squashfs-combined.img.gz' -print -quit)}"
RUN_ID="${VM_AWG_OUT_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$RUN_ID"
ROUTER_PORT="${VM_AWG_OUT_ROUTER_SERIAL_PORT:-19101}"
EXTERNAL_PORT="${VM_AWG_OUT_EXTERNAL_SERIAL_PORT:-19102}"
LINK_PORT="${VM_AWG_OUT_LINK_PORT:-19110}"
BASE_DISK=''
ROUTER_DISK=''
EXTERNAL_DISK=''
ROUTER_QEMU=''
EXTERNAL_QEMU=''
ROUTER_CONSOLE=''
EXTERNAL_CONSOLE=''

fail() { echo "VM AWG-OUT TEST FAILED: $*" >&2; exit 1; }
record() { printf '%s=%s\n' "$1" "$2" >> "$RESULT_DIR/summary.txt"; }
stop() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && kill "$1" 2>/dev/null || true; }
cleanup() {
	for pid in "$ROUTER_QEMU" "$EXTERNAL_QEMU" "$ROUTER_CONSOLE" "$EXTERNAL_CONSOLE"; do stop "$pid"; done
	for disk in "$BASE_DISK" "$ROUTER_DISK" "$EXTERNAL_DISK"; do [ -n "$disk" ] && rm -f "$disk"; done
}
run_guest() {
	local delay="$1" port="$2" command="$3" log="$4"
	(
		sleep "$delay"
		(
			printf '\nroot\n'
			sleep 3
			printf ': >/tmp/vm-test.sh\n'
			printf '%s' "$command" | base64 | fold -w 60 | while IFS= read -r chunk; do
				printf 'printf %%s %s | base64 -d >>/tmp/vm-test.sh\n' "$chunk"
				sleep 0.05
			done
			printf 'sh -e /tmp/vm-test.sh; status=$?; rm -f /tmp/vm-test.sh; exit $status\n'
			sleep 160
		) | timeout 190 nc -N 127.0.0.1 "$port"
	) > "$log" 2>&1 &
	GUEST_PID=$!
}
trap cleanup EXIT

test -n "$IMAGE" && test -f "$IMAGE" || fail 'x86_64 combined image is absent; run build-vm first'
command -v qemu-system-x86_64 >/dev/null || fail 'qemu-system-x86_64 is required'
command -v qemu-img >/dev/null || fail 'qemu-img is required'
command -v nc >/dev/null || fail 'nc is required'
mkdir -p "$RESULT_DIR"
printf 'VIRTUAL_AWG_OUT_VALIDATION=RUNNING\n' > "$RESULT_DIR/summary.txt"
BASE_DISK="$(mktemp "${TMPDIR:-/tmp}/flint2-awg-out-${RUN_ID}.XXXXXX.img")"
ROUTER_DISK="${BASE_DISK%.img}-router.qcow2"
EXTERNAL_DISK="${BASE_DISK%.img}-external.qcow2"
gzip -cd "$IMAGE" > "$BASE_DISK"
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$ROUTER_DISK" >/dev/null
qemu-img create -f qcow2 -b "$BASE_DISK" -F raw "$EXTERNAL_DISK" >/dev/null

qemu-system-x86_64 -machine q35 -m 768M -smp 2 -display none -monitor none \
	-drive "file=$ROUTER_DISK,format=qcow2,if=virtio" \
	-netdev 'user,id=wan,net=10.0.2.0/24' -device e1000,netdev=wan \
	-netdev "socket,id=outbound,listen=127.0.0.1:$LINK_PORT" -device e1000,netdev=outbound,mac=52:54:00:aa:10:01 \
	-serial "tcp:127.0.0.1:$ROUTER_PORT,server=on,wait=off" -no-reboot > "$RESULT_DIR/router-qemu.log" 2>&1 &
ROUTER_QEMU=$!
sleep 2
kill -0 "$ROUTER_QEMU" 2>/dev/null || fail 'router QEMU did not start'
qemu-system-x86_64 -machine q35 -m 512M -smp 2 -display none -monitor none \
	-drive "file=$EXTERNAL_DISK,format=qcow2,if=virtio" \
	-netdev "socket,id=outbound,connect=127.0.0.1:$LINK_PORT" -device e1000,netdev=outbound,mac=52:54:00:aa:10:02 \
	-serial "tcp:127.0.0.1:$EXTERNAL_PORT,server=on,wait=off" -no-reboot > "$RESULT_DIR/external-qemu.log" 2>&1 &
EXTERNAL_QEMU=$!

read -r -d '' EXTERNAL_COMMAND <<'EOF' || true
set -e
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
ip link set eth0 up
ip addr replace 192.0.2.2/24 dev eth0
uci set firewall.@defaults[0].input=ACCEPT
uci set firewall.@defaults[0].output=ACCEPT
uci set firewall.vm_outlink=zone
uci set firewall.vm_outlink.name=vm_outlink
uci set firewall.vm_outlink.network=outlink
uci set firewall.vm_outlink.input=ACCEPT
uci set firewall.vm_outlink.output=ACCEPT
uci set firewall.vm_outlink.forward=REJECT
uci commit firewall
/etc/init.d/firewall reload
/etc/init.d/uhttpd restart
modprobe amneziawg
umask 077
awg genkey | head -c 44 >/tmp/external-awg-private.key
test "$(wc -c </tmp/external-awg-private.key)" -eq 44
awg pubkey </tmp/external-awg-private.key >/www/external-awg.pub
test "$(wc -c </www/external-awg.pub)" -eq 45
chmod 644 /www/external-awg.pub
sleep 1
for attempt in $(seq 1 60); do
  wget -qO /tmp/router-awg.pub http://192.0.2.1/router-awg.pub && test -s /tmp/router-awg.pub && break
  sleep 2
done
router_public="$(sed -n '1p' /tmp/router-awg.pub)"
test ${#router_public} -eq 44
ip link add awg_external type amneziawg
awg set awg_external private-key /tmp/external-awg-private.key listen-port 51820 peer "$router_public" allowed-ips 10.77.0.2/32
ip addr add 10.77.0.1/24 dev awg_external
ip link set awg_external up
mkdir -p /www/awg-out
printf 'ROUTE=AWG-OUT\n' >/www/awg-out/index.html
chmod 755 /www/awg-out
chmod 644 /www/awg-out/index.html
echo EXTERNAL_AWG_READY
for attempt in $(seq 1 45); do
  if awg show awg_external latest-handshakes | awk 'NF == 2 && $2 > 0 { found=1 } END { exit !found }' \
    && awg show awg_external transfer | awk 'NF == 3 && ($2 > 0 || $3 > 0) { found=1 } END { exit !found }'; then
    echo EXTERNAL_AWG_TRANSFER_PASS
    rm -f /tmp/external-awg-private.key /tmp/router-awg.pub /www/external-awg.pub
    exit 0
  fi
  sleep 2
done
exit 1
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
uci set firewall.@defaults[0].input=ACCEPT
uci set firewall.@defaults[0].output=ACCEPT
uci set firewall.vm_outlink=zone
uci set firewall.vm_outlink.name=vm_outlink
uci set firewall.vm_outlink.network=outlink
uci set firewall.vm_outlink.input=ACCEPT
uci set firewall.vm_outlink.output=ACCEPT
uci set firewall.vm_outlink.forward=REJECT
uci commit firewall
/etc/init.d/firewall reload
/etc/init.d/uhttpd restart
for attempt in $(seq 1 10); do
  ping -c 1 -W 1 192.0.2.2 >/dev/null && break
  sleep 1
done
ping -c 1 -W 1 192.0.2.2 >/dev/null
echo OUTBOUND_LINK_PASS
umask 077
awg genkey | head -c 44 >/tmp/awg-out-private.key
test "$(wc -c </tmp/awg-out-private.key)" -eq 44
awg pubkey </tmp/awg-out-private.key >/www/router-awg.pub
test "$(wc -c </www/router-awg.pub)" -eq 45
chmod 644 /www/router-awg.pub
sleep 1
for attempt in $(seq 1 60); do
  wget -qO /tmp/external-awg.pub http://192.0.2.2/external-awg.pub && test -s /tmp/external-awg.pub && break
  sleep 2
done
server_public="$(sed -n '1p' /tmp/external-awg.pub)"
test ${#server_public} -eq 44
ip link add awg_out type amneziawg
awg set awg_out private-key /tmp/awg-out-private.key peer "$server_public" allowed-ips 0.0.0.0/0 endpoint 192.0.2.2:51820 persistent-keepalive 5
ip addr add 10.77.0.2/24 dev awg_out
ip link set awg_out up
ip route replace 10.77.0.0/24 dev awg_out
for attempt in $(seq 1 35); do
  wget -qO /tmp/awg-out-response http://10.77.0.1/awg-out/ && grep -qx 'ROUTE=AWG-OUT' /tmp/awg-out-response && break
  sleep 2
done
grep -qx 'ROUTE=AWG-OUT' /tmp/awg-out-response
awg show awg_out latest-handshakes | awk 'NF == 2 && $2 > 0 { found=1 } END { exit !found }'
echo ROUTER_AWG_OUT_PASS
rm -f /tmp/awg-out-private.key /tmp/external-awg.pub /tmp/awg-out-response /www/router-awg.pub
EOF

run_guest 45 "$EXTERNAL_PORT" "$EXTERNAL_COMMAND" "$RESULT_DIR/external.serial.log"
EXTERNAL_CONSOLE="$GUEST_PID"
run_guest 55 "$ROUTER_PORT" "$ROUTER_COMMAND" "$RESULT_DIR/router.serial.log"
ROUTER_CONSOLE="$GUEST_PID"
wait "$ROUTER_CONSOLE" || true
wait "$EXTERNAL_CONSOLE" || true
tr -d '\r' < "$RESULT_DIR/router.serial.log" > "$RESULT_DIR/router.serial.normalized.log"
tr -d '\r' < "$RESULT_DIR/external.serial.log" > "$RESULT_DIR/external.serial.normalized.log"
grep -Fxq ROUTER_AWG_OUT_PASS "$RESULT_DIR/router.serial.normalized.log" || fail 'router awg-out test failed'
grep -Fxq OUTBOUND_LINK_PASS "$RESULT_DIR/router.serial.normalized.log" || fail 'router outbound link test failed'
for marker in EXTERNAL_AWG_READY EXTERNAL_AWG_TRANSFER_PASS; do grep -Fxq "$marker" "$RESULT_DIR/external.serial.normalized.log" || fail "external awg-out test failed: $marker"; done
record AWG_OUTBOUND PASS
record EXTERNAL_AWG_TRANSFER PASS
record CONTROLLED_AWG_ENDPOINT PASS
printf 'VIRTUAL_AWG_OUT_VALIDATION=PASS\n' >> "$RESULT_DIR/summary.txt"
echo "VM AWG-OUT TEST PASS: $RESULT_DIR"
