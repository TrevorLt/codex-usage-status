import AppKit
import XCTest
@testable import CodexUsageStatus

@MainActor
final class AppearanceObserverTests: XCTestCase {
    func testNotifiesWhenEffectiveAppearanceChanges() {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)

        var notifications = 0
        let observer = ApplicationAppearanceObserver {
            notifications += 1
        }

        app.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertGreaterThanOrEqual(notifications, 1)
        withExtendedLifetime(observer) {}
        app.appearance = nil
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
