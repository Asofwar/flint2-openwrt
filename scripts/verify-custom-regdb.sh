#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"

fail() { echo "CUSTOM REGDB VERIFY FAILED: $*" >&2; exit 1; }

grep -qx 'CONFIG_PACKAGE_wireless-regdb=y' "$BUILDROOT/.config" || fail "wireless-regdb package is not selected"

DB_TXT="$(find "$BUILDROOT/build_dir" -type f -path '*/wireless-regdb-*/db.txt' -print -quit)"
REGDB="$(find "$BUILDROOT/build_dir" -type f -path '*/root-mediatek/lib/firmware/regulatory.db' -print -quit)"
MANIFEST="$(find "$BUILDROOT/bin/targets/mediatek/filogic" -maxdepth 1 -type f -name '*gl-mt6000*.manifest' -print -quit)"

test -n "$DB_TXT" || fail "customized wireless-regdb db.txt was not found"
test -s "$REGDB" || fail "regulatory.db is absent from the root filesystem"
test -n "$MANIFEST" || fail "firmware manifest was not found"

grep -Fq '(2400 - 2483.5 @ 40), (36)' "$DB_TXT" || fail "2.4 GHz custom rule is absent"
grep -Fq '(5150 - 5350 @ 160), (36)' "$DB_TXT" || fail "5 GHz custom rule is absent"
grep -Fq '(5470 - 5730 @ 160), (36)' "$DB_TXT" || fail "upper 5 GHz custom rule is absent"
grep -Fq '(5925 - 7125 @ 320), (36)' "$DB_TXT" || fail "6 GHz custom rule is absent"
grep -Fq '(57000 - 71000 @ 2160), (44)' "$DB_TXT" || fail "60 GHz custom rule is absent"

grep -q '^wireless-regdb - ' "$MANIFEST" || fail "wireless-regdb is absent from firmware manifest"

# The customizer intentionally removes country DFS-region suffixes. Spot-check
# a few common domains to catch accidental fallback to the stock source.
for cc in RU US DE; do
  grep -qx "country $cc:" "$DB_TXT" || fail "country $cc was not customized"
done

printf 'CUSTOM REGDB VERIFY PASSED: %s (%s bytes)\n' "$REGDB" "$(stat -c '%s' "$REGDB")"
