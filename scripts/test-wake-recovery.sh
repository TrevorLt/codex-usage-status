#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/WakeRecovery"
wake_test_dir="$(mktemp -d /private/tmp/codex-wake-recovery.XXXXXX)"
app_bundle="$wake_test_dir/Codex Usage Status Harness.app"
app_contents="$app_bundle/Contents"
app_binary="$app_contents/MacOS/CodexUsageStatusHarness"
bundle_identifier="dev.local.CodexUsageStatus.ResetExpiryHarness.$(/usr/bin/uuidgen)"
mkdir -p "$app_contents/MacOS" "$app_contents/Resources"
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$wake_test_dir/module-cache}" \
  "$source_root/App/AppDelegate.swift" \
  "$source_root/App/Configuration.swift" \
  "$source_root/App/LoginItemController.swift" \
  "$source_root/App/RefreshPolicy.swift" \
  "$source_root/Codex/ResetRedemptionFlow.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$source_root/UI/AboutRefreshCountdownView.swift" \
  "$source_root/UI/ResetReminderMenuContent.swift" \
  "$source_root/UI/UsageBadgeAnimator.swift" \
  "$source_root/UI/UsageBadgeRenderer.swift" \
  "$source_root/UI/BadgeStyle.swift" \
  "$source_root/UI/ApplicationAppearanceObserver.swift" \
  "$fixture_root/FakeFetcher.swift" "$fixture_root/main.swift" \
  -o "$app_binary"

cat > "$app_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageStatusHarness</string>
  <key>CFBundleIdentifier</key>
  <string>__BUNDLE_ID__</string>
  <key>CFBundleName</key>
  <string>Codex Usage Status Harness</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' "s/__BUNDLE_ID__/$bundle_identifier/g" "$app_contents/Info.plist"
printf 'APPL????' > "$app_contents/PkgInfo"

codesign --force --sign - "$app_bundle" >/dev/null

screenshot_path="$wake_test_dir/expired-window.png"
status_path="$screenshot_path.status"
rm -f "$status_path"
echo "Harness app: $app_bundle"
open -W -n "$app_bundle" --args "$screenshot_path"
if [[ ! -f "$status_path" ]]; then
  echo "FAIL: wake-recovery app did not emit its result marker. Artifacts: $wake_test_dir" >&2
  exit 1
fi
cat "$status_path"
if [[ "$(cat "$status_path")" != WAKE\ RECOVERY\ INTEGRATION\ PASS* ]]; then
  echo "FAIL: wake-recovery app did not pass. Artifacts: $wake_test_dir" >&2
  exit 1
fi
if [[ ! -s "$screenshot_path" ]]; then
  echo "FAIL: wake-recovery app did not render its status button. Artifacts: $wake_test_dir" >&2
  exit 1
fi
echo "Test artifacts: $wake_test_dir"
