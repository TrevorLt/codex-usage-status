#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/PolicyDomain"
test_dir="$(mktemp -d /private/tmp/codex-policy-domain.XXXXXX)"
module_cache_path="${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}"
mkdir -p "$module_cache_path"
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache_path" \
  "$source_root/App/Configuration.swift" \
  "$source_root/App/RefreshPolicy.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$fixture_root/main.swift" \
  -o "$test_dir/PolicyDomainHarness"

"$test_dir/PolicyDomainHarness"
