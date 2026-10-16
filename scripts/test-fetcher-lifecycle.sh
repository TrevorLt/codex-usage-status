#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
fixture_root="$project_root/macos/CodexUsageStatus/IntegrationTests/FetcherLifecycle"
test_dir="$(mktemp -d /private/tmp/codex-fetcher-lifecycle.XXXXXX)"
sdk_path="$(xcrun --show-sdk-path)"

swiftc -swift-version 6 -sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$test_dir/module-cache" \
  "$source_root/App/Configuration.swift" \
  "$source_root/Codex/CodexUsageFetcher.swift" \
  "$source_root/Domain/UsageModels.swift" \
  "$fixture_root/main.swift" \
  -o "$test_dir/FetcherLifecycleHarness"

"$test_dir/FetcherLifecycleHarness"
