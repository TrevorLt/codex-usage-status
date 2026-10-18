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
                    if expectedWarning, let warningOverlay = rendering.warningOverlay {
                        let centerRedPixels = try countRedPixels(
                            in: warningOverlay,
                            xRange: style == .doubleRing ? 23..<35 : 18..<41,
                            yRange: style == .doubleRing ? 8..<16 : 6..<18
                        )
                        check(centerRedPixels == 0,
                            "\(style) \(remaining)% warning overlay keeps the center reading neutral in \(appearanceLabel); got \(centerRedPixels) red center pixels")
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
        case darkNeutral
        case lightNeutral
    }

    private struct RenderedButton {
        let bitmap: NSBitmapImageRep
        let imageIsTemplate: Bool
    }

    @MainActor
    private static func countRedPixels(in bitmap: NSBitmapImageRep, xRange: Range<Int>? = nil) -> Int {
        countPixels(in: bitmap, xRange: xRange ?? 0..<90, yRange: 0..<bitmap.pixelsHigh, matching: .red)
    }

    @MainActor
    private static func countRedPixels(in image: NSImage, xRange: Range<Int>, yRange: Range<Int>) throws -> Int {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            throw AuditFailure(message: "could not rasterize warning overlay")
        }
        return countPixels(in: bitmap, xRange: xRange, yRange: yRange, matching: .red)
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
            rateLimitsByLimitId: nil
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
