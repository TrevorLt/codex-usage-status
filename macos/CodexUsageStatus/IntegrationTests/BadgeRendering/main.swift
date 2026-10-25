import AppKit
import Foundation

@main
struct BadgeRenderingAudit {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var assertions = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            assertions += 1
        }

        let now = Date()
        let appearances: [(NSAppearance.Name, NSColor, NSColor, String)] = [
            (.aqua, .black, .white, "aqua"),
            (.darkAqua, .white, NSColor(calibratedWhite: 0.18, alpha: 1), "darkAqua"),
        ]

        // The stale marker is separate from each full-size reading. Compare rasterized
        // number and marker regions so a '~' prefix cannot shrink the digits.
        let staleTestUsage = try makeUsage(primaryRemaining: 19, weeklyRemaining: 88, now: now)
        for style in BadgeStyle.allCases {
            let appearance = try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance")
            let staleBadge = UsageBadgeRenderer.rendering(for: staleTestUsage, style: style, appearance: appearance, isStale: true, now: now)
            let freshBadge = UsageBadgeRenderer.rendering(for: staleTestUsage, style: style, appearance: appearance, now: now)
            let staleBitmap = try rasterize(staleBadge.image)
            let freshBitmap = try rasterize(freshBadge.image)
            let numberRanges: (Range<Int>, Range<Int>) = style == .doubleRing
                ? (24..<34, 70..<80)
                : (15..<40, 61..<86)
            let markerRanges: (Range<Int>, Range<Int>) = style == .doubleRing
                ? (14..<24, 60..<71)
                : (12..<15, 58..<61)
            let separatorGapRange = style == .doubleRing ? 41..<49 : 39..<47

            check(countOpaquePixels(in: freshBitmap, xRange: separatorGapRange, yRange: 0..<24) == 0,
                "\(style) center gap has no separator dot")
            check(countDifferentPixels(in: staleBitmap, and: freshBitmap, xRange: numberRanges.0, yRange: 4..<20) == 0,
                "\(style) stale state leaves the left number at the same size and position")
            check(countDifferentPixels(in: staleBitmap, and: freshBitmap, xRange: numberRanges.1, yRange: 4..<20) == 0,
                "\(style) stale state leaves the right number at the same size and position")
            check(countDifferentPixels(in: staleBitmap, and: freshBitmap, xRange: markerRanges.0, yRange: 0..<24) > 0,
                "\(style) left stale mark is rendered beside the reading")
            check(countDifferentPixels(in: staleBitmap, and: freshBitmap, xRange: markerRanges.1, yRange: 0..<24) > 0,
                "\(style) right stale mark is rendered beside the reading")
        }

        // Both styles use the actual renderer and overlay view. A confirmed reset
        // highlights only its recovered window in system green.
        let resetTarget = try makeUsage(primaryRemaining: 100, weeklyRemaining: 82, now: now)
        let fiveHourResetTransition = UsageBadgeTransition(
            fromFiveHour: 8,
            fromWeekly: 82,
            toFiveHour: 100,
            toWeekly: 82,
            startUptime: 0,
            resetWindows: [.fiveHour]
        )
        let resetFrame = fiveHourResetTransition.frame(at: fiveHourResetTransition.duration / 2)
        for style in BadgeStyle.allCases {
            for (appearanceName, tint, background, appearanceLabel) in appearances {
                let appearance = try unwrap(NSAppearance(named: appearanceName), "missing appearance")
                let rendering = UsageBadgeRenderer.rendering(
                    for: resetTarget,
                    style: style,
                    appearance: appearance,
                    now: now,
                    animationFrame: resetFrame
                )
                let button = try renderButton(rendering, appearance: appearance, tint: tint, background: background, style: style)
                let fiveHourRange = style == .doubleRing ? 17..<41 : 0..<44
                let weeklyRange = style == .doubleRing ? 63..<87 : 48..<87
                check(rendering.resetOverlay != nil && rendering.resetOverlayAlpha == 1,
                    "\(style) reset frame has an active green overlay in \(appearanceLabel)")
                check(countGreenPixels(in: button.bitmap, xRange: fiveHourRange) > 0,
                    "\(style) confirmed 5h window turns green in \(appearanceLabel)")
                check(countGreenPixels(in: button.bitmap, xRange: weeklyRange) == 0,
                    "\(style) unchanged weekly window stays neutral in \(appearanceLabel)")
            }
        }

        let completedResetFrame = fiveHourResetTransition.frame(at: fiveHourResetTransition.duration)
        for style in BadgeStyle.allCases {
            let appearance = try unwrap(NSAppearance(named: .aqua), "missing aqua appearance")
            let rendering = UsageBadgeRenderer.rendering(
                for: resetTarget,
                style: style,
                appearance: appearance,
                now: now,
                animationFrame: completedResetFrame
            )
            let button = try renderButton(rendering, appearance: appearance, tint: .black, background: .white, style: style)
            check(rendering.resetOverlayAlpha == 0, "\(style) reset highlight fades to neutral at completion")
            check(countGreenPixels(in: button.bitmap) == 0, "\(style) completed reset has no lingering green")
        }

        // The rendered button is the regression surface: the template base and red overlay
        // are captured together after AppKit lays out the image and overlay view.
        for style in BadgeStyle.allCases {
            for remaining in [0, 19, 20] {
                let usage = try makeUsage(primaryRemaining: remaining, weeklyRemaining: 88, now: now)
                for (appearanceName, tint, background, appearanceLabel) in appearances {
                    let appearance = try unwrap(NSAppearance(named: appearanceName), "missing appearance")
                    let rendering = UsageBadgeRenderer.rendering(
                        for: usage,
                        style: style,
                        appearance: appearance,
                        now: now
                    )
                    let button = try renderButton(rendering, appearance: appearance, tint: tint, background: background, style: style)
                    let redPixels = countRedPixels(in: button.bitmap)
                    let expectedWarning = remaining < 20

                    check(rendering.image.isTemplate, "\(style) \(remaining)% base remains a template in \(appearanceLabel)")
                    check((rendering.warningOverlay != nil) == expectedWarning, "\(style) \(remaining)% warning threshold in \(appearanceLabel)")
                    check((redPixels > 0) == expectedWarning, "\(style) \(remaining)% visible red pixels in \(appearanceLabel); got \(redPixels)")
                    if expectedWarning, style == .doubleRing {
                        let centerRedPixels = countRedPixels(in: button.bitmap, xRange: 24..<34, yRange: 8..<16)
                        check(centerRedPixels == 0,
                            "\(style) \(remaining)% composed button keeps the center reading neutral in \(appearanceLabel); got \(centerRedPixels) red center pixels")
                    }
                }
            }
        }

        // A low primary window stays red while the normal weekly window is still rendered
        // by AppKit's native template tint in both light and dark appearances.
        let mixedUsage = try makeUsage(primaryRemaining: 19, weeklyRemaining: 88, now: now)
        for style in BadgeStyle.allCases {
            for (appearanceName, tint, background, appearanceLabel) in appearances {
                let appearance = try unwrap(NSAppearance(named: appearanceName), "missing appearance")
                let rendering = UsageBadgeRenderer.rendering(for: mixedUsage, style: style, appearance: appearance, now: now)
                let button = try renderButton(rendering, appearance: appearance, tint: tint, background: background, style: style)

                check(button.imageIsTemplate, "\(style) mixed-state neutral image is installed as a template in \(appearanceLabel)")
                check(countPixels(in: button.bitmap, xRange: 0..<44, matching: .red) > 0, "\(style) mixed-state warning window is red in \(appearanceLabel)")
                check(countPixels(in: button.bitmap, xRange: 48..<86, matching: tint == .white ? .lightNeutral : .darkNeutral) > 0,
                    "\(style) mixed-state normal window keeps native tint in \(appearanceLabel)")
            }
        }

        // The amber reminder dot is fixed inside the existing button bounds, remains visible
        // in both appearances and styles, and composes with the existing red low-usage layer.
        for style in BadgeStyle.allCases {
            for remaining in [88, 19] {
                for (appearanceName, tint, background, appearanceLabel) in appearances {
                    let appearance = try unwrap(NSAppearance(named: appearanceName), "missing appearance")
                    let usage = try makeUsage(primaryRemaining: remaining, weeklyRemaining: 88, now: now)
                    let withReminder = UsageBadgeRenderer.rendering(
                        for: usage,
                        style: style,
                        appearance: appearance,
                        now: now,
                        showExpiryReminder: true
                    )
                    let withoutReminder = UsageBadgeRenderer.rendering(
                        for: usage,
                        style: style,
                        appearance: appearance,
                        now: now
                    )
                    let markedButton = try renderButton(withReminder, appearance: appearance, tint: tint, background: background, style: style)
                    let plainButton = try renderButton(withoutReminder, appearance: appearance, tint: tint, background: background, style: style)

                    check(UsageBadgeRenderer.statusItemLength(for: style) == 90,
                        "\(style) amber reminder does not expand the status item in \(appearanceLabel)")
                    check(countAmberPixels(in: markedButton.bitmap, xRange: 80..<90, yRange: 17..<24) > 0,
                        "\(style) amber reminder is visible at the fixed top-right in \(appearanceLabel)")
                    check(countAmberPixels(in: plainButton.bitmap) == 0,
                        "\(style) normal state has no amber reminder in \(appearanceLabel)")
                    check((countRedPixels(in: markedButton.bitmap) > 0) == (remaining < 20),
                        "\(style) amber reminder composes with the existing red warning in \(appearanceLabel)")
                }
            }
        }

        // An expired low reading is suppressed, but an unexpired low reading in the other
        // window still warns. Hiding cached readings suppresses all warning content.
        let expiredPrimary = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, primaryExpiry: -1)
        let expiredRendering = UsageBadgeRenderer.rendering(
            for: expiredPrimary,
            style: .doubleRing,
            appearance: try unwrap(NSAppearance(named: .aqua), "missing aqua appearance"),
            now: now
        )
        check(expiredRendering.image.isTemplate && expiredRendering.warningOverlay == nil,
            "expired zero reading is hidden and leaves a native template badge")
        let expiredButton = try renderButton(
            expiredRendering,
            appearance: try unwrap(NSAppearance(named: .aqua), "missing aqua appearance"),
            tint: .black,
            background: .white,
            style: .doubleRing
        )
        check(countRedPixels(in: expiredButton.bitmap) == 0, "expired zero reading has no red pixels")

        let otherWindowWarning = try makeUsage(primaryRemaining: 0, weeklyRemaining: 19, now: now, primaryExpiry: -1)
        let weeklyWarning = UsageBadgeRenderer.rendering(
            for: otherWindowWarning,
            style: .doubleRing,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            now: now
        )
        let weeklyWarningButton = try renderButton(
            weeklyWarning,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            tint: .white,
            background: NSColor(calibratedWhite: 0.18, alpha: 1),
            style: .doubleRing
        )
        check(countRedPixels(in: weeklyWarningButton.bitmap, xRange: 48..<86) > 0,
            "unexpired weekly warning remains visible when the primary window is expired")

        let cached = UsageBadgeRenderer.rendering(
            for: mixedUsage,
            style: .largeReadout,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            isStale: true,
            now: now,
            hideReadings: true
        )
        let cachedButton = try renderButton(
            cached,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            tint: .white,
            background: NSColor(calibratedWhite: 0.18, alpha: 1),
            style: .largeReadout
        )
        check(cached.image.isTemplate && cached.warningOverlay == nil, "hidden cached readings use only the template base")
        check(countRedPixels(in: cachedButton.bitmap) == 0, "hidden cached readings have no red pixels")

        let stale = UsageBadgeRenderer.rendering(
            for: mixedUsage,
            style: .doubleRing,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            isStale: true,
            now: now
        )
        let fresh = UsageBadgeRenderer.rendering(
            for: mixedUsage,
            style: .doubleRing,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            now: now
        )
        check(stale.image.isTemplate && stale.warningOverlay != nil, "stale warning keeps the native template base and red overlay")
        check(stale.image.tiffRepresentation != fresh.image.tiffRepresentation,
            "stale marker remains in the compatibility image layer")

        try verifyAppearanceObserver(app: app, usage: mixedUsage, check: check)

        print("BADGE RENDERING PASS: \(assertions) assertions; AppKit button composition, both styles and appearances")
    }

    @MainActor
    private static func verifyAppearanceObserver(
        app: NSApplication,
        usage: UsageSummary,
        check: @MainActor (Bool, String) -> Void
    ) throws {
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }
        app.appearance = NSAppearance(named: .aqua)

        var callbackImageIsTemplate = false
        var callbackHasWarningOverlay = false
        let observer = ApplicationAppearanceObserver {
            let rendering = UsageBadgeRenderer.rendering(
                for: usage,
                style: .doubleRing,
                appearance: app.effectiveAppearance
            )
            callbackImageIsTemplate = rendering.image.isTemplate
            callbackHasWarningOverlay = rendering.warningOverlay != nil
        }

        app.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check(callbackImageIsTemplate, "appearance observer rebuilds a template base")
        check(callbackHasWarningOverlay, "appearance observer retains the separate warning overlay")
        withExtendedLifetime(observer) {}
    }

    @MainActor
    private static func renderButton(
        _ rendering: UsageBadgeRendering,
        appearance: NSAppearance,
        tint: NSColor,
        background: NSColor,
        style: BadgeStyle
    ) throws -> RenderedButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: UsageBadgeRenderer.statusItemLength(for: style), height: 24))
        button.isBordered = false
        button.title = ""
        button.appearance = appearance
        button.contentTintColor = tint
        button.wantsLayer = true
        button.layer?.backgroundColor = try unwrap(background.usingColorSpace(.deviceRGB)?.cgColor, "background color conversion failed")
        UsageBadgeRenderer.apply(rendering, to: button)
        button.layoutSubtreeIfNeeded()

        guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
            throw AuditFailure(message: "AppKit could not allocate a button bitmap")
        }
        button.cacheDisplay(in: button.bounds, to: bitmap)
        return RenderedButton(bitmap: bitmap, imageIsTemplate: button.image?.isTemplate == true)
    }

    private enum PixelKind {
        case red
        case amber
        case green
        case darkNeutral
        case lightNeutral
    }

    private struct RenderedButton {
        let bitmap: NSBitmapImageRep
        let imageIsTemplate: Bool
    }

    @MainActor
    private static func countRedPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>? = nil,
        yRange: Range<Int>? = nil
    ) -> Int {
        countPixels(in: bitmap, xRange: xRange ?? 0..<90, yRange: yRange, matching: .red)
    }

    @MainActor
    private static func countAmberPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>? = nil,
        yRange: Range<Int>? = nil
    ) -> Int {
        countPixels(in: bitmap, xRange: xRange ?? 0..<90, yRange: yRange, matching: .amber)
    }

    @MainActor
    private static func countGreenPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>? = nil,
        yRange: Range<Int>? = nil
    ) -> Int {
        countPixels(in: bitmap, xRange: xRange ?? 0..<90, yRange: yRange, matching: .green)
    }

    @MainActor
    private static func rasterize(_ image: NSImage) throws -> NSBitmapImageRep {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            throw AuditFailure(message: "could not rasterize badge image")
        }
        return bitmap
    }

    @MainActor
    private static func countDifferentPixels(
        in lhs: NSBitmapImageRep,
        and rhs: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Int {
        let scale = CGFloat(lhs.pixelsWide) / 86
        let minX = max(0, Int((CGFloat(xRange.lowerBound) * scale).rounded(.down)))
        let maxX = min(lhs.pixelsWide, Int((CGFloat(xRange.upperBound) * scale).rounded(.up)))
        let minY = max(0, Int((CGFloat(yRange.lowerBound) * scale).rounded(.down)))
        let maxY = min(lhs.pixelsHigh, Int((CGFloat(yRange.upperBound) * scale).rounded(.up)))
        var count = 0

        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let difference = abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                    + abs(left.alphaComponent - right.alphaComponent)
                if difference > 0.05 { count += 1 }
            }
        }
        return count
    }

    @MainActor
    private static func countOpaquePixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / 86
        let minX = max(0, Int((CGFloat(xRange.lowerBound) * scale).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((CGFloat(xRange.upperBound) * scale).rounded(.up)))
        let minY = max(0, Int((CGFloat(yRange.lowerBound) * scale).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((CGFloat(yRange.upperBound) * scale).rounded(.up)))
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                if let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent, alpha > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }

    @MainActor
    private static func countPixels(in bitmap: NSBitmapImageRep, xRange: Range<Int>, yRange: Range<Int>? = nil, matching kind: PixelKind) -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / 90
        let minX = max(0, Int((CGFloat(xRange.lowerBound) * scale).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((CGFloat(xRange.upperBound) * scale).rounded(.up)))
        let effectiveYRange = yRange ?? 0..<bitmap.pixelsHigh
        let minY = max(0, Int((CGFloat(effectiveYRange.lowerBound) * scale).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((CGFloat(effectiveYRange.upperBound) * scale).rounded(.up)))
        var count = 0

        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                let alpha = color.alphaComponent

                switch kind {
                case .red:
                    if alpha > 0.2 && red > 0.35 && red > green * 1.5 && red > blue * 1.5 { count += 1 }
                case .amber:
                    if alpha > 0.2 && red > 0.7 && green > 0.4 && green < 0.8 && blue < 0.4 { count += 1 }
                case .green:
                    if alpha > 0.2 && green > 0.3 && green > red * 1.15 && green > blue * 1.05 { count += 1 }
                case .darkNeutral:
                    if alpha > 0.2 && abs(red - green) < 0.08 && abs(green - blue) < 0.08 && red < 0.65 { count += 1 }
                case .lightNeutral:
                    if alpha > 0.2 && abs(red - green) < 0.08 && abs(green - blue) < 0.08 && red > 0.45 { count += 1 }
                }
            }
        }
        return count
    }

    private static func makeUsage(
        primaryRemaining: Int,
        weeklyRemaining: Int,
        now: Date,
        primaryExpiry: TimeInterval = 3_600,
        weeklyExpiry: TimeInterval = 86_400
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: Double(100 - primaryRemaining),
                    windowDurationMins: 300,
                    resetsAt: now.timeIntervalSince1970 + primaryExpiry
                ),
                secondary: RateLimitWindow(
                    usedPercent: Double(100 - weeklyRemaining),
                    windowDurationMins: 10_080,
                    resetsAt: now.timeIntervalSince1970 + weeklyExpiry
                ),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil,
            accountId: "test-account"
        ))
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw AuditFailure(message: message) }
        return value
    }
}

private struct AuditFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
