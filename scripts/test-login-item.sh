#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$project_root/macos/CodexUsageStatus"
source_file="$package_dir/Sources/CodexUsageStatus/App/LoginItemController.swift"
test_source="$package_dir/IntegrationTests/LoginItem/main.swift"
test_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-login-item.XXXXXX")"
mkdir -p "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}"
trap 'rm -rf "$test_dir"' EXIT

swiftc -swift-version 6 -O -parse-as-library \
  -module-cache-path "${CODEX_USAGE_TEST_MODULE_CACHE:-$test_dir/module-cache}" \
  "$source_file" "$test_source" -o "$test_dir/LoginItemAudit"

"$test_dir/LoginItemAudit"
