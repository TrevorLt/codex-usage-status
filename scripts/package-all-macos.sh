#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
VERSION="${VERSION:-0.1.2}"
ARCHES=("arm64" "x86_64")

rm -f "$DIST_DIR"/CodexUsageStatus-"$VERSION"-macos-*.zip "$DIST_DIR/SHA256SUMS.txt"

for arch in "${ARCHES[@]}"; do
  BUILD_ARCH="$arch" "$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null
  ZIP_NAME="CodexUsageStatus-${VERSION}-macos-${arch}.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/$ZIP_NAME"
done

(
  cd "$DIST_DIR"
  openssl dgst -sha256 -r CodexUsageStatus-"$VERSION"-macos-*.zip > SHA256SUMS.txt
)

"$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

echo "$DIST_DIR"
