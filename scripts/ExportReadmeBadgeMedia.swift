import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
@main
private enum ExportReadmeBadgeMedia {
    private static let canvasSize = NSSize(width: 220, height: 72)
    private static let menuBarSampleSize = NSSize(width: 300, height: 100)
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
                drawBackdrop(in: menuBarSampleSize)

                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                rendering.image.draw(
                    in: centeredBadgeRect(in: menuBarSampleSize, width: 172, height: 48),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }

            let filename = style == .doubleRing ? "double-ring" : "large-readout"
            let destination = directory.appendingPathComponent("menu-bar-badge-\(filename).png")
            try writePNG(bitmap, to: destination)
            print("Wrote \(destination.path)")
        }
    }

    private static func writeCreditBalanceImage(now: Date, to directory: URL) throws {
        let size = NSSize(width: 760, height: 160)
        let bitmap = try makeBitmap(size: size, pixelScale: 2)
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let usage = try makeUsage(fiveHour: 0, weekly: 68, now: now, purchasedCreditBalance: "218.3286855")

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.bitmapContextUnavailable
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true

        appearance.performAsCurrentDrawingAppearance {
            drawBackdrop(in: size)

            for (index, style) in BadgeStyle.allCases.enumerated() {
                let rendering = UsageBadgeRenderer.rendering(for: usage, style: style, appearance: appearance, now: now)
                let columnWidth = size.width / CGFloat(BadgeStyle.allCases.count)
                let badgeRect = NSRect(
                    x: columnWidth * CGFloat(index) + (columnWidth - 172) / 2,
                    y: (size.height - 48) / 2,
                    width: 172,
                    height: 48
                )
                rendering.image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                rendering.warningOverlay?.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
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
            drawBackdrop(in: canvasSize)

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
        let size = NSSize(width: 760, height: 160)
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
            drawBackdrop(in: size)

            for (index, style) in BadgeStyle.allCases.enumerated() {
                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                let columnWidth = size.width / CGFloat(BadgeStyle.allCases.count)
                let badgeRect = NSRect(
                    x: columnWidth * CGFloat(index) + (columnWidth - 258) / 2,
                    y: (size.height - 72) / 2,
                    width: 258,
                    height: 72
                )
                rendering.image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                drawExpiryDot(in: badgeRect, scale: 3)
            }
        }

        try writePNG(bitmap, to: url)
    }

    private static func drawBackdrop(in size: NSSize) {
        NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
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

    private static func centeredBadgeRect(in size: NSSize, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private static var enlargedBadgeRect: NSRect {
        centeredBadgeRect(in: canvasSize, width: 172, height: 48)
    }

    private static func drawExpiryDot(in badgeRect: NSRect, scale: CGFloat) {
        // Mirrors the 4.5 pt dot overlaid by UsageBadgeRenderer.apply on the 90 pt status item.
        let localRect = NSRect(x: 80.5, y: 18.5, width: 4.5, height: 4.5)
        let dotRect = NSRect(
            x: badgeRect.minX + localRect.minX * scale,
            y: badgeRect.minY + localRect.minY * scale,
            width: localRect.width * scale,
            height: localRect.height * scale
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
