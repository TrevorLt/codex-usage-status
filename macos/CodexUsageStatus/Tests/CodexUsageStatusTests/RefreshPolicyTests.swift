import Foundation
import XCTest
@testable import CodexUsageStatus

final class RefreshPolicyTests: XCTestCase {
    func testStartupWithoutPreviousSnapshotUsesFastInterval() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)

        let interval = policy.nextInterval(
            previous: nil,
            current: snapshot(fiveHourUsed: 5, weeklyUsed: 10),
            now: 1_000
        )

        XCTAssertEqual(interval, 30)
    }

    func testStableUsageUsesThirtySixtyAndOneHundredTwentySecondStages() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)
        let usage = snapshot(fiveHourUsed: 30, weeklyUsed: 50)

        XCTAssertEqual(policy.nextInterval(previous: nil, current: usage, now: 100), 30)
        XCTAssertEqual(policy.nextInterval(previous: usage, current: usage, now: 189), 30)
        XCTAssertEqual(policy.nextInterval(previous: usage, current: usage, now: 190), 60)
        XCTAssertEqual(policy.nextInterval(previous: usage, current: usage, now: 399), 60)
        XCTAssertEqual(policy.nextInterval(previous: usage, current: usage, now: 400), 120)
    }

    func testRawUsageDecreaseInEitherWindowRebuildsBaseline() {
        let cases: [(UsageRefreshSnapshot, UsageRefreshSnapshot)] = [
            (snapshot(fiveHourUsed: 50, weeklyUsed: 40), snapshot(fiveHourUsed: 49.9, weeklyUsed: 40)),
            (snapshot(fiveHourUsed: 50, weeklyUsed: 40), snapshot(fiveHourUsed: 50, weeklyUsed: 39.9))
        ]

        for (previous, current) in cases {
            var policy = RefreshPolicy(fixedIntervalOverride: nil)
            XCTAssertEqual(policy.nextInterval(previous: nil, current: previous, now: 0), 30)
            XCTAssertEqual(policy.nextInterval(previous: previous, current: current, now: 200), 30)
            XCTAssertEqual(policy.nextInterval(previous: current, current: current, now: 289), 30)
            XCTAssertEqual(policy.nextInterval(previous: current, current: current, now: 290), 60)
        }
    }

    func testRawUsageIncreaseInEitherWindowStartsFastCadence() {
        let cases: [(UsageRefreshSnapshot, UsageRefreshSnapshot)] = [
            (snapshot(fiveHourUsed: 10, weeklyUsed: 40), snapshot(fiveHourUsed: 10.1, weeklyUsed: 40)),
            (snapshot(fiveHourUsed: 10, weeklyUsed: 40), snapshot(fiveHourUsed: 10, weeklyUsed: 40.1))
        ]

        for (previous, current) in cases {
            var policy = RefreshPolicy(fixedIntervalOverride: nil)
            XCTAssertEqual(policy.nextInterval(previous: nil, current: previous, now: 0), 30)
            XCTAssertEqual(policy.nextInterval(previous: previous, current: current, now: 200), 30)
        }
    }

    func testCreditBalanceChangeUsesTheSameAdaptiveCadence() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)
        let before = snapshot(
            fiveHourUsed: 100,
            weeklyUsed: 50,
            credits: RateLimitCreditsSnapshot(hasCredits: true, unlimited: false, balance: "218.3286855")
        )
        let after = snapshot(
            fiveHourUsed: 100,
            weeklyUsed: 50,
            credits: RateLimitCreditsSnapshot(hasCredits: true, unlimited: false, balance: "217.3286855")
        )

        XCTAssertEqual(policy.nextInterval(previous: nil, current: before, now: 100), 30)
        XCTAssertEqual(policy.nextInterval(previous: before, current: after, now: 200), 30)
        XCTAssertEqual(policy.nextInterval(previous: after, current: after, now: 289), 30)
        XCTAssertEqual(policy.nextInterval(previous: after, current: after, now: 290), 60)
    }

    func testRemainingDropFromNinetyToEightyNineUsesFastCadence() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)
        let previous = UsageRefreshSnapshot(fiveHourRemaining: 90, weeklyRemaining: 80)
        let current = UsageRefreshSnapshot(fiveHourRemaining: 89, weeklyRemaining: 80)

        XCTAssertEqual(policy.nextInterval(previous: nil, current: previous, now: 0), 30)
        XCTAssertEqual(policy.nextInterval(previous: previous, current: current, now: 200), 30)
    }

    func testWindowCycleRebuildsBaselineEvenWhenRawUsageDidNotDecrease() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)
        let oldReset = Date(timeIntervalSince1970: 10_000)
        let previous = snapshot(
            fiveHourUsed: 20,
            weeklyUsed: 40,
            fiveHourResetsAt: oldReset
        )
        let cycled = snapshot(
            fiveHourUsed: 20,
            weeklyUsed: 40,
            fiveHourResetsAt: oldReset.addingTimeInterval(5 * 60 * 60)
        )

        XCTAssertEqual(policy.nextInterval(previous: nil, current: previous, now: 0), 30)
        XCTAssertEqual(policy.nextInterval(previous: previous, current: cycled, now: 400), 30)
        XCTAssertEqual(policy.nextInterval(previous: cycled, current: cycled, now: 489), 30)
        XCTAssertEqual(policy.nextInterval(previous: cycled, current: cycled, now: 490), 60)
    }

    func testFailureKeepsFixedRetryAndDoesNotMoveActivityBaseline() {
        var policy = RefreshPolicy(fixedIntervalOverride: nil)
        let usage = snapshot(fiveHourUsed: 30, weeklyUsed: 50)

        XCTAssertEqual(policy.nextInterval(previous: nil, current: usage, now: 0), 30)
        XCTAssertEqual(policy.intervalAfterFailure(), 300)
        XCTAssertEqual(policy.currentInterval, 300)
        XCTAssertEqual(policy.nextInterval(previous: usage, current: usage, now: 90), 60)
    }

    func testExplicitEnvironmentOverrideIsFixedAndHasThirtySecondFloor() {
        XCTAssertEqual(configuredRefreshIntervalOverride(environmentValue: "42.5"), 42.5)
        XCTAssertEqual(configuredRefreshIntervalOverride(environmentValue: "15"), 30)
        XCTAssertEqual(configuredRefreshIntervalOverride(environmentValue: "601"), 601)
        XCTAssertNil(configuredRefreshIntervalOverride(environmentValue: "NaN"))
        XCTAssertNil(configuredRefreshIntervalOverride(environmentValue: "infinity"))
        XCTAssertNil(configuredRefreshIntervalOverride(environmentValue: "invalid"))
        XCTAssertNil(configuredRefreshIntervalOverride(environmentValue: nil))

        var policy = RefreshPolicy(fixedIntervalOverride: 42.5)
        let old = snapshot(fiveHourUsed: 80, weeklyUsed: 70)
        let new = snapshot(fiveHourUsed: 20, weeklyUsed: 70)
        XCTAssertEqual(policy.nextInterval(previous: nil, current: old, now: 0), 42.5)
        XCTAssertEqual(policy.nextInterval(previous: old, current: new, now: 1), 42.5)
    }

    private func snapshot(
        fiveHourUsed: Double,
        weeklyUsed: Double,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        credits: RateLimitCreditsSnapshot? = nil
    ) -> UsageRefreshSnapshot {
        UsageRefreshSnapshot(
            fiveHourRemaining: Int((100 - fiveHourUsed).rounded()),
            weeklyRemaining: Int((100 - weeklyUsed).rounded()),
            fiveHourRawUsedPercent: fiveHourUsed,
            weeklyRawUsedPercent: weeklyUsed,
            fiveHourWindowDurationMins: 300,
            weeklyWindowDurationMins: 10_080,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            credits: credits
        )
    }
}
