#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Codex Usage Status.app"
VERSION="${VERSION:-0.1.4}"
ARCHES=("arm64" "x86_64")

rm -f "$DIST_DIR"/CodexUsageStatus-"$VERSION"-macos-*.zip "$DIST_DIR"/CodexUsageStatus-"$VERSION"-macos-*.dmg "$DIST_DIR/SHA256SUMS.txt"

for arch in "${ARCHES[@]}"; do
  BUILD_ARCH="$arch" VERSION="$VERSION" "$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null
  ZIP_NAME="CodexUsageStatus-${VERSION}-macos-${arch}.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/$ZIP_NAME"
  BUILD_ARCH="$arch" VERSION="$VERSION" "$ROOT_DIR/scripts/package-dmg.sh" >/dev/null
done

(
  cd "$DIST_DIR"
  openssl dgst -sha256 -r CodexUsageStatus-"$VERSION"-macos-*.zip CodexUsageStatus-"$VERSION"-macos-*.dmg > SHA256SUMS.txt
)

VERSION="$VERSION" "$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

echo "$DIST_DIR"
