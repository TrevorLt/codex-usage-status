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

    func testWarningUsageKeepsColoredRendering() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let usage = try makeUsage(fiveHourUsedPercent: 85, weeklyUsedPercent: 2)
        let image = UsageBadgeRenderer.image(for: usage, style: .doubleRing, appearance: appearance)

        XCTAssertFalse(image.isTemplate)
    }

    func testPlaceholderUsesNativeTemplateTinting() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let image = UsageBadgeRenderer.placeholderImage(style: .largeReadout, appearance: appearance)

        XCTAssertTrue(image.isTemplate)
    }

    private func makeUsage(fiveHourUsedPercent: Double, weeklyUsedPercent: Double) throws -> UsageSummary {
        let response = RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: fiveHourUsedPercent, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: weeklyUsedPercent, windowDurationMins: 10_080, resetsAt: nil),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil
        )

        return try UsageSummary(response: response)
    }
}
