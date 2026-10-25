#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
test_source="$project_root/macos/CodexUsageStatus/IntegrationTests/BadgeAnimation/main.swift"
test_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-badge-animation.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

swiftc -swift-version 6 -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}" \
  "$source_root/App/Configuration.swift" \
  "$source_root/Codex/CodexUsageFetcher.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$source_root/UI/UsageBadgeAnimator.swift" \
  "$test_source" -o "$test_dir/BadgeAnimationAudit"

"$test_dir/BadgeAnimationAudit"
