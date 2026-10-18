import AppKit
import XCTest
@testable import CodexUsageStatus

@MainActor
final class AppearanceColorTests: XCTestCase {
    func testNormalUsageUsesNativeTemplateTinting() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let usage = try makeUsage(fiveHourUsedPercent: 11, weeklyUsedPercent: 2)
        let image = UsageBadgeRenderer.image(for: usage, style: .doubleRing, appearance: appearance)

        XCTAssertTrue(image.isTemplate)
    }

    func testWarningUsesSeparateRedOverlayAndKeepsNativeTemplateBase() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let usage = try makeUsage(fiveHourUsedPercent: 85, weeklyUsedPercent: 2)
        let rendering = UsageBadgeRenderer.rendering(for: usage, style: .doubleRing, appearance: appearance)

        XCTAssertTrue(rendering.image.isTemplate)
        XCTAssertEqual(rendering.image.size, NSSize(width: 86, height: 24))
        XCTAssertFalse(try XCTUnwrap(rendering.warningOverlay).isTemplate)

        let legacyImage = UsageBadgeRenderer.image(for: usage, style: .doubleRing, appearance: appearance)
        XCTAssertTrue(legacyImage.isTemplate, "single-image compatibility access returns only the neutral template base")
    }

    func testExactlyTwentyPercentDoesNotCreateWarningOverlay() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let usage = try makeUsage(fiveHourUsedPercent: 80, weeklyUsedPercent: 12)

        let rendering = UsageBadgeRenderer.rendering(for: usage, style: .doubleRing, appearance: appearance)

        XCTAssertTrue(rendering.image.isTemplate)
        XCTAssertNil(rendering.warningOverlay)
    }

    func testExpiredAndHiddenWarningsUseOnlyTheNativeTemplateImage() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let now = Date()
        let expiredUsage = try makeUsage(
            fiveHourUsedPercent: 100,
            weeklyUsedPercent: 12,
            fiveHourResetsAt: now.addingTimeInterval(-1)
        )

        let expired = UsageBadgeRenderer.rendering(
            for: expiredUsage,
            style: .doubleRing,
            appearance: appearance,
            now: now
        )
        let cachedHidden = UsageBadgeRenderer.rendering(
            for: try makeUsage(fiveHourUsedPercent: 100, weeklyUsedPercent: 12),
            style: .doubleRing,
            appearance: appearance,
            now: now,
            hideReadings: true
        )

        XCTAssertTrue(expired.image.isTemplate)
        XCTAssertNil(expired.warningOverlay)
        XCTAssertTrue(cachedHidden.image.isTemplate)
        XCTAssertNil(cachedHidden.warningOverlay)
    }

    func testPlaceholderUsesNativeTemplateTinting() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let image = UsageBadgeRenderer.placeholderImage(style: .largeReadout, appearance: appearance)

        XCTAssertTrue(image.isTemplate)
    }

    private func makeUsage(
        fiveHourUsedPercent: Double,
        weeklyUsedPercent: Double,
        fiveHourResetsAt: Date? = nil
    ) throws -> UsageSummary {
        let response = RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: fiveHourUsedPercent,
                    windowDurationMins: 300,
                    resetsAt: fiveHourResetsAt?.timeIntervalSince1970
                ),
                secondary: RateLimitWindow(usedPercent: weeklyUsedPercent, windowDurationMins: 10_080, resetsAt: nil),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil
        )

        return try UsageSummary(response: response)
    }
}
