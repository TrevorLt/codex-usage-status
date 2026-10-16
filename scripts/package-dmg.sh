#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
VERSION="${VERSION:-0.1.2}"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
DMG_NAME="CodexUsageStatus-${VERSION}-macos-${BUILD_ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RW_DMG="$DIST_DIR/.CodexUsageStatus-${VERSION}-${BUILD_ARCH}-rw.dmg"
BACKGROUND="$ROOT_DIR/branding/dmg-background.png"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle at $APP_DIR; build the app before creating a DMG." >&2
  exit 1
fi

case "$BUILD_ARCH" in
  arm64 | x86_64)
    ;;
  *)
    echo "Unsupported BUILD_ARCH '$BUILD_ARCH'. Use arm64 or x86_64." >&2
    exit 1
    ;;
esac

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-status-dmg.XXXXXX")"
HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-status-dmg-helper.XXXXXX")"
MOUNT_POINT=""
DEVICE=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -Fq "on $MOUNT_POINT "; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  rm -rf "$STAGING_DIR"
  rm -rf "$HELPER_DIR"
  rm -f "$RW_DMG"
}
trap cleanup EXIT

SDK_PATH="$(xcrun --show-sdk-path)"
HOST_ARCH="$(uname -m)"
swiftc -swift-version 6 \
  -sdk "$SDK_PATH" \
  -target "${HOST_ARCH}-apple-macosx13.0" \
  -module-cache-path "$DIST_DIR/module-cache-dmg-$HOST_ARCH" \
  "$ROOT_DIR/scripts/create-dmg-background.swift" \
  -o "$HELPER_DIR/create-dmg-background"

"$HELPER_DIR/create-dmg-background" \
  --output "$BACKGROUND" \
  --icon "$ROOT_DIR/branding/validation/app-icon-256.png"

mkdir -p "$STAGING_DIR/.background"
ditto "$APP_DIR" "$STAGING_DIR/CodexUsageStatus.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND" "$STAGING_DIR/.background/dmg-background.png"

rm -f "$RW_DMG" "$DMG_PATH"
hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "Codex Usage Status" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {sub(/^.*Apple_HFS[[:space:]]+/, ""); print; exit}')"

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Could not determine the mounted DMG device or mount point." >&2
  printf '%s\n' "$ATTACH_OUTPUT" >&2
  exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "Codex Usage Status"
        open
        delay 1
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set bounds of theWindow to {120, 100, 1080, 700}
        set viewOptions to icon view options of theWindow
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set arrangement of viewOptions to not arranged
        set background picture of viewOptions to file ".background:dmg-background.png"
        set position of item "CodexUsageStatus.app" to {270, 335}
        set position of item "Applications" to {690, 335}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "$DEVICE" -quiet
MOUNT_POINT=""
DEVICE=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
