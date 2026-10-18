#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos/CodexUsageStatus"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Codex Usage Status.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/branding/CodexUsageStatus.icns"
VERSION="${VERSION:-0.1.3}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

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

case "$BUILD_ARCH" in
  arm64 | x86_64)
    ;;
  *)
    echo "Unsupported BUILD_ARCH '$BUILD_ARCH'. Use arm64 or x86_64." >&2
    exit 1
    ;;
esac

TRIPLE="${BUILD_ARCH}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}"
SDK_PATH="$(xcrun --show-sdk-path)"
BINARY_PATH="$MACOS_DIR/CodexUsageStatus"

# The production target has no Swift package dependencies. Compile its source
# directly so local and release builds do not depend on SwiftPM's manifest
# linker/cache state (the package manifest remains available for XCTest).
SWIFT_SOURCES=(
  "$SWIFT_DIR/Sources/CodexUsageStatus/App/"*.swift
  "$SWIFT_DIR/Sources/CodexUsageStatus/Codex/"*.swift
  "$SWIFT_DIR/Sources/CodexUsageStatus/Domain/"*.swift
  "$SWIFT_DIR/Sources/CodexUsageStatus/UI/"*.swift
  "$SWIFT_DIR/Sources/CodexUsageStatus/main.swift"
)

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon at $ICON_SOURCE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
swiftc -swift-version 6 -O \
  -sdk "$SDK_PATH" \
  -target "$TRIPLE" \
  -module-cache-path "$DIST_DIR/module-cache-$BUILD_ARCH" \
  "${SWIFT_SOURCES[@]}" \
  -o "$BINARY_PATH"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Build succeeded, but expected binary was not found at $BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ICON_SOURCE" "$RESOURCES_DIR/CodexUsageStatus.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageStatus</string>
  <key>CFBundleIdentifier</key>
  <string>dev.local.CodexUsageStatus</string>
  <key>CFBundleName</key>
  <string>Codex Usage Status</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage Status</string>
  <key>CFBundleIconFile</key>
  <string>CodexUsageStatus.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key>
  <string>__MIN_MACOS__</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT</string>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' "s/__VERSION__/$VERSION/g" "$CONTENTS_DIR/Info.plist"
/usr/bin/sed -i '' "s/__MIN_MACOS__/$MACOSX_DEPLOYMENT_TARGET/g" "$CONTENTS_DIR/Info.plist"

codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "$APP_DIR"
