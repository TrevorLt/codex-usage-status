#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/NativeFaults"
test_dir="$(mktemp -d /private/tmp/codex-native-faults.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}" \
  "$source_root/App/Configuration.swift" \
  "$source_root/Codex/CodexUsageFetcher.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$fixture_root/main.swift" \
  -o "$test_dir/NativeFaultsHarness"

chmod +x "$fixture_root/fake-server.mjs"
node "$fixture_root/run.mjs" \
  "$test_dir/NativeFaultsHarness" \
  "$fixture_root/fake-server.mjs" \
  "$test_dir"
