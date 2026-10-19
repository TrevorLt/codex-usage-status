import AppKit

struct UsageBadgeRendering {
    /// The complete neutral badge as a template image. AppKit supplies its menu-bar tint.
    let image: NSImage

    /// Red warning marks for windows below 20%, drawn above the template image.
    let warningOverlay: NSImage?
}

enum UsageBadgeRenderer {
    private static let doubleRingImageSize = NSSize(width: 86, height: 24)
    private static let largeReadoutImageSize = NSSize(width: 86, height: 24)

    static func statusItemLength(for style: BadgeStyle) -> CGFloat {
        switch style {
        case .doubleRing:
            return 90
        case .largeReadout:
            return 90
        }
    }

    static func rendering(
        for usage: UsageSummary,
        style: BadgeStyle,
        appearance: NSAppearance,
        isStale: Bool = false,
        now: Date = Date(),
        hideReadings: Bool = false
    ) -> UsageBadgeRendering {
        render(
            style: style,
            left: BadgeValue(label: "5H", percent: hideReadings || usage.fiveHour.isExpired(at: now) ? nil : usage.fiveHour.remainingPercent),
            right: BadgeValue(label: "7D", percent: hideReadings || usage.weekly.isExpired(at: now) ? nil : usage.weekly.remainingPercent),
            appearance: appearance,
            isStale: isStale
        )
    }

    /// Legacy single-image callers receive the native template base, including during warnings.
    /// Use `rendering(for:style:appearance:isStale:now:hideReadings:)` with `apply(_:to:)`
    /// when the red warning overlay must also be displayed.
    static func image(
        for usage: UsageSummary,
        style: BadgeStyle,
        appearance: NSAppearance,
        isStale: Bool = false,
        now: Date = Date(),
        hideReadings: Bool = false
    ) -> NSImage {
        rendering(for: usage, style: style, appearance: appearance, isStale: isStale, now: now, hideReadings: hideReadings).image
    }

    static func placeholderImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(
            style: style,
            left: BadgeValue(label: "5H", percent: nil),
            right: BadgeValue(label: "7D", percent: nil),
            appearance: appearance
        ).image
    }

    static func errorImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(
            style: style,
            left: BadgeValue(label: "5H", percent: nil, overrideText: "?"),
            right: BadgeValue(label: "7D", percent: nil, overrideText: "?"),
            appearance: appearance,
            forcedColor: .systemRed
        ).image
    }

    /// Installs the template image as the button image and positions the optional red overlay
    /// over the exact image rect, so neutral marks retain AppKit's native template tinting.
    @MainActor
    static func apply(_ rendering: UsageBadgeRendering, to button: NSButton) {
        button.image = rendering.image
        let overlayView = button.subviews.compactMap { $0 as? BadgeWarningOverlayView }.first

        guard let warningOverlay = rendering.warningOverlay else {
            overlayView?.removeFromSuperview()
            return
        }

        let warningView = overlayView ?? BadgeWarningOverlayView(frame: .zero)
        if overlayView == nil {
            button.addSubview(warningView, positioned: .above, relativeTo: nil)
        }
        warningView.warningImage = warningOverlay
        warningView.frame = button.cell?.imageRect(forBounds: button.bounds)
            ?? centeredImageRect(for: rendering.image, in: button.bounds)
    }

    @MainActor
    static func apply(image: NSImage, to button: NSButton) {
        apply(UsageBadgeRendering(image: image, warningOverlay: nil), to: button)
    }

    private static func centeredImageRect(for image: NSImage, in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.midX - image.size.width / 2,
            y: bounds.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
    }

    private static func render(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor? = nil,
        isStale: Bool = false
    ) -> UsageBadgeRendering {
        let image = renderLayer(
            style: style,
            left: left,
            right: right,
            appearance: appearance,
            forcedColor: forcedColor,
            isStale: isStale,
            warningOverlay: false
        )
        let overlay = forcedColor == nil && containsWarning(left: left, right: right)
            ? renderLayer(
                style: style,
                left: left,
                right: right,
                appearance: appearance,
                isStale: isStale,
                warningOverlay: true
            )
            : nil

        return UsageBadgeRendering(image: image, warningOverlay: overlay)
    }

    private static func containsWarning(left: BadgeValue, right: BadgeValue) -> Bool {
        [left.percent, right.percent].compactMap { $0 }.contains { $0 < 20 }
    }

    private static func renderLayer(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor? = nil,
        isStale: Bool,
        warningOverlay: Bool
    ) -> NSImage {
        let foregroundColor = warningOverlay
            ? NSColor.systemRed
            : (forcedColor == nil ? NSColor.black : NSColor.labelColor)

        switch style {
        case .doubleRing:
            return renderDoubleRing(
                left: left,
                right: right,
                appearance: appearance,
                forcedColor: forcedColor,
                foregroundColor: foregroundColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
        case .largeReadout:
            return renderLargeReadout(
                left: left,
                right: right,
                appearance: appearance,
                forcedColor: forcedColor,
                foregroundColor: foregroundColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
        }
    }

    private static func renderDoubleRing(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?,
        foregroundColor: NSColor,
        isStale: Bool,
        warningOverlay: Bool
    ) -> NSImage {
        let image = NSImage(size: doubleRingImageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: doubleRingImageSize)
            NSColor.clear.setFill()
            rect.fill()

            if !warningOverlay {
                drawDivider(foregroundColor: foregroundColor)
            }

            drawLabeledRing(
                value: left,
                labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16),
                ringCenter: NSPoint(x: 29, y: 12),
                foregroundColor: foregroundColor,
                forcedColor: forcedColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
            drawLabeledRing(
                value: right,
                labelRect: NSRect(x: 50, y: 4.0, width: 11, height: 16),
                ringCenter: NSPoint(x: 75, y: 12),
                foregroundColor: foregroundColor,
                forcedColor: forcedColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
        }

        image.isTemplate = !warningOverlay && forcedColor == nil
        return image
    }

    private static func renderLargeReadout(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?,
        foregroundColor: NSColor,
        isStale: Bool,
        warningOverlay: Bool
    ) -> NSImage {
        let image = NSImage(size: largeReadoutImageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: largeReadoutImageSize)
            NSColor.clear.setFill()
            rect.fill()

            if !warningOverlay {
                drawDivider(foregroundColor: foregroundColor)
            }

            drawReadoutGroup(
                value: left,
                labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16),
                numberRect: NSRect(x: 15, y: 3.4, width: 25, height: 17),
                lineRect: NSRect(x: 1, y: 2.4, width: 36, height: 1.5),
                foregroundColor: foregroundColor,
                forcedColor: forcedColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
            drawReadoutGroup(
                value: right,
                labelRect: NSRect(x: 49, y: 4.0, width: 11, height: 16),
                numberRect: NSRect(x: 61, y: 3.4, width: 25, height: 17),
                lineRect: NSRect(x: 48, y: 2.4, width: 36, height: 1.5),
                foregroundColor: foregroundColor,
                forcedColor: forcedColor,
                isStale: isStale,
                warningOverlay: warningOverlay
            )
        }

        image.isTemplate = !warningOverlay && forcedColor == nil
        return image
    }

    private static func drawDivider(foregroundColor: NSColor) {
        let divider = NSBezierPath()
        divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1, startAngle: 0, endAngle: 360)
        foregroundColor.withAlphaComponent(0.25).setFill()
        divider.fill()
    }

    private static func drawLabeledRing(
        value: BadgeValue,
        labelRect: NSRect,
        ringCenter: NSPoint,
        foregroundColor: NSColor,
        forcedColor: NSColor?,
        isStale: Bool,
        warningOverlay: Bool
    ) {
        if warningOverlay {
            guard let percent = value.percent, percent < 20 else { return }
            drawWarningArc(percent: percent, center: ringCenter, color: .systemRed)
            return
        }

        drawSideLabel(value.label, in: labelRect, foregroundColor: foregroundColor)
        drawRing(
            value: value,
            center: ringCenter,
            foregroundColor: foregroundColor,
            forcedColor: forcedColor,
            suppressWarningContent: forcedColor == nil,
            isStale: isStale
        )
    }

    private static func drawRing(
        value: BadgeValue,
        center: NSPoint,
        foregroundColor: NSColor,
        forcedColor: NSColor?,
        suppressWarningContent: Bool,
        isStale: Bool
    ) {
        let radius: CGFloat = 9.7
        let lineWidth: CGFloat = 2.25
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        foregroundColor.withAlphaComponent(0.20).setStroke()
        track.stroke()

        let isWarning = suppressWarningContent && (value.percent.map { $0 < 20 } ?? false)
        if let percent = value.percent, !isWarning {
            let progress = max(0, min(100, percent))
            let ring = NSBezierPath()
            ring.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(progress) * 3.6,
                clockwise: true
            )
            ring.lineWidth = lineWidth
            ring.lineCapStyle = .round
            (forcedColor ?? color(for: progress, foregroundColor: foregroundColor)).withAlphaComponent(0.92).setStroke()
            ring.stroke()
        }

        drawText(
            readingText(for: value, isStale: isStale),
            center: center,
            yOffset: -5.5,
            fontSize: ringFontSize(for: value, isStale: isStale),
            weight: .bold,
            alpha: 0.98,
            foregroundColor: foregroundColor
        )
    }

    private static func drawWarningArc(percent: Int, center: NSPoint, color: NSColor) {
        // A zero-length progress arc would hide the warning entirely. At 0%, use
        // a complete red ring while leaving the percentage text in the template layer.
        let visiblePercent = percent == 0 ? 100 : max(0, min(100, percent))
        guard visiblePercent > 0 else { return }
        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: 9.7,
            startAngle: 90,
            endAngle: 90 - CGFloat(visiblePercent) * 3.6,
            clockwise: true
        )
        ring.lineWidth = 2.25
        ring.lineCapStyle = .round
        color.withAlphaComponent(0.95).setStroke()
        ring.stroke()
    }

    private static func drawReadoutGroup(
        value: BadgeValue,
        labelRect: NSRect,
        numberRect: NSRect,
        lineRect: NSRect,
        foregroundColor: NSColor,
        forcedColor: NSColor?,
        isStale: Bool,
        warningOverlay: Bool
    ) {
        let percent = value.percent.map { max(0, min(100, $0)) }
        let isWarning = forcedColor == nil && (percent.map { $0 < 20 } ?? false)

        if warningOverlay {
            guard isWarning, let percent else { return }
            drawReadoutFill(percent: percent, lineRect: lineRect, color: .systemRed, alpha: 0.95)
            return
        }

        drawStackedLabel(value.label, in: labelRect, alpha: 0.62, foregroundColor: foregroundColor)
        drawString(
            readingText(for: value, isStale: isStale),
            in: numberRect,
            fontSize: readoutFontSize(for: value, isStale: isStale),
            weight: .bold,
            alpha: 0.96,
            alignment: .left,
            foregroundColor: foregroundColor
        )

        let track = NSBezierPath(roundedRect: lineRect, xRadius: 0.7, yRadius: 0.7)
        foregroundColor.withAlphaComponent(0.14).setFill()
        track.fill()

        if let percent, !isWarning {
            let accent = forcedColor ?? color(for: percent, foregroundColor: foregroundColor)
            drawReadoutFill(percent: percent, lineRect: lineRect, color: accent, alpha: 0.72)
        }
    }

    private static func drawReadoutFill(percent: Int, lineRect: NSRect, color: NSColor, alpha: CGFloat) {
        let fillWidth = max(1.2, lineRect.width * CGFloat(percent) / 100)
        let fillRect = NSRect(x: lineRect.minX, y: lineRect.minY, width: fillWidth, height: lineRect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 0.7, yRadius: 0.7)
        color.withAlphaComponent(alpha).setFill()
        fillPath.fill()
    }

    private static func drawText(
        _ text: String,
        center: NSPoint,
        yOffset: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        foregroundColor: NSColor
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor.withAlphaComponent(alpha),
            .paragraphStyle: centeredParagraphStyle,
        ]
        let height = fontSize + 2
        let rect = NSRect(x: center.x - 10, y: center.y + yOffset, width: 20, height: height)
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func drawSideLabel(_ text: String, in rect: NSRect, foregroundColor: NSColor) {
        drawStackedLabel(text, in: rect, alpha: 0.78, foregroundColor: foregroundColor)
    }

    private static func drawStackedLabel(_ text: String, in rect: NSRect, alpha: CGFloat, foregroundColor: NSColor) {
        let lines: [String]
        let normalized = text.uppercased()
        if normalized.count == 2 {
            lines = normalized.map(String.init)
        } else {
            lines = [normalized]
        }

        let fontSize: CGFloat = lines.count > 1 ? 7.4 : 10.0
        let lineHeight: CGFloat = lines.count > 1 ? 7.5 : 10.8
        let totalHeight = CGFloat(lines.count) * lineHeight
        let startY = rect.midY + totalHeight / 2 - lineHeight

        for (index, line) in lines.enumerated() {
            let lineRect = NSRect(
                x: rect.minX,
                y: startY - CGFloat(index) * lineHeight,
                width: rect.width,
                height: lineHeight
            )
            drawString(line, in: lineRect, fontSize: fontSize, weight: .bold, alpha: alpha, alignment: .center, foregroundColor: foregroundColor)
        }
    }

    private static func drawString(
        _ text: String,
        in rect: NSRect,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        alignment: NSTextAlignment,
        foregroundColor: NSColor
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: foregroundColor.withAlphaComponent(alpha),
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func readingText(for value: BadgeValue, isStale: Bool) -> String {
        guard isStale, value.percent != nil, value.overrideText == nil else {
            return value.centerText
        }
        return "~\(value.centerText)"
    }

    private static func ringFontSize(for value: BadgeValue, isStale: Bool) -> CGFloat {
        guard isStale, value.percent != nil, value.overrideText == nil else {
            return value.centerText.count >= 3 ? 7.4 : 9.0
        }
        return value.centerText.count >= 3 ? 6.7 : 7.8
    }

    private static func readoutFontSize(for value: BadgeValue, isStale: Bool) -> CGFloat {
        guard isStale, value.percent != nil, value.overrideText == nil else {
            return value.centerText.count >= 3 ? 11.6 : 13.2
        }
        return value.centerText.count >= 3 ? 9.8 : 10.8
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    private static var neutralColor: NSColor { NSColor.labelColor }

    private static func color(for percent: Int, foregroundColor: NSColor) -> NSColor {
        percent < 20 ? .systemRed : foregroundColor
    }
}

private final class BadgeWarningOverlayView: NSView {
    var warningImage: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        warningImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BadgeValue {
    let label: String
    let percent: Int?
    let overrideText: String?

    init(label: String, percent: Int?, overrideText: String? = nil) {
        self.label = label
        self.percent = percent
        self.overrideText = overrideText
    }

    var centerText: String {
        if let overrideText {
            return overrideText
        }
        guard let percent else {
            return "--"
        }
        return "\(percent)"
    }
}
