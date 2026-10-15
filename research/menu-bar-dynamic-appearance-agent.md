# Apple AppKit menu-bar appearance findings

## Conclusion

For a standard macOS menu-bar extra, the native strategy is to assign a monochrome, glyph-like `NSImage` to `NSStatusItem.button.image` and set `image.isTemplate = true`. The status-bar button then owns the tinting and state styling. This is preferable to choosing a hard-coded black/white color from `NSAppearance`.

Apple's SDK header is unusually explicit: `NSStatusBarButton` says that a template image is rendered with the correct menu-bar style and will look correct across button states and appearances, including a dark menu bar. This is the strongest evidence that template rendering is the mechanism used for native foreground adaptation.

## Primary sources

- [`NSStatusBarButton` header](https://github.com/apple-oss-distributions/AppKit/blob/main/Headers/NSStatusBarButton.h) — Apple documents that a template image on the button is rendered with the correct menu-bar style and adapts to appearances such as a dark menu bar. The same text is present in the local SDK at `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSStatusBarButton.h`.
- [`NSStatusItem.button`](https://developer.apple.com/documentation/appkit/nsstatusitem/button) — the status item creates the button automatically; customize its appearance through the button, including its `image`.
- [`NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusitem) — `button` is the current API for the status item; the older `NSStatusItem.image` and custom `view` paths are deprecated. The header specifically advises using the standard button with a template image instead of a custom status-item view.
- [`NSImage.isTemplate`](https://developer.apple.com/documentation/appkit/nsimage/istemplate) — template images should contain black and clear content and are processed by clients to create the appropriate appearance. Apple describes them as glyph-like art intended to be processed for on-screen use.
- [`NSAppearance`](https://developer.apple.com/documentation/appkit/nsappearance) — AppKit appearances determine which colors and images controls use; AppKit sets the current drawing appearance while drawing controls, and template images are among the images affected by that drawing context.
- [`NSView.effectiveAppearance`](https://developer.apple.com/documentation/appkit/nsappearancecustomization/effectiveappearance) and [`viewDidChangeEffectiveAppearance`](https://developer.apple.com/documentation/appkit/nsview/viewdidchangeeffectiveappearance%28%29) — useful for custom views or custom-colored drawing that must be redrawn when the inherited appearance changes, but not a substitute for the status-button template-image path.

## Implementation implications for CodexUsageStatus

1. Render the normal, non-warning badge as a single-color mask with transparent background, then set `isTemplate = true` before assigning it to `statusItem.button.image`.
2. Do not hard-code `NSColor.black` for light mode or `NSColor.white` for dark mode. The status-bar button should choose the foreground/tint appropriate to the actual menu-bar style.
3. Keep an explicit colored rendering only for states that need semantic color, such as the existing below-20%-remaining red warning. A multicolor image cannot be treated as a pure template image without losing that distinction; its neutral portions should use dynamic AppKit colors and it should still be redrawn when the effective appearance changes.
4. Continue observing appearance changes for the multicolor warning/error fallback and for a deterministic redraw after system appearance changes. For the ordinary template-image state, AppKit should perform the foreground adaptation when it draws the status-bar button.
5. Verify the result on both light and dark menu bars and while switching appearance without clicking Refresh. The expected behavior is native tint adaptation, not a fixed light/dark color mapping.

## Scope note

Apple's public documentation describes template processing and menu-bar style adaptation; it does not promise an application-level API that exposes the sampled pixels or exact background luminance behind an individual status item. Therefore the correct implementation should delegate adaptation to `NSStatusBarButton` rather than attempting to sample the menu bar itself.
