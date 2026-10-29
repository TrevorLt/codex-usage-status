import AppKit

struct UsageBadgeRendering {
    /// The complete neutral badge as a template image. AppKit supplies its menu-bar tint.
    let image: NSImage

    /// Red warning marks for windows below 20%, drawn above the template image.
    let warningOverlay: NSImage?

    /// Apple-green progress overlay, shown only after a reset is confirmed by a fresh read.
    let resetOverlay: NSImage?
    let resetOverlayAlpha: CGFloat

    /// A static amber mark for a confirmed reset credit expiring soon.
    let expiryReminder: Bool

    init(
        image: NSImage,
        warningOverlay: NSImage? = nil,
        resetOverlay: NSImage? = nil,
        resetOverlayAlpha: CGFloat = 0,
        expiryReminder: Bool = false
    ) {
        self.image = image
        self.warningOverlay = warningOverlay
        self.resetOverlay = resetOverlay
        self.resetOverlayAlpha = resetOverlayAlpha
        self.expiryReminder = expiryReminder
    }
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
        staleWindows: Set<UsageWindowKind>? = nil,
        now: Date = Date(),
        hideReadings: Bool = false,
        showExpiryReminder: Bool = false,
        animationFrame: UsageBadgeAnimationFrame? = nil
    ) -> UsageBadgeRendering {
        let staleKinds = staleWindows ?? (isStale ? [.fiveHour, .weekly] : [])
        let creditBalanceText = animationFrame == nil
            ? creditBalanceBadgeText(for: usage, now: now, hideReadings: hideReadings)
            : nil
        return render(
            style: style,
            left: BadgeValue(
                label: creditBalanceText == nil ? "5H" : "C",
                percent: hideReadings || usage.fiveHour.isExpired(at: now) ? nil : usage.fiveHour.remainingPercent,
                overrideText: creditBalanceText,
                displayedPercent: hideReadings || usage.fiveHour.isExpired(at: now) ? nil : animationFrame?.fiveHourPercent,
                isStale: staleKinds.contains(.fiveHour)
            ),
            right: BadgeValue(
                label: "7D",
                percent: hideReadings || usage.weekly.isExpired(at: now) ? nil : usage.weekly.remainingPercent,
                displayedPercent: hideReadings || usage.weekly.isExpired(at: now) ? nil : animationFrame?.weeklyPercent,
                isStale: staleKinds.contains(.weekly)
            ),
            appearance: appearance,
            resetWindows: animationFrame?.resetWindows ?? [],
            resetOverlayAlpha: animationFrame?.resetHighlightAlpha ?? 0,
            showExpiryReminder: showExpiryReminder
        )
    }

    static func creditBalanceBadgeText(for usage: UsageSummary, now: Date, hideReadings: Bool = false) -> String? {
        guard !hideReadings,
              usage.fiveHour.remainingPercent == 0,
              !usage.fiveHour.isExpired(at: now),
              let credits = usage.credits else {
            return nil
        }

        if credits.unlimited { return "∞" }
        guard credits.hasCredits else { return nil }
        guard let balance = credits.decimalBalance else { return "?" }
        guard balance > 0 else { return nil }

        var unrounded = balance
        var rounded = Decimal()
        NSDecimalRound(&rounded, &unrounded, 0, .plain)
        guard rounded > 0 else { return "<1" }
        return compactCreditCount(NSDecimalNumber(decimal: rounded).stringValue)
    }

    private static func compactCreditCount(_ digits: String) -> String {
        guard digits.count > 4 else { return digits }
        let units = ["", "K", "M", "B", "T", "P", "E", "Z", "Y"]
        let group = (digits.count - 1) / 3
        guard group < units.count else { return "\(digits.first ?? "0")e\(digits.count - 1)" }

        let leadingCount = digits.count - group * 3
        let leading = String(digits.prefix(leadingCount))
        let firstFraction = digits.dropFirst(leadingCount).first ?? "0"
        let suffix = units[group]
        if leadingCount == 1, firstFraction != "0" {
            return "\(leading).\(firstFraction)\(suffix)"
        }
        return "\(leading)\(suffix)"
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
        hideReadings: Bool = false,
        showExpiryReminder: Bool = false
    ) -> NSImage {
        rendering(
            for: usage,
            style: style,
            appearance: appearance,
            isStale: isStale,
            now: now,
            hideReadings: hideReadings,
            showExpiryReminder: showExpiryReminder
        ).image
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

    /// Installs the template base and keeps colored overlays aligned to its exact image rect.
    @MainActor
    static func apply(_ rendering: UsageBadgeRendering, to button: NSButton) {
        button.image = rendering.image
        let imageRect = button.cell?.imageRect(forBounds: button.bounds)
            ?? centeredImageRect(for: rendering.image, in: button.bounds)
        let warningView = button.subviews.compactMap { $0 as? BadgeWarningOverlayView }.first
        if let warningOverlay = rendering.warningOverlay {
            let view = warningView ?? BadgeWarningOverlayView(frame: .zero)
            if warningView == nil { button.addSubview(view, positioned: .above, relativeTo: nil) }
            view.warningImage = warningOverlay
            view.frame = imageRect
        } else {
            warningView?.removeFromSuperview()
        }

        let resetView = button.subviews.compactMap { $0 as? BadgeResetOverlayView }.first
        if let resetOverlay = rendering.resetOverlay, rendering.resetOverlayAlpha > 0 {
            let view = resetView ?? BadgeResetOverlayView(frame: .zero)
            if resetView == nil { button.addSubview(view, positioned: .above, relativeTo: warningView) }
            view.overlayImage = resetOverlay
            view.overlayAlpha = rendering.resetOverlayAlpha
            view.frame = imageRect
        } else {
            resetView?.removeFromSuperview()
        }
        applyExpiryReminder(rendering.expiryReminder, to: button)
    }

    @MainActor
    static func apply(image: NSImage, to button: NSButton) {
        apply(UsageBadgeRendering(image: image, warningOverlay: nil, expiryReminder: false), to: button)
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
        isStale: Bool = false,
        resetWindows: Set<UsageWindowKind> = [],
        resetOverlayAlpha: Double = 0,
        showExpiryReminder: Bool = false
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
        let resetOverlay = forcedColor == nil && !resetWindows.isEmpty
            ? renderResetOverlay(style: style, left: left, right: right, appearance: appearance, resetWindows: resetWindows)
            : nil

        return UsageBadgeRendering(
            image: image,
            warningOverlay: overlay,
            resetOverlay: resetOverlay,
            resetOverlayAlpha: CGFloat(max(0, min(1, resetOverlayAlpha))),
            expiryReminder: showExpiryReminder && forcedColor == nil
        )
    }

    @MainActor
    private static func applyExpiryReminder(_ show: Bool, to button: NSButton) {
        let existing = button.subviews.compactMap { $0 as? BadgeExpiryReminderDotView }.first
        guard show else {
            existing?.removeFromSuperview()
            return
        }

        let dot = existing ?? BadgeExpiryReminderDotView(frame: .zero)
        if existing == nil {
            button.addSubview(dot, positioned: .above, relativeTo: nil)
        }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds)
            ?? NSRect(x: 2, y: 0, width: 86, height: 24)
        dot.frame = NSRect(x: imageRect.maxX - 5.5, y: imageRect.maxY - 5.5, width: 4.5, height: 4.5)
    }

    private static func containsWarning(left: BadgeValue, right: BadgeValue) -> Bool {
        [left.progressPercent, right.progressPercent].compactMap { $0 }.contains { $0 < 20 }
    }

    private static func renderResetOverlay(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        resetWindows: Set<UsageWindowKind>
    ) -> NSImage {
        let size = style == .doubleRing ? doubleRingImageSize : largeReadoutImageSize
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()
            switch style {
            case .doubleRing:
                if resetWindows.contains(.fiveHour) {
                    drawResetRing(percent: left.progressPercent, center: NSPoint(x: 29, y: 12))
                }
                if resetWindows.contains(.weekly) {
                    drawResetRing(percent: right.progressPercent, center: NSPoint(x: 75, y: 12))
                }
            case .largeReadout:
                if resetWindows.contains(.fiveHour), let percent = left.progressPercent {
                    drawReadoutFill(percent: percent, lineRect: NSRect(x: 1, y: 2.4, width: 36, height: 1.5), color: .systemGreen, alpha: 1)
                }
                if resetWindows.contains(.weekly), let percent = right.progressPercent {
                    drawReadoutFill(percent: percent, lineRect: NSRect(x: 48, y: 2.4, width: 36, height: 1.5), color: .systemGreen, alpha: 1)
                }
            }
        }

        image.isTemplate = false
        return image
    }

    private static func drawResetRing(percent: Double?, center: NSPoint) {
        guard let percent else { return }
        let progress = max(0, min(100, percent))
        guard progress > 0 else { return }
        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: 9.7,
            startAngle: 90,
            endAngle: 90 - CGFloat(progress) * 3.6,
            clockwise: true
        )
        ring.lineWidth = 2.25
        ring.lineCapStyle = .round
        NSColor.systemGreen.setStroke()
        ring.stroke()
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
            guard let percent = value.progressPercent, percent < 20 else { return }
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

        let isWarning = suppressWarningContent && (value.progressPercent.map { $0 < 20 } ?? false)
        if let percent = value.progressPercent, !isWarning {
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
            value.centerText,
            center: center,
            yOffset: -5.5,
            fontSize: ringFontSize(for: value),
            weight: .bold,
            alpha: 0.98,
            foregroundColor: foregroundColor
        )
        if value.isStale { drawRingStaleMarker(near: center, foregroundColor: foregroundColor) }
    }

    private static func drawWarningArc(percent: Double, center: NSPoint, color: NSColor) {
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
        let percent = value.progressPercent.map { max(0, min(100, $0)) }
        let isWarning = forcedColor == nil && (percent.map { $0 < 20 } ?? false)

        if warningOverlay {
            guard isWarning, let percent else { return }
            drawReadoutFill(percent: percent, lineRect: lineRect, color: .systemRed, alpha: 0.95)
            return
        }

        drawStackedLabel(value.label, in: labelRect, alpha: 0.62, foregroundColor: foregroundColor)
        drawString(
            value.centerText,
            in: numberRect,
            fontSize: readoutFontSize(for: value),
            weight: .bold,
            alpha: 0.96,
            alignment: .left,
            foregroundColor: foregroundColor
        )
        if value.isStale { drawReadoutStaleMarker(in: numberRect, foregroundColor: foregroundColor) }

        let track = NSBezierPath(roundedRect: lineRect, xRadius: 0.7, yRadius: 0.7)
        foregroundColor.withAlphaComponent(0.14).setFill()
        track.fill()

        if let percent, !isWarning {
            let accent = forcedColor ?? color(for: percent, foregroundColor: foregroundColor)
            drawReadoutFill(percent: percent, lineRect: lineRect, color: accent, alpha: 0.72)
        }
    }

    private static func drawReadoutFill(percent: Double, lineRect: NSRect, color: NSColor, alpha: CGFloat) {
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

    private static func ringFontSize(for value: BadgeValue) -> CGFloat {
        value.centerText.count >= 3 ? 7.4 : 9.0
    }

    private static func readoutFontSize(for value: BadgeValue) -> CGFloat {
        value.centerText.count >= 4 ? 8.8 : (value.centerText.count >= 3 ? 11.6 : 13.2)
    }

    private static func drawRingStaleMarker(near center: NSPoint, foregroundColor: NSColor) {
        drawString("~", in: NSRect(x: center.x - 10.5, y: center.y + 5.2, width: 4.5, height: 6),
                   fontSize: 5.0, weight: .medium, alpha: 0.62, alignment: .center, foregroundColor: foregroundColor)
    }

    private static func drawReadoutStaleMarker(in numberRect: NSRect, foregroundColor: NSColor) {
        drawString("~", in: NSRect(x: numberRect.minX - 3.1, y: numberRect.maxY - 5.8, width: 3.0, height: 6),
                   fontSize: 5.0, weight: .medium, alpha: 0.62, alignment: .center, foregroundColor: foregroundColor)
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    private static var neutralColor: NSColor { NSColor.labelColor }

    private static func color(for percent: Double, foregroundColor: NSColor) -> NSColor {
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

@MainActor
private final class BadgeResetOverlayView: NSView {
    var overlayImage: NSImage? {
        didSet { needsDisplay = true }
    }
    var overlayAlpha: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        overlayImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: overlayAlpha)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class BadgeExpiryReminderDotView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.96, green: 0.63, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.35, dy: 0.35)).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BadgeValue {
    let label: String
    let percent: Int?
    let overrideText: String?
    let displayedPercent: Double?
    let isStale: Bool

    init(label: String, percent: Int?, overrideText: String? = nil, displayedPercent: Double? = nil, isStale: Bool = false) {
        self.label = label
        self.percent = percent
        self.overrideText = overrideText
        self.displayedPercent = displayedPercent
        self.isStale = isStale
    }

    var progressPercent: Double? {
        displayedPercent ?? percent.map(Double.init)
    }

    var centerText: String {
        if let overrideText {
            return overrideText
        }
        guard let progressPercent else {
            return "--"
        }
        return "\(Int(progressPercent.rounded()))"
    }
}
