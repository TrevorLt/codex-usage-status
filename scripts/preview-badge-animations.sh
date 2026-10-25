#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
preview_source="$project_root/macos/CodexUsageStatus/IntegrationTests/BadgeAnimationPreview/main.swift"
preview_dir="$project_root/dist"
preview_app="$preview_dir/Codex Usage Status Animation Preview v0.1.4.app"
preview_contents="$preview_app/Contents"
module_cache="$preview_dir/module-cache-badge-preview"
rm -rf "$preview_app"
mkdir -p "$module_cache" "$preview_contents/MacOS" "$preview_contents/Resources"

swift_sources=(
  "$source_dir/App/Configuration.swift"
  "$source_dir/Codex/CodexUsageFetcher.swift"
  "$source_dir/Domain/UsageModels.swift"
  "$source_dir/UI/BadgeStyle.swift"
  "$source_dir/UI/UsageBadgeAnimator.swift"
  "$source_dir/UI/UsageBadgeRenderer.swift"
)

swiftc -swift-version 6 -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  "${swift_sources[@]}" "$preview_source" \
  -o "$preview_contents/MacOS/BadgeAnimationPreview"

cat > "$preview_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>BadgeAnimationPreview</string>
  <key>CFBundleIdentifier</key>
  <string>dev.local.CodexUsageStatus.AnimationPreview.v014</string>
  <key>CFBundleName</key>
  <string>Codex Usage Status Animation Preview v0.1.4</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$preview_contents/PkgInfo"
codesign --force --sign - "$preview_app" >/dev/null
printf 'Animation preview: %s\n' "$preview_app"
open -n "$preview_app"
