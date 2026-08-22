#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${VM_IMAGE:-$(find "$PROJECT_DIR/artifacts/vm" -maxdepth 1 -type f -name '*squashfs-combined.img.gz' -print -quit)}"
RUN_ID="${VM_BACKUP_RESTORE_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RESULT_DIR="$PROJECT_DIR/artifacts/test-results/$RUN_ID"
SERIAL_PORT="${VM_BACKUP_RESTORE_SERIAL_PORT:-19031}"
QEMU_PID=''
CONSOLE_PID=''
VM_BASE_DISK=''
VM_DISK=''

fail() { echo "VM BACKUP/RESTORE TEST FAILED: $*" >&2; exit 1; }
record() { printf '%s=%s\n' "$1" "$2" >> "$RESULT_DIR/summary.txt"; }
cleanup() {
	for pid in "$QEMU_PID" "$CONSOLE_PID"; do
		[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
	done
	for disk in "$VM_BASE_DISK" "$VM_DISK"; do
		[ -n "$disk" ] && rm -f "$disk"
	done
}
trap cleanup EXIT

test -n "$IMAGE" && test -f "$IMAGE" || fail 'x86_64 combined image is absent; run build-vm first'
command -v qemu-system-x86_64 >/dev/null || fail 'qemu-system-x86_64 is required'
command -v qemu-img >/dev/null || fail 'qemu-img is required'

mkdir -p "$RESULT_DIR"
printf 'VIRTUAL_BACKUP_RESTORE_VALIDATION=RUNNING\n' > "$RESULT_DIR/summary.txt"
VM_BASE_DISK="$(mktemp "${TMPDIR:-/tmp}/flint2-vm-backup-${RUN_ID}.XXXXXX.img")"
VM_DISK="${VM_BASE_DISK%.img}.qcow2"
gzip -cd "$IMAGE" > "$VM_BASE_DISK"
qemu-img create -f qcow2 -b "$VM_BASE_DISK" -F raw "$VM_DISK" >/dev/null

qemu-system-x86_64 \
	-machine q35 -m 512M -smp 2 -display none -monitor none \
	-drive "file=$VM_DISK,format=qcow2,if=virtio" \
	-netdev "user,id=wan,net=10.0.2.0/24" -device e1000,netdev=wan \
	-serial "tcp:127.0.0.1:$SERIAL_PORT,server=on,wait=off" \
	> "$RESULT_DIR/qemu.log" 2>&1 &
QEMU_PID=$!

GUEST_COMMAND='set -e
modprobe amneziawg
uci set vpn-dashboard.main.enabled=1
uci set vpn-dashboard.main.endpoint_mode=manual
uci set vpn-dashboard.main.endpoint_host=203.0.113.1
uci commit vpn-dashboard
/etc/init.d/vpn-dashboard restart
sleep 8
ifstatus awg_server | grep -q "\"up\": true"
/usr/libexec/vpn-dashboard-peer create restorepeer full >/tmp/restorepeer.conf
test "$(ls -ld /etc/vpn-dashboard/peers/restorepeer | awk "{print \$1}")" = "-rw-------"
/sbin/sysupgrade -b /tmp/vm-backup.tar.gz
for backup_path in \
  etc/config/network \
  etc/config/firewall \
  etc/config/dhcp \
  etc/config/podkop \
  etc/config/vpn-dashboard \
  etc/vpn-dashboard/peers/restorepeer; do
  tar -tzf /tmp/vm-backup.tar.gz | grep -qx "$backup_path"
done
echo BACKUP_ARCHIVE_PASS
uci set vpn-dashboard.main.endpoint_host=198.51.100.99
uci commit vpn-dashboard
/sbin/sysupgrade -r /tmp/vm-backup.tar.gz
uci get vpn-dashboard.main.endpoint_host | grep -qx 203.0.113.1
uci get vpn-dashboard.peer_restorepeer.name | grep -qx restorepeer
test "$(ls -ld /etc/vpn-dashboard/peers/restorepeer | awk "{print \$1}")" = "-rw-------"
rm -f /tmp/vm-backup.tar.gz /tmp/restorepeer.conf
echo BACKUP_RESTORE_PASS'

(
	sleep 35
	(
		printf '\nroot\n'
		sleep 3
		printf ': >/tmp/vm-backup-restore.sh\n'
		printf '%s' "$GUEST_COMMAND" | base64 | fold -w 60 | while IFS= read -r chunk; do
			printf 'printf %%s %s | base64 -d >>/tmp/vm-backup-restore.sh\n' "$chunk"
		done
		printf 'sh -e /tmp/vm-backup-restore.sh; status=$?; rm -f /tmp/vm-backup-restore.sh; exit $status\n'
		sleep 25
	) | timeout 150 nc -N 127.0.0.1 "$SERIAL_PORT"
) > "$RESULT_DIR/openwrt.serial.log" 2>&1 &
CONSOLE_PID=$!
wait "$CONSOLE_PID" || true

tr -d '\r' < "$RESULT_DIR/openwrt.serial.log" > "$RESULT_DIR/openwrt.serial.normalized.log"
grep -Fxq BACKUP_ARCHIVE_PASS "$RESULT_DIR/openwrt.serial.normalized.log" || fail 'backup archive contents or permissions check failed'
grep -Fxq BACKUP_RESTORE_PASS "$RESULT_DIR/openwrt.serial.normalized.log" || fail 'backup restore check failed'
record BACKUP_ARCHIVE PASS
record BACKUP_RESTORE PASS
cat > "$RESULT_DIR/junit.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="openwrt-vm-backup-restore" tests="2" failures="0">
  <testcase name="backup_archive_contents_and_permissions"/>
  <testcase name="restore_configuration_and_peer_secret"/>
</testsuite>
EOF
printf 'VIRTUAL_BACKUP_RESTORE_VALIDATION=PASS\n' >> "$RESULT_DIR/summary.txt"
echo "VM BACKUP/RESTORE TEST PASS: $RESULT_DIR"
