#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Codex Usage Status.app"
VERSION="${VERSION:-0.1.3}"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
DMG_NAME="CodexUsageStatus-${VERSION}-macos-${BUILD_ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RW_DMG="$DIST_DIR/.CodexUsageStatus-${VERSION}-${BUILD_ARCH}-rw.dmg"

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
  --output "$HELPER_DIR/dmg-background-1x.png" \
  --scale 1 \
  --icon "$ROOT_DIR/branding/validation/app-icon-256.png"
"$HELPER_DIR/create-dmg-background" \
  --output "$HELPER_DIR/dmg-background-2x.png" \
  --scale 2 \
  --icon "$ROOT_DIR/branding/validation/app-icon-256.png"

# Finder treats the background as a point-sized image. Combine 1x and 2x
# TIFF representations so Retina displays get sharp artwork without doubling
# the logical layout or moving the app and Applications icons.
cp "$HELPER_DIR/dmg-background-1x.png" "$ROOT_DIR/branding/dmg-background.png"
sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 \
  "$HELPER_DIR/dmg-background-1x.png" \
  --out "$HELPER_DIR/dmg-background-1x.tiff" >/dev/null
sips -s format tiff -s dpiWidth 144 -s dpiHeight 144 \
  "$HELPER_DIR/dmg-background-2x.png" \
  --out "$HELPER_DIR/dmg-background-2x.tiff" >/dev/null
tiffutil -cathidpicheck \
  "$HELPER_DIR/dmg-background-1x.tiff" \
  "$HELPER_DIR/dmg-background-2x.tiff" \
  -out "$HELPER_DIR/dmg-background.tiff" >/dev/null
BACKGROUND="$HELPER_DIR/dmg-background.tiff"

mkdir -p "$STAGING_DIR/.background"
ditto "$APP_DIR" "$STAGING_DIR/Codex Usage Status.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND" "$STAGING_DIR/.background/dmg-background.tiff"

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

BACKGROUND_PATH="$MOUNT_POINT/.background/dmg-background.tiff"

osascript <<APPLESCRIPT
tell application "Finder"
    set targetDisk to disk (POSIX file "$MOUNT_POINT")
    tell targetDisk
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
        set background picture of viewOptions to POSIX file "$BACKGROUND_PATH"
        set position of item "Codex Usage Status.app" to {270, 335}
        set extension hidden of item "Codex Usage Status.app" to true
        set position of item "Applications" to {690, 335}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Finder can clear the volume custom-icon bit while saving the window layout.
# Apply the icon after Finder closes so the flag survives conversion to UDZO.
cp "$ROOT_DIR/branding/CodexUsageStatus.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"
SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"

hdiutil detach "$DEVICE" -quiet
MOUNT_POINT=""
DEVICE=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
