# Codex Usage Status v0.1.4

This patch release improves low-usage warning readability.

## Fixes

- Keep the 5H/7D percentage text in the native menu-bar contrast color when a window is below 20% remaining.
- Limit the warning overlay to the red ring or readout bar instead of recoloring the percentage text.
- Render a complete red warning ring at 0% so an exhausted window remains visibly actionable without relying on red text.
- Add AppKit pixel-level regression coverage for 0%, 19%, and 20% thresholds across both display styles and light/dark appearances.

Based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld), under the preserved MIT license. Independent maintenance and these changes do not imply affiliation with OpenAI.
