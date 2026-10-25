import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
@main
private enum ExportReadmeBadgeMedia {
    private static let canvasSize = NSSize(width: 300, height: 100)
    private static let menuBarSampleSize = NSSize(width: 213, height: 67)
    private static let animationPixelScale = 2
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
            let bitmap = try makeBitmap(size: menuBarSampleSize)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw ExportError.bitmapContextUnavailable
            }
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.shouldAntialias = true

            appearance.performAsCurrentDrawingAppearance {
                let bounds = NSRect(origin: .zero, size: menuBarSampleSize)
                NSGradient(colors: [
                    NSColor(calibratedRed: 1, green: 0.89, blue: 0.29, alpha: 1),
                    NSColor(calibratedRed: 1, green: 0.82, blue: 0.22, alpha: 1),
                ])?.draw(in: bounds, angle: 270)

                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                rendering.image.draw(
                    in: NSRect(x: 21, y: 9.5, width: 172, height: 48),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }

            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw ExportError.pngEncodingFailed
            }
            let filename = style == .doubleRing ? "double-ring" : "large-readout"
            let destination = directory.appendingPathComponent("menu-bar-badge-\(filename).png")
            try data.write(to: destination, options: .atomic)
            print("Wrote \(destination.path)")
        }
    }

    private static func makeUsage(fiveHour: Int, weekly: Int, now: Date) throws -> UsageSummary {
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
                planType: "readme-preview"
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
        let size = NSSize(width: 620, height: 180)
        let bitmap = try makeBitmap(size: size)
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
            let fullRect = NSRect(origin: .zero, size: size)
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            NSBezierPath(roundedRect: fullRect, xRadius: 16, yRadius: 16).fill()
            NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
            let border = NSBezierPath(roundedRect: fullRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
            border.lineWidth = 1
            border.stroke()

            NSAttributedString(
                string: "Reset expires soon",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]
            ).draw(at: NSPoint(x: 24, y: 142))

            for (index, style) in BadgeStyle.allCases.enumerated() {
                let originX = index == 0 ? 24.0 : 324.0
                NSAttributedString(
                    string: style.menuTitle,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                ).draw(at: NSPoint(x: originX, y: 112))

                let rendering = UsageBadgeRenderer.rendering(
                    for: usage,
                    style: style,
                    appearance: appearance,
                    now: now
                )
                let badgeRect = NSRect(x: originX, y: 38, width: 258, height: 72)
                rendering.image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                drawExpiryDot(in: badgeRect)
            }
        }

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
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
        NSRect(x: 64, y: 18, width: 172, height: 48)
    }

    private static func drawCardBackground() {
        let fullRect = NSRect(origin: .zero, size: canvasSize)
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: fullRect, xRadius: 16, yRadius: 16).fill()
        NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: fullRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        border.lineWidth = 1
        border.stroke()
    }

    private static func drawTitle(_ text: String) {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        ).draw(at: NSPoint(x: 18, y: 78))
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
    }
}
