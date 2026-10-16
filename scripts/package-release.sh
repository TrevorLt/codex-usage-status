#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
VERSION="${VERSION:-0.1.1}"

detect_hardware_arch() {
  local machine
  machine="$(uname -m)"

  if [[ "$machine" == "x86_64" ]]; then
    if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
      echo "arm64"
      return
    fi
  fi

  echo "$machine"
}

BUILD_ARCH="${BUILD_ARCH:-$(detect_hardware_arch)}"
export BUILD_ARCH

case "$BUILD_ARCH" in
  arm64 | x86_64)
    ;;
  *)
    echo "Unsupported BUILD_ARCH '$BUILD_ARCH'. Use arm64 or x86_64." >&2
    exit 1
    ;;
esac

ZIP_NAME="CodexUsageStatus-${VERSION}-macos-${BUILD_ARCH}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

"$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

rm -f "$DIST_DIR"/CodexUsageStatus-"$VERSION"-macos-*.zip "$DIST_DIR/SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

(
  cd "$DIST_DIR"
  openssl dgst -sha256 -r "$ZIP_NAME" > SHA256SUMS.txt
)

echo "$ZIP_PATH"
