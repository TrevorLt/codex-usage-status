import Foundation
import XCTest
@testable import CodexUsageStatus

final class RefreshPolicyTests: XCTestCase {
    func testInitialSuccessUsesDefaultInterval() {
        var policy = RefreshPolicy()

        let interval = policy.nextInterval(
            previous: nil,
            current: UsageRefreshSnapshot(fiveHourRemaining: 95, weeklyRemaining: 99),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(interval, AppConfig.defaultRefreshInterval)
    }

    func testFivePercentagePointDropUsesFastInterval() {
        var policy = RefreshPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        let interval = policy.nextInterval(
            previous: UsageRefreshSnapshot(fiveHourRemaining: 95, weeklyRemaining: 99),
            current: UsageRefreshSnapshot(fiveHourRemaining: 90, weeklyRemaining: 99),
            now: now
        )

        XCTAssertEqual(interval, AppConfig.minimumRefreshInterval)
    }

    func testSmallerDropKeepsTheNormalInterval() {
        var policy = RefreshPolicy()

        let interval = policy.nextInterval(
            previous: UsageRefreshSnapshot(fiveHourRemaining: 95, weeklyRemaining: 99),
            current: UsageRefreshSnapshot(fiveHourRemaining: 92, weeklyRemaining: 99),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(interval, AppConfig.defaultRefreshInterval)
    }

    func testStableUsageBacksOffToTheResourceCap() {
        var policy = RefreshPolicy()
        let start = Date(timeIntervalSince1970: 1_000)
        let changed = UsageRefreshSnapshot(fiveHourRemaining: 90, weeklyRemaining: 99)

        XCTAssertEqual(
            policy.nextInterval(
                previous: UsageRefreshSnapshot(fiveHourRemaining: 95, weeklyRemaining: 99),
                current: changed,
                now: start
            ),
            AppConfig.minimumRefreshInterval
        )
        XCTAssertEqual(policy.nextInterval(previous: changed, current: changed, now: start.addingTimeInterval(60)), 120)
        XCTAssertEqual(policy.nextInterval(previous: changed, current: changed, now: start.addingTimeInterval(180)), 240)
        XCTAssertEqual(policy.nextInterval(previous: changed, current: changed, now: start.addingTimeInterval(420)), AppConfig.maximumRefreshInterval)
    }

    func testFailureUsesTheConservativeRetryInterval() {
        var policy = RefreshPolicy()

        XCTAssertEqual(policy.intervalAfterFailure(), AppConfig.errorRetryInterval)
    }
}
