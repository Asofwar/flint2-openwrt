#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
JOBS="${JOBS:-$(nproc)}"

require() { command -v "$1" >/dev/null || { echo "missing required command: $1" >&2; exit 1; }; }
require git
require make
require sha256sum

if [[ ! -d "$BUILDROOT/.git" ]]; then
  mkdir -p "$(dirname "$BUILDROOT")"
  git clone "$OPENWRT_REPOSITORY" "$BUILDROOT"
fi

git -C "$BUILDROOT" fetch --tags --force "$OPENWRT_REPOSITORY"
git -C "$BUILDROOT" checkout --detach "$OPENWRT_COMMIT"
if [[ "$(git -C "$BUILDROOT" rev-parse HEAD)" != "$OPENWRT_COMMIT" ]]; then
  echo "OpenWrt checkout does not match the pinned commit" >&2
  exit 1
fi

if ! grep -Fqx "src-git-full awg $AMNEZIAWG_FEED_REPOSITORY^$AMNEZIAWG_FEED_COMMIT" "$BUILDROOT/feeds.conf.default"; then
cat >> "$BUILDROOT/feeds.conf.default" <<EOF
src-git-full awg $AMNEZIAWG_FEED_REPOSITORY^$AMNEZIAWG_FEED_COMMIT
src-git-full podkop $PODKOP_REPOSITORY^$PODKOP_COMMIT
EOF
fi

pushd "$BUILDROOT" >/dev/null
./scripts/feeds update -a
PODKOP_PATCH="$PROJECT_DIR/patches/podkop/0001-luci-25.12-single-buildpackage.patch"
if git -C feeds/podkop apply --check "$PODKOP_PATCH"; then
  git -C feeds/podkop apply "$PODKOP_PATCH"
elif ! git -C feeds/podkop apply --reverse --check "$PODKOP_PATCH"; then
  echo "Podkop compatibility patch does not apply to the pinned source" >&2
  exit 1
fi
./scripts/feeds install -a -p awg
./scripts/feeds install -a -p podkop
cp "$PROJECT_DIR/configs/gl-mt6000.config" .config
make defconfig
make download -j"$JOBS"
make -j"$JOBS" V=s
popd >/dev/null

BUILDROOT="$BUILDROOT" "$PROJECT_DIR/scripts/collect-artifacts.sh"
BUILDROOT="$BUILDROOT" "$PROJECT_DIR/scripts/verify-build.sh"
