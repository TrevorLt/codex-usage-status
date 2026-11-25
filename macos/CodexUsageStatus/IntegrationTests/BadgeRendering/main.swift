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

        let purchasedCreditResponse = try JSONDecoder().decode(RateLimitsResponse.self, from: Data("""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":\(now.timeIntervalSince1970 + 3_600)},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":\(now.timeIntervalSince1970 + 86_400)},"credits":{"hasCredits":true,"unlimited":false,"balance":"218.3286855000"}},"rateLimitResetCredits":{"availableCount":0,"credits":null}}
        """.utf8))
        let purchasedCreditUsage = try UsageSummary(response: purchasedCreditResponse)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: purchasedCreditUsage, now: now) == "218",
            "the purchased-credit balance drives the exhausted 5h badge even when reset-credit count is zero")

        let creditsForEmptyWindow = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "1234")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: creditsForEmptyWindow, now: now) == "1234",
            "an exhausted 5h window shows the exact available credit count up to four digits")
        let darkAppearance = try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance")
        let quotaBadge = UsageBadgeRenderer.rendering(
            for: try makeUsage(primaryRemaining: 50, weeklyRemaining: 46, now: now),
            style: .doubleRing,
            appearance: darkAppearance,
            now: now
        )
        let creditBadge = UsageBadgeRenderer.rendering(
            for: try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "1"),
            style: .doubleRing,
            appearance: darkAppearance,
            now: now
        )
        let quotaBitmap = try rasterize(quotaBadge.image)
        let creditBitmap = try rasterize(creditBadge.image)
        for bitmap in [quotaBitmap, try rasterize(quotaBadge.image, scale: 2)] {
            check(countOpaquePixels(in: bitmap, xRange: 23..<35, yRange: 8..<16) > 0,
                "synthetic 5h value 50 is visible inside the left ring")
            check(countOpaquePixels(in: bitmap, xRange: 69..<81, yRange: 8..<16) > 0,
                "synthetic weekly value 46 is visible inside the right ring")
        }
        let fullQuotaBadge = UsageBadgeRenderer.rendering(
            for: try makeUsage(primaryRemaining: 100, weeklyRemaining: 100, now: now),
            style: .doubleRing,
            appearance: darkAppearance,
            now: now
        )
        for bitmap in [try rasterize(fullQuotaBadge.image), try rasterize(fullQuotaBadge.image, scale: 2)] {
            check(countOpaquePixels(in: bitmap, xRange: 23..<35, yRange: 8..<16) > 0,
                "synthetic 5h value 100 is visible inside the left ring")
            check(countOpaquePixels(in: bitmap, xRange: 69..<81, yRange: 8..<16) > 0,
                "synthetic weekly value 100 is visible inside the right ring")
        }
        func verifyDoubleRingTextCenter(
            _ image: NSImage,
            description: String,
            text: String,
            ringCenterX: CGFloat,
            expectedCenterX: CGFloat,
            checkTrackOnlyClearance: Bool = false
        ) throws {
            let fontSize = UsageBadgeRenderer.doubleRingFontSize(for: text)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            check(textWidth <= 17.11, "Double Ring \(description) fits its 17pt text width (\(textWidth)pt)")
            for scale in [1, 2] {
                let bitmap = try rasterize(image, scale: scale)
                let scaleX = CGFloat(bitmap.pixelsWide) / 86
                let scaleY = CGFloat(bitmap.pixelsHigh) / 24
                let minX = Int(((ringCenterX - 9) * scaleX).rounded(.down))
                let maxX = Int(((ringCenterX + 9) * scaleX).rounded(.up))
                let minY = Int((4 * scaleY).rounded(.down))
                let maxY = Int((20 * scaleY).rounded(.up))
                var minInkX = Int.max
                var maxInkX = Int.min
                var minInkY = Int.max
                var maxInkY = Int.min
                var inkWeight = 0.0
                var weightedInkX = 0.0
                for y in minY..<maxY {
                    for x in minX..<maxX {
                        let pointX = (CGFloat(x) + 0.5) / scaleX
                        let pointY = (CGFloat(y) + 0.5) / scaleY
                        let dx = pointX - ringCenterX
                        let dy = pointY - 12
                        let alpha = Double(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                        guard dx * dx + dy * dy < 64,
                              alpha > 0.05 else { continue }
                        minInkX = min(minInkX, x)
                        maxInkX = max(maxInkX, x)
                        minInkY = min(minInkY, y)
                        maxInkY = max(maxInkY, y)
                        inkWeight += alpha
                        weightedInkX += Double(pointX) * alpha
                    }
                }
                check(minInkX != Int.max, "synthetic \(description) text is visible at \(scale)x")
                let inkBounds = (minX: minInkX, maxX: maxInkX, minY: minInkY, maxY: maxInkY)
                let centerX = pixelCenterX(inkBounds) / Double(scaleX)
                let centerY = pixelCenterY(inkBounds) / Double(scaleY)
                let horizontalTolerance = scale == 1 ? 0.5 : 0.4
                let verticalTolerance = text.count <= 2 ? (scale == 1 ? 0.5 : 0.25) : 0.5
                let expectedCenterY = 12.0
                check(abs(centerX - Double(expectedCenterX)) <= horizontalTolerance,
                    "Double Ring \(description) ink is horizontally centered at \(scale)x (center \(centerX)pt, target \(expectedCenterX)pt)")
                check(abs(centerY - expectedCenterY) <= verticalTolerance,
                    "Double Ring \(description) ink matches its calibrated vertical center at \(scale)x (center \(centerY)pt, target \(expectedCenterY)pt)")
                if checkTrackOnlyClearance {
                    var textTouchesRing = false
                    for y in max(0, minY - Int(2 * scaleY))..<min(bitmap.pixelsHigh, maxY + Int(2 * scaleY)) {
                        for x in max(0, Int(((ringCenterX - 11) * scaleX).rounded(.down)))..<min(bitmap.pixelsWide, Int(((ringCenterX + 11) * scaleX).rounded(.up))) {
                            let pointX = (CGFloat(x) + 0.5) / scaleX
                            let pointY = (CGFloat(y) + 0.5) / scaleY
                            let dx = pointX - ringCenterX
                            let dy = pointY - 12
                            let radiusSquared = dx * dx + dy * dy
                            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                            if radiusSquared >= 8.575 * 8.575,
                               radiusSquared <= 10.825 * 10.825,
                               alpha > 0.75 {
                                textTouchesRing = true
                            }
                        }
                    }
                    check(!textTouchesRing,
                        "Double Ring \(description) glyph ink stays inside the credit ring track at \(scale)x")
                }
                if text == "164", scale == 2 {
                    let inkCenterX = weightedInkX / inkWeight
                    check(abs(inkCenterX - Double(ringCenterX)) <= 0.22,
                        "Double Ring \(description) visual ink mass is optically centered (center \(inkCenterX)pt, target \(ringCenterX)pt)")
                }
            }
        }
        let quotaSamples = [(0, 100), (1, 50), (9, 99), (10, 1), (50, 10), (99, 9), (100, 0)]
        for (fiveHour, weekly) in quotaSamples {
            let usage = try makeUsage(primaryRemaining: fiveHour, weeklyRemaining: weekly, now: now)
            for (appearanceName, _, _, appearanceLabel) in appearances {
                let appearance = try unwrap(NSAppearance(named: appearanceName), "missing \(appearanceLabel) appearance")
                let image = UsageBadgeRenderer.rendering(for: usage, style: .doubleRing, appearance: appearance, now: now).image
                let expectedLeftX = 29 + UsageBadgeRenderer.doubleRingTextOpticalOffset(for: String(fiveHour))
                let expectedRightX = 75 + UsageBadgeRenderer.doubleRingTextOpticalOffset(for: String(weekly))
                try verifyDoubleRingTextCenter(image, description: "quota \(fiveHour)/\(weekly) left", text: String(fiveHour), ringCenterX: 29, expectedCenterX: expectedLeftX)
                try verifyDoubleRingTextCenter(image, description: "quota \(fiveHour)/\(weekly) right", text: String(weekly), ringCenterX: 75, expectedCenterX: expectedRightX)
            }
        }

        let creditSamples: [(String, String)] = [
            ("0.3", "<1"),
            ("1", "1"),
            ("12", "12"),
            ("100", "100"),
            ("164", "164"),
            ("218", "218"),
            ("1234", "1234"),
            ("12345", "12K"),
            ("123456", "123K"),
            ("1234567", "1.2M"),
            ("9223372036854775807", "9.2E"),
            ("12abc", "?"),
        ]
        check(UsageBadgeRenderer.doubleRingFontSize(for: "99") > UsageBadgeRenderer.doubleRingFontSize(for: "100"),
            "three-digit quota values step down slightly from two-digit values")
        check(UsageBadgeRenderer.doubleRingFontSize(for: "100") > UsageBadgeRenderer.doubleRingFontSize(for: "1234"),
            "four-digit credit values scale down to preserve breathing room")
        check(UsageBadgeRenderer.doubleRingFontSize(for: "1234") > 5.8,
            "four-digit credit values remain comfortably legible")
        for (balance, expectedText) in creditSamples {
            let usage = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: balance)
            let text = UsageBadgeRenderer.creditBalanceBadgeText(for: usage, now: now)
            check(text == expectedText, "credit \(balance) formats as \(expectedText)")
            guard let text else { continue }
            for (appearanceName, _, _, appearanceLabel) in appearances {
                let appearance = try unwrap(NSAppearance(named: appearanceName), "missing \(appearanceLabel) appearance")
                let image = UsageBadgeRenderer.rendering(for: usage, style: .doubleRing, appearance: appearance, now: now).image
                let expectedCenterX = 29 + UsageBadgeRenderer.doubleRingTextOpticalOffset(for: text)
                try verifyDoubleRingTextCenter(image, description: "credit C\(text)", text: text, ringCenterX: 29, expectedCenterX: expectedCenterX, checkTrackOnlyClearance: true)
            }
        }
        let unlimitedCreditUsage = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, unlimitedCredits: true)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: unlimitedCreditUsage, now: now) == "∞",
            "unlimited credit mode uses the centered infinity glyph")
        for (appearanceName, _, _, appearanceLabel) in appearances {
            let appearance = try unwrap(NSAppearance(named: appearanceName), "missing \(appearanceLabel) appearance")
            let image = UsageBadgeRenderer.rendering(for: unlimitedCreditUsage, style: .doubleRing, appearance: appearance, now: now).image
            try verifyDoubleRingTextCenter(image, description: "credit C∞", text: "∞", ringCenterX: 29, expectedCenterX: 29)
        }
        let quotaFiveHourLabel = try unwrap(opaquePixelBounds(in: quotaBitmap, xRange: 4..<15, yRange: 0..<24), "missing 5H label pixels")
        let creditLabel = try unwrap(opaquePixelBounds(in: creditBitmap, xRange: 4..<15, yRange: 0..<24), "missing credit label pixels")
        let weeklyLabel = try unwrap(opaquePixelBounds(in: quotaBitmap, xRange: 50..<61, yRange: 0..<24), "missing 7D label pixels")
        let fiveHourRing = try unwrap(opaquePixelBounds(in: quotaBitmap, xRange: 17..<42, yRange: 0..<24), "missing 5h ring pixels")
        let creditRing = try unwrap(opaquePixelBounds(in: creditBitmap, xRange: 17..<42, yRange: 0..<24), "missing credit ring pixels")
        let weeklyRing = try unwrap(opaquePixelBounds(in: quotaBitmap, xRange: 63..<86, yRange: 0..<24), "missing 7-day ring pixels")
        let weeklyGap = weeklyRing.minX - weeklyLabel.maxX - 1
        check(weeklyGap == 5, "the 7D reference gap remains five empty pixels")
        check(fiveHourRing.minX - quotaFiveHourLabel.maxX - 1 == weeklyGap,
            "the 5H label and its ring have the same pixel gap as the 7D label and ring")
        check(creditRing.minX - creditLabel.maxX - 1 == weeklyGap,
            "the credit C and its ring have the same pixel gap as the 7D label and ring")
        let ringCenterY = pixelCenterY(fiveHourRing)
        check(abs(pixelCenterY(quotaFiveHourLabel) - ringCenterY) <= 0.5,
            "the 5H label's visible pixels are vertically centered on its ring")
        check(abs(pixelCenterY(weeklyLabel) - pixelCenterY(weeklyRing)) <= 0.5,
            "the 7D label's visible pixels are vertically centered on its ring")
        check(abs(pixelCenterY(creditLabel) - pixelCenterY(creditRing)) <= 0.5,
            "the credit C's visible pixels are vertically centered on its ring")
        let retinaQuotaBitmap = try rasterize(quotaBadge.image, scale: 2)
        let retinaCreditBitmap = try rasterize(creditBadge.image, scale: 2)
        let retinaFiveHourLabel = try unwrap(opaquePixelBounds(in: retinaQuotaBitmap, xRange: 4..<15, yRange: 0..<24), "missing Retina 5H label pixels")
        let retinaCreditLabel = try unwrap(opaquePixelBounds(in: retinaCreditBitmap, xRange: 4..<15, yRange: 0..<24), "missing Retina credit label pixels")
        let retinaWeeklyLabel = try unwrap(opaquePixelBounds(in: retinaQuotaBitmap, xRange: 50..<61, yRange: 0..<24), "missing Retina 7D label pixels")
        let retinaFiveHourRing = try unwrap(opaquePixelBounds(in: retinaQuotaBitmap, xRange: 17..<42, yRange: 0..<24), "missing Retina 5h ring pixels")
        let retinaCreditRing = try unwrap(opaquePixelBounds(in: retinaCreditBitmap, xRange: 17..<42, yRange: 0..<24), "missing Retina credit ring pixels")
        let retinaWeeklyRing = try unwrap(opaquePixelBounds(in: retinaQuotaBitmap, xRange: 63..<86, yRange: 0..<24), "missing Retina 7-day ring pixels")
        check(abs(pixelCenterY(retinaFiveHourLabel) - pixelCenterY(retinaFiveHourRing)) <= 0.5,
            "the Retina 5H label's visible pixels are vertically centered on its ring")
        check(abs(pixelCenterY(retinaWeeklyLabel) - pixelCenterY(retinaWeeklyRing)) <= 0.5,
            "the Retina 7D label's visible pixels are vertically centered on its ring")
        check(abs(pixelCenterY(retinaCreditLabel) - pixelCenterY(retinaCreditRing)) <= 0.5,
            "the Retina credit C's visible pixels are vertically centered on its ring")

        func verifyReadoutGroup(
            _ bitmap: NSBitmapImageRep,
            labelRange: Range<Int>,
            numberRange: Range<Int>,
            lineRightEdge: CGFloat,
            description: String
        ) throws {
            let label = try unwrap(opaquePixelBounds(in: bitmap, xRange: labelRange, yRange: 6..<19), "missing Large Readout \(description) label")
            let number = try unwrap(opaquePixelBounds(in: bitmap, xRange: numberRange, yRange: 6..<19), "missing Large Readout \(description) number")
            let expectedCenter = Double(CGFloat(label.maxX + 1) + lineRightEdge * CGFloat(bitmap.pixelsWide) / 86) / 2
            check(abs(pixelCenterX(number) - expectedCenter) <= Double(bitmap.pixelsWide) / 86,
                "Large Readout \(description) number is centered between its label and progress-line end (number \(number.minX)...\(number.maxX), label end \(label.maxX + 1), center \(pixelCenterX(number)), target \(expectedCenter))")
            check(abs(pixelCenterY(label) - pixelCenterY(number)) <= 0.5,
                "Large Readout \(description) label and number share a visible vertical center (label \(pixelCenterY(label)), number \(pixelCenterY(number)))")
        }

        let largeReadoutQuota = UsageBadgeRenderer.rendering(
            for: try makeUsage(primaryRemaining: 50, weeklyRemaining: 46, now: now),
            style: .largeReadout,
            appearance: darkAppearance,
            now: now
        )
        let largeReadoutCredits = try ["218", "1234"].map { balance in
            UsageBadgeRenderer.rendering(
                for: try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: balance),
                style: .largeReadout,
                appearance: darkAppearance,
                now: now
            )
        }
        let quotaReadoutBitmap = try rasterize(largeReadoutQuota.image)
        for bitmap in [quotaReadoutBitmap, try rasterize(largeReadoutQuota.image, scale: 2)] {
            try verifyReadoutGroup(bitmap, labelRange: 1..<12, numberRange: 13..<38, lineRightEdge: 38, description: "5H")
            try verifyReadoutGroup(bitmap, labelRange: 48..<59, numberRange: 60..<85, lineRightEdge: 85, description: "7D")
        }
        for credit in largeReadoutCredits {
            for bitmap in [try rasterize(credit.image), try rasterize(credit.image, scale: 2)] {
                try verifyReadoutGroup(bitmap, labelRange: 1..<12, numberRange: 13..<38, lineRightEdge: 38, description: "credit C")
            }
        }
        let creditsForEmptyWeek = try makeUsage(primaryRemaining: 42, weeklyRemaining: 0, now: now, purchasedCreditBalance: "1234")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: creditsForEmptyWeek, now: now) == "1234",
            "an exhausted weekly window shows credits even while the 5h window has quota left")
        let almostExhaustedWeek = try makeUsage(
            primaryRemaining: 42,
            weeklyRemaining: 0,
            now: now,
            purchasedCreditBalance: "1234",
            weeklyUsedPercent: 99.6
        )
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: almostExhaustedWeek, now: now) == nil,
            "a weekly value rounded to zero does not show credits before full exhaustion")
        let noCreditsForEmptyWeek = try makeUsage(primaryRemaining: 42, weeklyRemaining: 0, now: now)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: noCreditsForEmptyWeek, now: now) == nil,
            "an exhausted weekly window keeps the normal 5h reading when the user has no purchased credits")
        let creditModeReference = try makeUsage(primaryRemaining: 0, weeklyRemaining: 0, now: now, purchasedCreditBalance: "1234")
        let weeklyDepletionAnimation = UsageBadgeTransition(
            fromFiveHour: 42,
            fromWeekly: 8,
            toFiveHour: 42,
            toWeekly: 0,
            startUptime: 0
        ).frame(at: 0.18)
        for style in BadgeStyle.allCases {
            let appearance = try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance")
            let creditModeDuringAnimation = UsageBadgeRenderer.rendering(
                for: creditsForEmptyWeek,
                style: style,
                appearance: appearance,
                now: now,
                animationFrame: weeklyDepletionAnimation
            )
            let creditModeReferenceImage = UsageBadgeRenderer.rendering(
                for: creditModeReference,
                style: style,
                appearance: appearance,
                now: now
            )
            check(countDifferentPixels(
                in: try rasterize(creditModeDuringAnimation.image),
                and: try rasterize(creditModeReferenceImage.image),
                xRange: 0..<44,
                yRange: 0..<24
            ) == 0, "\(style) switches to credit mode immediately while weekly depletion animates")
        }
        let fiveHourResetDuringCreditMode = UsageBadgeTransition(
            fromFiveHour: 42,
            fromWeekly: 0,
            toFiveHour: 100,
            toWeekly: 0,
            startUptime: 0,
            resetWindows: [.fiveHour]
        ).frame(at: 0.18)
        let resetRendering = UsageBadgeRenderer.rendering(
            for: creditsForEmptyWeek,
            style: .doubleRing,
            appearance: try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance"),
            now: now,
            animationFrame: fiveHourResetDuringCreditMode
        )
        check(resetRendering.resetOverlay != nil && resetRendering.resetOverlayAlpha > 0,
            "a confirmed 5h recharge remains visible while weekly exhaustion keeps credit mode active")
        let almostExhausted = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "1234", primaryUsedPercent: 99.6)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: almostExhausted, now: now) == nil,
            "rounding a nearly exhausted window to zero does not show purchased credits early")
        let malformedCreditBalance = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "12abc")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: malformedCreditBalance, now: now) == "?",
            "a malformed purchased balance is not partially parsed as a valid count")
        let manyCredits = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "12345")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: manyCredits, now: now) == "12K",
            "large credit counts use a compact badge value")
        let extremelyManyCredits = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "9223372036854775807")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: extremelyManyCredits, now: now) == "9.2E",
            "very large credit counts remain bounded to the badge width")
        let noCredits = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: noCredits, now: now) == nil,
            "users without credits keep the original zero reading")
        let zeroCreditBalance = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "0")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: zeroCreditBalance, now: now) == nil,
            "an explicit zero purchased-credit balance keeps the original zero reading")
        let resetCreditOnly = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, resetCreditCount: 3)
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: resetCreditOnly, now: now) == nil,
            "earned reset credits are not confused with a purchased usage-credit balance")
        let fractionalCredit = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, purchasedCreditBalance: "0.3")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: fractionalCredit, now: now) == "<1",
            "a positive fractional balance is not displayed as zero")
        let remainingQuotaWithCredits = try makeUsage(primaryRemaining: 1, weeklyRemaining: 88, now: now, purchasedCreditBalance: "3")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: remainingQuotaWithCredits, now: now) == nil,
            "available credits do not replace a nonzero 5h balance")
        let expiredCredits = try makeUsage(primaryRemaining: 0, weeklyRemaining: 88, now: now, primaryExpiry: -1, purchasedCreditBalance: "3")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: expiredCredits, now: now) == nil,
            "expired 5h readings do not show reset credits as if they could apply")
        check(UsageBadgeRenderer.creditBalanceBadgeText(for: creditsForEmptyWindow, now: now, hideReadings: true) == nil,
            "hidden stale readings do not expose an old credit count")
        for style in BadgeStyle.allCases {
            let appearance = try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance")
            let withCredits = try renderButton(
                UsageBadgeRenderer.rendering(for: creditsForEmptyWindow, style: style, appearance: appearance, now: now),
                appearance: appearance,
                tint: .white,
                background: NSColor(calibratedWhite: 0.18, alpha: 1),
                style: style
            )
            let withoutCredits = try renderButton(
                UsageBadgeRenderer.rendering(for: noCredits, style: style, appearance: appearance, now: now),
                appearance: appearance,
                tint: .white,
                background: NSColor(calibratedWhite: 0.18, alpha: 1),
                style: style
            )
            check(countDifferentPixels(in: withCredits.bitmap, and: withoutCredits.bitmap, xRange: 0..<44, yRange: 0..<24) > 0,
                "\(style) replaces the zero badge with a credit count")
            check(countDifferentPixels(in: withCredits.bitmap, and: withoutCredits.bitmap, xRange: 48..<90, yRange: 0..<24) == 0,
                "\(style) leaves the weekly badge unchanged")
        }

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
                    if style == .largeReadout {
                        let redLineEnd = countRedPixels(in: button.bitmap, xRange: 36..<41)
                        check((redLineEnd > 0) == (remaining == 0),
                            "Large Readout \(remaining)% red warning \(remaining == 0 ? "fills" : "stops before") the line end in \(appearanceLabel); got \(redLineEnd) end pixels")
                    }
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

        let unknownWindowReset = UsageBadgeTransition(
            fromFiveHour: 19,
            fromWeekly: 88,
            toFiveHour: 19,
            toWeekly: 88,
            startUptime: 0,
            isConfirmedReset: true
        ).frame(at: 0.4)
        for style in BadgeStyle.allCases {
            let appearance = try unwrap(NSAppearance(named: .darkAqua), "missing dark appearance")
            let resetBadge = try renderButton(
                UsageBadgeRenderer.rendering(
                    for: mixedUsage,
                    style: style,
                    appearance: appearance,
                    now: now,
                    animationFrame: unknownWindowReset
                ),
                appearance: appearance,
                tint: .white,
                background: NSColor(calibratedWhite: 0.18, alpha: 1),
                style: style
            )
            check(countPixels(in: resetBadge.bitmap, xRange: 0..<90, matching: .green) > 0,
                "\(style) acknowledges a confirmed reset without guessing which quota recovered")
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
                    check(countAmberPixels(in: markedButton.bitmap, xRange: 80..<90, yRange: 0..<7) == 0,
                        "\(style) amber reminder is absent from the bottom-right in \(appearanceLabel)")
                    check(markedButton.hasExpiryReminderDot && !plainButton.hasExpiryReminderDot,
                        "\(style) reminder view appears only in the expiring state in \(appearanceLabel)")
                    check(countDifferentPixels(
                        in: markedButton.bitmap,
                        and: plainButton.bitmap,
                        xRange: 80..<86,
                        yRange: 18..<24
                    ) > 0, "\(style) reminder changes its top-right visual region in \(appearanceLabel)")
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

        for (condition, message) in try verifyAppearanceObserver(app: app, usage: mixedUsage) {
            check(condition, message)
        }

        print("BADGE RENDERING PASS: \(assertions) assertions; AppKit button composition, both styles and appearances")
    }

    @MainActor
    private static func verifyAppearanceObserver(
        app: NSApplication,
        usage: UsageSummary
    ) throws -> [(Bool, String)] {
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
        let checks = [
            (callbackImageIsTemplate, "appearance observer rebuilds a template base"),
            (callbackHasWarningOverlay, "appearance observer retains the separate warning overlay"),
        ]
        withExtendedLifetime(observer) {}
        return checks
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
        return RenderedButton(
            bitmap: bitmap,
            imageIsTemplate: button.image?.isTemplate == true,
            hasExpiryReminderDot: button.subviews.contains {
                String(describing: type(of: $0)).contains("BadgeExpiryReminderDotView")
            }
        )
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
        let hasExpiryReminderDot: Bool
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
    private static func rasterize(_ image: NSImage, scale: Int = 1) throws -> NSBitmapImageRep {
        guard scale == 1 || scale == 2 else { throw AuditFailure(message: "unsupported badge image scale") }
        if scale == 1 {
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
                throw AuditFailure(message: "could not rasterize badge image")
            }
            return bitmap
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 86 * scale,
            pixelsHigh: 24 * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw AuditFailure(message: "could not allocate a Retina badge bitmap") }
        bitmap.size = NSSize(width: 86, height: 24)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw AuditFailure(message: "could not create a Retina badge context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 86, height: 24), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
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
    private static func opaquePixelBounds(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        let scaleX = CGFloat(bitmap.pixelsWide) / 86
        let scaleY = CGFloat(bitmap.pixelsHigh) / 24
        let minX = max(0, Int((CGFloat(xRange.lowerBound) * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((CGFloat(xRange.upperBound) * scaleX).rounded(.up)))
        let minY = max(0, Int((CGFloat(yRange.lowerBound) * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((CGFloat(yRange.upperBound) * scaleY).rounded(.up)))
        var firstX = Int.max
        var lastX = Int.min
        var firstY = Int.max
        var lastY = Int.min

        for y in minY..<maxY {
            for x in minX..<maxX where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                firstX = min(firstX, x)
                lastX = max(lastX, x)
                firstY = min(firstY, y)
                lastY = max(lastY, y)
            }
        }
        return firstX == Int.max ? nil : (firstX, lastX, firstY, lastY)
    }

    private static func pixelCenterY(_ bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)) -> Double {
        Double(bounds.minY + bounds.maxY + 1) / 2
    }

    private static func pixelCenterX(_ bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)) -> Double {
        Double(bounds.minX + bounds.maxX + 1) / 2
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
        weeklyExpiry: TimeInterval = 86_400,
        resetCreditCount: Int? = nil,
        purchasedCreditBalance: String? = nil,
        unlimitedCredits: Bool = false,
        primaryUsedPercent: Double? = nil,
        weeklyUsedPercent: Double? = nil
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: primaryUsedPercent ?? Double(100 - primaryRemaining),
                    windowDurationMins: 300,
                    resetsAt: now.timeIntervalSince1970 + primaryExpiry
                ),
                secondary: RateLimitWindow(
                    usedPercent: weeklyUsedPercent ?? Double(100 - weeklyRemaining),
                    windowDurationMins: 10_080,
                    resetsAt: now.timeIntervalSince1970 + weeklyExpiry
                ),
                planType: "plus",
                credits: purchasedCreditBalance.map { RateLimitCreditsSnapshot(hasCredits: true, unlimited: false, balance: $0) }
                    ?? (unlimitedCredits ? RateLimitCreditsSnapshot(hasCredits: true, unlimited: true, balance: nil) : nil)
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: resetCreditCount.map { RateLimitResetCredits(availableCount: $0, credits: nil) },
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
