#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/PathResolution"
test_dir="$(mktemp -d /private/tmp/codex-path-resolution.XXXXXX)"
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}" \
  "$source_root/App/Configuration.swift" \
  "$fixture_root/main.swift" \
  -o "$test_dir/PathResolverHarness"

"$test_dir/PathResolverHarness"
