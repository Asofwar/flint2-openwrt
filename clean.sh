#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"

if [[ -d "$BUILDROOT" ]]; then
  make -C "$BUILDROOT" clean
fi
rm -rf "$PROJECT_DIR/artifacts"

