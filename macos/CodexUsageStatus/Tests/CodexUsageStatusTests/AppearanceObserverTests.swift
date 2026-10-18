import AppKit
import XCTest
@testable import CodexUsageStatus

@MainActor
final class AppearanceObserverTests: XCTestCase {
    func testNotifiesWhenEffectiveAppearanceChangesAndWarningKeepsItsLayers() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = nil }

        let usage = try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: 81, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 10_080, resetsAt: nil),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil
        ))

        var notifications = 0
        var warningRemainedLayered = false
        let observer = ApplicationAppearanceObserver {
            notifications += 1
            let rendering = UsageBadgeRenderer.rendering(
                for: usage,
                style: .doubleRing,
                appearance: app.effectiveAppearance
            )
            warningRemainedLayered = rendering.image.isTemplate && rendering.warningOverlay != nil
        }

        app.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertGreaterThanOrEqual(notifications, 1)
        XCTAssertTrue(warningRemainedLayered)
        withExtendedLifetime(observer) {}
    }

    func testNotifiesForTheSystemAppearanceChangeNotification() {
        var notifications = 0
        let observer = ApplicationAppearanceObserver {
            notifications += 1
        }

        DistributedNotificationCenter.default.post(
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertGreaterThanOrEqual(notifications, 1)
        withExtendedLifetime(observer) {}
    }
}
