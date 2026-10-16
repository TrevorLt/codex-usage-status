#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/WakeRecovery"
wake_test_dir="$(mktemp -d /private/tmp/codex-wake-recovery.XXXXXX)"
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$wake_test_dir/module-cache" \
  "$source_root/App/AppDelegate.swift" \
  "$source_root/App/Configuration.swift" \
  "$source_root/App/RefreshPolicy.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$source_root/UI/UsageBadgeRenderer.swift" \
  "$source_root/UI/BadgeStyle.swift" \
  "$source_root/UI/ApplicationAppearanceObserver.swift" \
  "$fixture_root/FakeFetcher.swift" "$fixture_root/main.swift" \
  -o "$wake_test_dir/WakeRecoveryHarness"

"$wake_test_dir/WakeRecoveryHarness" "$wake_test_dir/expired-window.png"
echo "Test artifacts: $wake_test_dir"
