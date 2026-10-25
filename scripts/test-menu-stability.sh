#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$project_root/macos/CodexUsageStatus"
source_dir="$package_dir/Sources/CodexUsageStatus"
test_source="$package_dir/IntegrationTests/MenuStability/main.swift"
test_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-menu-stability.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

swiftc -swift-version 6 -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}" \
  "$source_dir/Domain/UsageModels.swift" \
  "$source_dir/UI/ResetReminderMenuContent.swift" \
  "$test_source" -o "$test_dir/MenuStabilityAudit"

"$test_dir/MenuStabilityAudit"
