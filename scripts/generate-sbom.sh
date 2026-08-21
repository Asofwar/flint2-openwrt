#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/versions.env"
BUILDROOT="${BUILDROOT:-$PROJECT_DIR/.work/openwrt}"
OUT="${OUT:-$PROJECT_DIR/artifacts}"
MANIFEST="$OUT/packages.manifest"
SBOM="$OUT/SBOM.spdx"

fail() { echo "SBOM GENERATION FAILED: $*" >&2; exit 1; }
test -f "$MANIFEST" || fail "packages.manifest is absent"
test -d "$BUILDROOT/.git" || fail "OpenWrt checkout is absent"

created="$(git -C "$BUILDROOT" show -s --format=%cI HEAD)"
manifest_sha256="$(sha256sum "$MANIFEST" | awk '{print $1}')"
package_count="$(awk '$2 == "-" { count++ } END { print count + 0 }' "$MANIFEST")"

{
  echo 'SPDXVersion: SPDX-2.3'
  echo 'DataLicense: CC0-1.0'
  echo 'SPDXID: SPDXRef-DOCUMENT'
  echo 'DocumentName: Flint-2-OpenWrt-GL-MT6000'
  echo "DocumentNamespace: https://github.com/Asofwar/flint2-openwrt/spdx/$manifest_sha256"
  echo 'Creator: Tool: flint2-openwrt/scripts/generate-sbom.sh'
  echo "Created: $created"
  echo "DocumentComment: OpenWrt=$OPENWRT_COMMIT; kernel=$OPENWRT_KERNEL; packages=$package_count"

  index=0
  while read -r package separator version; do
    test "$separator" = '-' || continue
    index=$((index + 1))
    package_id="SPDXRef-Package-$index"
    echo
    echo "PackageName: $package"
    echo "SPDXID: $package_id"
    echo "PackageVersion: $version"
    echo 'PackageDownloadLocation: NOASSERTION'
    echo 'FilesAnalyzed: false'
    echo 'PackageLicenseConcluded: NOASSERTION'
    echo 'PackageLicenseDeclared: NOASSERTION'
    echo "Relationship: SPDXRef-DOCUMENT DESCRIBES $package_id"
  done < "$MANIFEST"
} > "$SBOM"
