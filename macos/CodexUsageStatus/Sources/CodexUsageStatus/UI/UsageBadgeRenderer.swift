import AppKit

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

    static func image(for usage: UsageSummary, style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: usage.fiveHour.remainingPercent),
            right: BadgeValue(label: "7D", percent: usage.weekly.remainingPercent),
            appearance: appearance
        )
    }

    static func placeholderImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: nil),
            right: BadgeValue(label: "7D", percent: nil),
            appearance: appearance
        )
    }

    static func errorImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: nil, overrideText: "?"),
            right: BadgeValue(label: "7D", percent: nil, overrideText: "?"),
            appearance: appearance,
            forcedColor: .systemRed
        )
    }

    private static func render(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor? = nil
    ) -> NSImage {
        switch style {
        case .doubleRing:
            return renderDoubleRing(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        case .largeReadout:
            return renderLargeReadout(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        }
    }

    private static func renderDoubleRing(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let imageSize = doubleRingImageSize
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: imageSize)
            NSColor.clear.setFill()
            rect.fill()

            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            divider.fill()

            drawLabeledRing(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 29, y: 12), forcedColor: forcedColor)
            drawLabeledRing(value: right, labelRect: NSRect(x: 50, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 75, y: 12), forcedColor: forcedColor)
        }

        image.isTemplate = false
        return image
    }

    private static func renderLargeReadout(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let imageSize = largeReadoutImageSize
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: imageSize)
            NSColor.clear.setFill()
            rect.fill()

            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.28).setFill()
            divider.fill()

            drawReadoutGroup(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 15, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 1, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
            drawReadoutGroup(value: right, labelRect: NSRect(x: 49, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 61, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 48, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
        }

        image.isTemplate = false
        return image
    }

    private static func drawLabeledRing(
        value: BadgeValue,
        labelRect: NSRect,
        ringCenter: NSPoint,
        forcedColor: NSColor?
    ) {
        drawSideLabel(value.label, in: labelRect)
        drawRing(value: value, center: ringCenter, forcedColor: forcedColor)
    }

    private static func drawRing(value: BadgeValue, center: NSPoint, forcedColor: NSColor?) {
        let radius: CGFloat = 9.7
        let lineWidth: CGFloat = 2.25
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.20).setStroke()
        track.stroke()

        if let percent = value.percent {
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
            (forcedColor ?? color(for: progress)).withAlphaComponent(0.92).setStroke()
            ring.stroke()
        }

        drawText(value.centerText, center: center, yOffset: -5.5, fontSize: value.centerText.count >= 3 ? 7.4 : 9.0, weight: .bold, alpha: 0.98)
    }

    private static func drawReadoutGroup(
        value: BadgeValue,
        labelRect: NSRect,
        numberRect: NSRect,
        lineRect: NSRect,
        forcedColor: NSColor?
    ) {
        let percent = value.percent.map { max(0, min(100, $0)) }
        let accent = forcedColor ?? percent.map(color(for:)) ?? NSColor.labelColor.withAlphaComponent(0.26)
        let emphasisAlpha: CGFloat = (percent ?? 100) < 20 ? 1.0 : 0.96

        drawStackedLabel(value.label, in: labelRect, alpha: 0.62)
        drawString(value.centerText, in: numberRect, fontSize: value.centerText.count >= 3 ? 11.6 : 13.2, weight: .bold, alpha: emphasisAlpha, alignment: .left)

        let track = NSBezierPath(roundedRect: lineRect, xRadius: 0.7, yRadius: 0.7)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        track.fill()

        if let percent {
            let fillWidth = max(1.2, lineRect.width * CGFloat(percent) / 100)
            let fillRect = NSRect(x: lineRect.minX, y: lineRect.minY, width: fillWidth, height: lineRect.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 0.7, yRadius: 0.7)
            accent.withAlphaComponent(percent < 20 ? 0.95 : 0.72).setFill()
            fillPath.fill()
        }
    }

    private static func drawText(
        _ text: String,
        center: NSPoint,
        yOffset: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: centeredParagraphStyle,
        ]
        let height = fontSize + 2
        let rect = NSRect(x: center.x - 10, y: center.y + yOffset, width: 20, height: height)
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func drawSideLabel(_ text: String, in rect: NSRect) {
        drawStackedLabel(text, in: rect, alpha: 0.78)
    }

    private static func drawStackedLabel(_ text: String, in rect: NSRect, alpha: CGFloat) {
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
            drawString(line, in: lineRect, fontSize: fontSize, weight: .bold, alpha: alpha, alignment: .center)
        }
    }

    private static func drawString(
        _ text: String,
        in rect: NSRect,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        alignment: NSTextAlignment
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    private static func color(for percent: Int) -> NSColor {
        percent < 20 ? .systemRed : .labelColor
    }
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
