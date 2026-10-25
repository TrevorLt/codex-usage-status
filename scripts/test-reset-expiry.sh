#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/ResetExpiry"
test_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-reset-expiry.XXXXXX")"
module_cache_path="${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}"
mkdir -p "$module_cache_path"

swiftc -swift-version 6 -sdk "$(xcrun --show-sdk-path)" \
  -parse-as-library \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache_path" \
  "$source_root/App/Configuration.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$source_root/Codex/CodexUsageFetcher.swift" \
  "$fixture_root/main.swift" \
  -o "$test_dir/ResetExpiryAudit"

"$test_dir/ResetExpiryAudit"
