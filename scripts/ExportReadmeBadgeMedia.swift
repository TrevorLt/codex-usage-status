import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
@main
private enum ExportReadmeBadgeMedia {
    private static let canvasSize = NSSize(width: 360, height: 120)
    private static let menuBarSampleSize = NSSize(width: 480, height: 160)
    private static let menuBarSamplePixelScale = 2
    private static let animationPixelScale = 3
    private static let framesPerSecond = 24.0
    private static let repeatPause = 1.5

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: ExportReadmeBadgeMedia <docs/assets directory>\n", stderr)
            exit(2)
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let now = Date()
        let usage = try makeUsage(fiveHour: 100, weekly: 100, now: now)
        try writeMenuBarSamples(usage: makeUsage(fiveHour: 53, weekly: 93, now: now), now: now, to: outputDirectory)
        try writeCreditBalanceImage(now: now, to: outputDirectory)
        let transition = UsageBadgeTransition(
            fromFiveHour: 14,
            fromWeekly: 18,
            toFiveHour: 100,
            toWeekly: 100,
            startUptime: 0,
            resetWindows: [.fiveHour, .weekly]
        )

        for style in BadgeStyle.allCases {
            var frames = try resetFrames(style: style, usage: usage, transition: transition, now: now)
            if let finalFrame = frames.last {
                frames.append(GIFFrame(
                    image: finalFrame.image,
                    delay: max(0.1, repeatPause - finalFrame.delay)
                ))
            }
            let filename = style == .doubleRing ? "double-ring" : "large-readout"
            let destination = outputDirectory.appendingPathComponent("badge-reset-\(filename).gif")
            try writeGIF(frames, to: destination)
            print("Wrote \(destination.path)")
        }

        let reminderURL = outputDirectory.appendingPathComponent("reset-expiry-reminder.png")
        try writeReminderImage(usage: makeUsage(fiveHour: 62, weekly: 81, now: now), now: now, to: reminderURL)
        print("Wrote \(reminderURL.path)")
    }

    private static func writeMenuBarSamples(usage: UsageSummary, now: Date, to directory: URL) throws {
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        for style in BadgeStyle.allCases {
            let bitmap = try makeBitmap(size: menuBarSampleSize, pixelScale: menuBarSamplePixelScale)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw ExportError.bitmapContextUnavailable
            }
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.shouldAntialias = true

            appearance.performAsCurrentDrawingAppearance {
                NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1).setFill()
                NSRect(origin: .zero, size: menuBarSampleSize).fill()
                drawCard(
                    in: NSRect(x: 16, y: 14, width: 448, height: 132),
                    fill: .white,
                    border: NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.90, alpha: 1),
                    radius: 18
                )
                drawText("Codex Usage Status", at: NSPoint(x: 32, y: 111), size: 16, weight: .semibold, color: .labelColor)
                drawText(style.menuTitle.uppercased(), at: NSPoint(x: 350, y: 114), size: 10, weight: .medium,
                         color: NSColor(calibratedRed: 0.43, green: 0.36, blue: 0.58, alpha: 1))

                let badgeSurface = NSRect(x: 30, y: 38, width: 420, height: 60)
                drawCard(
                    in: badgeSurface,
                    fill: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.98, alpha: 1),
                    border: NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.93, alpha: 1),
                    radius: 14
                )

                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                rendering.image.draw(
                    in: NSRect(x: 154, y: 44, width: 172, height: 48),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                drawText("Live quota preview", at: NSPoint(x: 32, y: 20), size: 10, weight: .regular, color: .secondaryLabelColor)
            }

            let filename = style == .doubleRing ? "double-ring" : "large-readout"
            let destination = directory.appendingPathComponent("menu-bar-badge-\(filename).png")
            try writePNG(bitmap, to: destination)
            print("Wrote \(destination.path)")
        }
    }

    private static func writeCreditBalanceImage(now: Date, to directory: URL) throws {
        let size = NSSize(width: 760, height: 260)
        let bitmap = try makeBitmap(size: size, pixelScale: 2)
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let usage = try makeUsage(fiveHour: 0, weekly: 68, now: now, purchasedCreditBalance: "218.3286855")
        let tooltipLines = usage.hoverTooltip(
            now: now,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone.current
        ).components(separatedBy: "\n")

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.bitmapContextUnavailable
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true

        appearance.performAsCurrentDrawingAppearance {
            NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            drawText("When your 5-hour quota runs out", at: NSPoint(x: 24, y: 226), size: 18, weight: .semibold, color: .labelColor)
            drawText("A positive purchased balance stays visible in either badge style.",
                     at: NSPoint(x: 24, y: 207), size: 11, weight: .regular, color: .secondaryLabelColor)

            for (index, style) in BadgeStyle.allCases.enumerated() {
                let originX = index == 0 ? 18.0 : 386.0
                drawCard(
                    in: NSRect(x: originX, y: 16, width: 356, height: 174),
                    fill: .white,
                    border: NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.90, alpha: 1),
                    radius: 16
                )
                drawText(style.menuTitle, at: NSPoint(x: originX + 18, y: 170), size: 13, weight: .semibold, color: .labelColor)
                drawText("5H exhausted · purchased credits", at: NSPoint(x: originX + 18, y: 151), size: 10,
                         weight: .medium, color: NSColor(calibratedRed: 0.43, green: 0.36, blue: 0.58, alpha: 1))

                let badgeSurface = NSRect(x: originX + 18, y: 91, width: 320, height: 48)
                drawCard(
                    in: badgeSurface,
                    fill: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.98, alpha: 1),
                    border: NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.93, alpha: 1),
                    radius: 12
                )
                let rendering = UsageBadgeRenderer.rendering(for: usage, style: style, appearance: appearance, now: now)
                let badgeRect = NSRect(x: originX + 92, y: 91, width: 172, height: 48)
                rendering.image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                rendering.warningOverlay?.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                drawText("Hover for balance", at: NSPoint(x: originX + 92, y: 74), size: 9,
                         weight: .medium, color: .secondaryLabelColor)

                let tooltipRect = NSRect(x: originX + 18, y: 27, width: 320, height: 42)
                drawCard(
                    in: tooltipRect,
                    fill: NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.98, alpha: 1),
                    border: .clear,
                    radius: 9
                )
                for (lineIndex, line) in tooltipLines.enumerated() {
                    drawText(line, at: NSPoint(x: tooltipRect.minX + 9, y: tooltipRect.maxY - 12 - CGFloat(lineIndex * 11)),
                             size: 8, weight: .regular, color: .secondaryLabelColor)
                }
            }
        }

        let destination = directory.appendingPathComponent("menu-bar-credit-balance.png")
        try writePNG(bitmap, to: destination)
        print("Wrote \(destination.path)")
    }

    private static func makeUsage(
        fiveHour: Int,
        weekly: Int,
        now: Date,
        purchasedCreditBalance: String? = nil
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: Double(100 - fiveHour),
                    windowDurationMins: 300,
                    resetsAt: now.addingTimeInterval(3_600).timeIntervalSince1970
                ),
                secondary: RateLimitWindow(
                    usedPercent: Double(100 - weekly),
                    windowDurationMins: 10_080,
                    resetsAt: now.addingTimeInterval(7 * 86_400).timeIntervalSince1970
                ),
                planType: "readme-preview",
                credits: purchasedCreditBalance.map {
                    RateLimitCreditsSnapshot(hasCredits: true, unlimited: false, balance: $0)
                }
            ),
            rateLimitsByLimitId: nil,
            accountId: "readme-preview"
        ))
    }

    private static func resetFrames(
        style: BadgeStyle,
        usage: UsageSummary,
        transition: UsageBadgeTransition,
        now: Date
    ) throws -> [GIFFrame] {
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let transitionFrameCount = max(1, Int((transition.duration * framesPerSecond).rounded()))
        var frames: [GIFFrame] = []

        for _ in 0..<6 {
            frames.append(GIFFrame(
                image: try badgeFrame(style: style, usage: usage, appearance: appearance, now: now, animationFrame: transition.frame(at: 0)),
                delay: 1 / framesPerSecond
            ))
        }

        for frameIndex in 1...transitionFrameCount {
            let elapsed = transition.duration * Double(frameIndex) / Double(transitionFrameCount)
            frames.append(GIFFrame(
                image: try badgeFrame(style: style, usage: usage, appearance: appearance, now: now, animationFrame: transition.frame(at: elapsed)),
                delay: 1 / framesPerSecond
            ))
        }

        return frames
    }

    private static func badgeFrame(
        style: BadgeStyle,
        usage: UsageSummary,
        appearance: NSAppearance,
        now: Date,
        animationFrame: UsageBadgeAnimationFrame
    ) throws -> CGImage {
        let bitmap = try makeBitmap(size: canvasSize, pixelScale: animationPixelScale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.bitmapContextUnavailable
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true

        appearance.performAsCurrentDrawingAppearance {
            drawCardBackground()
            drawTitle("Reset confirmed")
            drawSubtitle("Green marks only recovered windows", at: NSPoint(x: 24, y: 57))

            let rendering = UsageBadgeRenderer.rendering(
                for: usage,
                style: style,
                appearance: appearance,
                now: now,
                animationFrame: animationFrame
            )
            let rect = enlargedBadgeRect
            rendering.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if let overlay = rendering.resetOverlay {
                overlay.draw(in: rect, from: .zero, operation: .sourceOver,
                             fraction: rendering.resetOverlayAlpha)
            }
        }

        guard let image = bitmap.cgImage else { throw ExportError.bitmapUnavailable }
        return image
    }

    private static func writeReminderImage(usage: UsageSummary, now: Date, to url: URL) throws {
        let size = NSSize(width: 760, height: 240)
        let bitmap = try makeBitmap(size: size, pixelScale: 2)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.bitmapContextUnavailable
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true

        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            drawText("Reset expiry reminder", at: NSPoint(x: 24, y: 211), size: 18, weight: .semibold, color: .labelColor)
            drawText("A quiet mark appears when an earned reset expires within 72 hours.",
                     at: NSPoint(x: 24, y: 192), size: 11, weight: .regular, color: .secondaryLabelColor)

            for (index, style) in BadgeStyle.allCases.enumerated() {
                let originX = index == 0 ? 18.0 : 386.0
                drawCard(
                    in: NSRect(x: originX, y: 18, width: 356, height: 162),
                    fill: .white,
                    border: NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.90, alpha: 1),
                    radius: 16
                )
                drawText(style.menuTitle, at: NSPoint(x: originX + 18, y: 157), size: 13, weight: .semibold, color: .labelColor)
                drawText("EXPIRING SOON", at: NSPoint(x: originX + 18, y: 138), size: 9, weight: .medium,
                         color: NSColor(calibratedRed: 0.68, green: 0.37, blue: 0.10, alpha: 1))

                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                let badgeRect = NSRect(x: originX + 28, y: 45, width: 258, height: 72)
                rendering.image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                drawExpiryDot(in: badgeRect)
            }
        }

        try writePNG(bitmap, to: url)
    }

    private static func drawCard(in rect: NSRect, fill: NSColor, border: NSColor?, radius: CGFloat) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard let border else { return }
        border.setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        outline.stroke()
    }

    private static func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]).draw(at: point)
    }

    private static func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == bitmap.pixelsWide,
              image.height == bitmap.pixelsHigh else {
            throw ExportError.pngMetadataVerificationFailed
        }
    }

    private static func makeBitmap(size: NSSize, pixelScale: Int = 1) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * pixelScale,
            pixelsHigh: Int(size.height) * pixelScale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.bitmapUnavailable
        }
        bitmap.size = size
        return bitmap
    }

    private static var enlargedBadgeRect: NSRect {
        NSRect(x: 168, y: 25, width: 172, height: 48)
    }

    private static func drawCardBackground() {
        let fullRect = NSRect(origin: .zero, size: canvasSize)
        NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1).setFill()
        fullRect.fill()
        drawCard(
            in: NSRect(x: 12, y: 12, width: 336, height: 96),
            fill: .white,
            border: NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.90, alpha: 1),
            radius: 16
        )
        drawCard(
            in: NSRect(x: 160, y: 21, width: 190, height: 56),
            fill: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.98, alpha: 1),
            border: nil,
            radius: 12
        )
    }

    private static func drawTitle(_ text: String) {
        drawText(text, at: NSPoint(x: 24, y: 78), size: 14, weight: .semibold, color: .labelColor)
    }

    private static func drawSubtitle(_ text: String, at point: NSPoint) {
        drawText(text, at: point, size: 9, weight: .regular, color: .secondaryLabelColor)
    }

    private static func drawExpiryDot(in badgeRect: NSRect) {
        // Mirrors the 4.5 pt dot overlaid by UsageBadgeRenderer.apply on the 90 pt status item.
        let localRect = NSRect(x: 80.5, y: 18.5, width: 4.5, height: 4.5)
        let dotRect = NSRect(
            x: badgeRect.minX + localRect.minX * 3,
            y: badgeRect.minY + localRect.minY * 3,
            width: localRect.width * 3,
            height: localRect.height * 3
        )
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func writeGIF(_ frames: [GIFFrame], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw ExportError.gifDestinationUnavailable
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
            ],
        ] as CFDictionary)

        for frame in frames {
            let frameProperties: CFDictionary = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: frame.delay,
                    kCGImagePropertyGIFUnclampedDelayTime as String: frame.delay,
                ],
            ] as CFDictionary
            CGImageDestinationAddImage(destination, frame.image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.gifEncodingFailed }
        try verifyGIF(at: url)
    }

    private static func verifyGIF(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              (gifProperties[kCGImagePropertyGIFCanvasPixelWidth] as? NSNumber)?.intValue == Int(canvasSize.width) * animationPixelScale,
              (gifProperties[kCGImagePropertyGIFCanvasPixelHeight] as? NSNumber)?.intValue == Int(canvasSize.height) * animationPixelScale,
              (gifProperties[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0 else {
            throw ExportError.gifMetadataVerificationFailed
        }

        var delays: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let frameGIFProperties = frameProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (frameGIFProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (frameGIFProperties?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                ?? 0
            delays.append(delay)
        }
        guard delays.count >= 2,
              delays.filter({ $0 > 1 }).count == 1,
              abs(delays[delays.count - 2] + delays[delays.count - 1] - repeatPause) < 0.01 else {
            throw ExportError.gifPauseVerificationFailed
        }
    }

    private struct GIFFrame {
        let image: CGImage
        let delay: Double
    }

    private enum ExportError: Error {
        case bitmapUnavailable
        case bitmapContextUnavailable
        case pngEncodingFailed
        case gifDestinationUnavailable
        case gifEncodingFailed
        case gifMetadataVerificationFailed
        case gifPauseVerificationFailed
        case pngMetadataVerificationFailed
    }
}
