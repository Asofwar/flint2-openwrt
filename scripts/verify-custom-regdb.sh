#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"

fail() { echo "CUSTOM REGDB VERIFY FAILED: $*" >&2; exit 1; }

grep -qx 'CONFIG_PACKAGE_wireless-regdb=y' "$BUILDROOT/.config" || fail "wireless-regdb package is not selected"

DB_TXT="$(find "$BUILDROOT/build_dir" -type f -path '*/wireless-regdb-*/db.txt' -print -quit)"
STOCK_DB_TXT="$(find "$BUILDROOT/build_dir" -type f -path '*/wireless-regdb-*/db.txt.stock' -print -quit)"
REGDB="$(find "$BUILDROOT/build_dir" -type f -path '*/root-mediatek/lib/firmware/regulatory.db' -print -quit)"
MANIFEST="$(find "$BUILDROOT/bin/targets/mediatek/filogic" -maxdepth 1 -type f -name '*gl-mt6000*.manifest' -print -quit)"

test -n "$DB_TXT" || fail "customized wireless-regdb db.txt was not found"
test -n "$STOCK_DB_TXT" || fail "stock wireless-regdb db.txt snapshot was not found"
test -s "$REGDB" || fail "regulatory.db is absent from the root filesystem"
test -n "$MANIFEST" || fail "firmware manifest was not found"

extract_country() {
  awk -v country="$1" '
    $0 ~ ("^country " country ":") { inside = 1 }
    inside {
      if ($0 ~ /^country [A-Z0-9][A-Z0-9]:/ && $0 !~ ("^country " country ":")) exit
      print
    }
  ' "$2"
}

country_codes() {
  awk '/^country [A-Z0-9][A-Z0-9]:/ { print substr($2, 1, 2) }' "$1"
}

stock_countries="$(country_codes "$STOCK_DB_TXT")"
if grep -Fxq 'BJ' <<< "$stock_countries"; then
  expected_countries="$stock_countries"
else
  expected_countries="${stock_countries}"$'\nBJ'
fi
custom_countries="$(country_codes "$DB_TXT")"
diff -u <(printf '%s\n' "$expected_countries") <(printf '%s\n' "$custom_countries") >/dev/null || fail "country list was modified unexpectedly"

while IFS= read -r country; do
  test -n "$country" || continue
  diff -u <(extract_country "$country" "$STOCK_DB_TXT") <(extract_country "$country" "$DB_TXT") >/dev/null || fail "country $country was modified"
done <<< "$stock_countries"

grep -qx 'country BJ:' "$DB_TXT" || fail "country BJ is absent"
stock_world="$(extract_country 00 "$STOCK_DB_TXT")"
custom_world="$(extract_country 00 "$DB_TXT")"
test -n "$stock_world" || fail "stock country 00 is absent"
test -n "$custom_world" || fail "custom country 00 is absent"
diff -u <(printf '%s\n' "$stock_world") <(printf '%s\n' "$custom_world") >/dev/null || fail "country 00 was modified"
extract_country BJ "$DB_TXT" | grep -Fxq '    (5150 - 5350 @ 160), (36)' || fail "BJ 5150-5350 rule is absent"
extract_country BJ "$DB_TXT" | grep -Fxq '    (5925 - 7125 @ 320), (36)' || fail "BJ 5925-7125 rule is absent"

grep -q '^wireless-regdb - ' "$MANIFEST" || fail "wireless-regdb is absent from firmware manifest"

printf 'CUSTOM REGDB VERIFY PASSED: %s (%s bytes)\n' "$REGDB" "$(stat -c '%s' "$REGDB")"
