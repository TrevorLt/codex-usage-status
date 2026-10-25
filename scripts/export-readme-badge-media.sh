#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$project_root/macos/CodexUsageStatus/Sources/CodexUsageStatus"
exporter_source="$project_root/scripts/ExportReadmeBadgeMedia.swift"
exporter_binary="$project_root/dist/export-readme-badge-media"
module_cache="$project_root/dist/module-cache-readme-media"
assets_dir="$project_root/docs/assets"

mkdir -p "$project_root/dist" "$module_cache" "$assets_dir"
swiftc -swift-version 6 -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  "$source_dir/App/Configuration.swift" \
  "$source_dir/Codex/CodexUsageFetcher.swift" \
  "$source_dir/Domain/UsageModels.swift" \
  "$source_dir/UI/BadgeStyle.swift" \
  "$source_dir/UI/UsageBadgeAnimator.swift" \
  "$source_dir/UI/UsageBadgeRenderer.swift" \
  "$exporter_source" \
  -o "$exporter_binary"

"$exporter_binary" "$assets_dir"
