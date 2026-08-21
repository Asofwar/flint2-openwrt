#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
SIGNING_KEY="${FLINT2_APK_SIGNING_KEY:?set FLINT2_APK_SIGNING_KEY to the P-256 private key}"
OUT="${OUT:-$PROJECT_DIR/artifacts/apk-repository}"
APK="$BUILDROOT/staging_dir/host/bin/apk"
PUBLIC_KEY="$PROJECT_DIR/files/etc/apk/keys/flint2-custom-repository.pem"

fail() { echo "APK REPOSITORY PREPARATION FAILED: $*" >&2; exit 1; }
test -x "$APK" || fail "OpenWrt host apk is absent"
test -f "$SIGNING_KEY" || fail "signing key is absent"
test -f "$PUBLIC_KEY" || fail "public key is absent"
case "$OUT" in
  "$PROJECT_DIR"/artifacts/*) ;;
  *) fail "output directory must be inside $PROJECT_DIR/artifacts" ;;
esac

generated_public_key="$(mktemp)"
trap 'rm -f "$generated_public_key"' EXIT
openssl ec -in "$SIGNING_KEY" -pubout -out "$generated_public_key" >/dev/null 2>&1
cmp -s "$generated_public_key" "$PUBLIC_KEY" || fail "signing key does not match the embedded public key"

rm -rf "$OUT"
mkdir -p "$OUT/keys"
cp "$PUBLIC_KEY" "$OUT/keys/flint2-custom-repository.pem"

copy_packages() {
  local source_dir="$1"
  shift
  local pattern
  for pattern in "$@"; do
    local package
    package="$(find "$source_dir" -maxdepth 1 -type f -name "$pattern" -print -quit)"
    test -n "$package" || fail "missing package: $source_dir/$pattern"
    local published_name
    published_name="$(basename "$package" | tr '~' '.')"
    cp -f "$package" "$OUT/$published_name"
  done
}

TARGET_PACKAGES="$BUILDROOT/bin/targets/mediatek/filogic/packages"
AWG_PACKAGES="$BUILDROOT/bin/packages/aarch64_cortex-a53/awg"
PODKOP_PACKAGES="$BUILDROOT/bin/packages/aarch64_cortex-a53/podkop"

copy_packages "$TARGET_PACKAGES" "kmod-amneziawg-${OPENWRT_KERNEL}*.apk"
copy_packages "$AWG_PACKAGES" 'amneziawg-tools-*.apk' 'luci-proto-amneziawg-*.apk' 'luci-i18n-amneziawg-ru-*.apk'
copy_packages "$PODKOP_PACKAGES" 'podkop-*.apk' 'luci-app-podkop-*.apk' 'luci-i18n-podkop-ru-*.apk'

make_index() {
  local index_name="$1"
  shift
  "$APK" --allow-untrusted mkndx --output "$OUT/$index_name" "$@"
  "$APK" --allow-untrusted adbsign --reset-signatures --sign-key "$SIGNING_KEY" "$OUT/$index_name"
  "$APK" --keys-dir "$OUT/keys" verify "$OUT/$index_name" >/dev/null
}

make_index flint2-target-packages.adb "$OUT"/kmod-amneziawg-*.apk
make_index flint2-awg-packages.adb "$OUT"/amneziawg-tools-*.apk "$OUT"/luci-proto-amneziawg-*.apk "$OUT"/luci-i18n-amneziawg-ru-*.apk
make_index flint2-podkop-packages.adb "$OUT"/podkop-*.apk "$OUT"/luci-app-podkop-*.apk "$OUT"/luci-i18n-podkop-ru-*.apk

{
  echo "OPENWRT_VERSION=$OPENWRT_VERSION"
  echo "OPENWRT_COMMIT=$OPENWRT_COMMIT"
  echo "KERNEL_VERSION=$OPENWRT_KERNEL"
  echo "TARGET=mediatek/filogic"
  echo "ARCHITECTURE=aarch64_cortex-a53"
  echo "RELEASE_TAG=$FLINT2_APK_REPOSITORY_TAG"
  echo "PACKAGES=$(find "$OUT" -maxdepth 1 -type f -name '*.apk' -printf '%f ' | LC_ALL=C sort | tr '\n' ' ')"
} > "$OUT/REPOSITORY_INFO.txt"

(
  cd "$OUT"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\0' \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum > SHA256SUMS
)

echo "APK repository is ready in $OUT"
