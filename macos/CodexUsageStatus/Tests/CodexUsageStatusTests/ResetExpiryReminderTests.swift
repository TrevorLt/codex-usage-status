import Foundation
import XCTest
@testable import CodexUsageStatus

final class ResetExpiryReminderTests: XCTestCase {
    @MainActor
    func testResetConsumptionAttemptReusesKeyUntilResolved() throws {
        let suiteName = "ResetConsumptionAttemptTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ResetConsumptionAttemptStore(defaults: defaults)

        XCTAssertThrowsError(try store.begin(creditID: "unknown-account-credit", accountID: nil)) { error in
            XCTAssertEqual(error as? ResetConsumptionAttemptStoreError, .accountIdentityUnavailable)
        }
        XCTAssertFalse(store.hasUnresolvedAttempt(forAccountID: nil))

        let first = try store.begin(creditID: "earliest-credit", accountID: "account-a")
        let retry = try store.begin(creditID: "different-credit", accountID: "account-a")
        let attemptData = try XCTUnwrap(defaults.data(forKey: "PendingResetConsumptionAttempt.v1"))
        XCTAssertFalse(String(decoding: attemptData, as: UTF8.self).contains("account-a"))
        XCTAssertEqual(first, retry)
        XCTAssertEqual(retry.creditID, "earliest-credit")
        XCTAssertTrue(store.hasUnresolvedAttempt(forAccountID: "account-b"))
        XCTAssertThrowsError(try store.begin(creditID: "account-b-credit", accountID: "account-b"))

        store.clear()
        let next = try store.begin(creditID: "different-credit", accountID: "account-b")
        XCTAssertNotEqual(next.idempotencyKey, first.idempotencyKey)
        XCTAssertEqual(next.creditID, "different-credit")
        XCTAssertFalse(store.hasUnresolvedAttempt(forAccountID: "account-b"))
    }

    func testUnknownResetFieldAndNullDetailsDoNotBecomeZeroOrAnExpiryAlert() throws {
        let missing = try decode(#"{"rateLimits":null}"#)
        XCTAssertNil(missing.rateLimitResetCredits)

        let explicitNull = try decode(#"{"rateLimitResetCredits":null}"#)
        XCTAssertNil(explicitNull.rateLimitResetCredits)

        let countOnly = try decode(#"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#)
        let reminder = ResetExpiryReminder(credits: countOnly.rateLimitResetCredits, now: date(1_000))
        XCTAssertEqual(reminder?.availableCount, 2)
        XCTAssertTrue(reminder?.expiringCredits.isEmpty == true)
        XCTAssertNil(reminder?.earliestKnownExpiry)
    }

    func testExpiryThresholdIncludesExactlySeventyTwoHoursAndExcludesLaterOrExpiredRows() {
        let now = date(1_000)
        let summary = RateLimitResetCredits(
            availableCount: 3,
            credits: [
                credit("edge", expiry: now.addingTimeInterval(ResetExpiryReminder.threshold)),
                credit("later", expiry: now.addingTimeInterval(ResetExpiryReminder.threshold + 1)),
                credit("expired", expiry: now.addingTimeInterval(-1)),
            ]
        )

        let reminder = ResetExpiryReminder(credits: summary, now: now)
        XCTAssertEqual(reminder?.expiringCredits.map(\.id), ["edge"])
        XCTAssertEqual(reminder?.earliestKnownExpiry, now.addingTimeInterval(ResetExpiryReminder.threshold))
    }

    func testOnlyAvailableCodexCreditsWithKnownExpiryCanTriggerReminder() {
        let now = date(10_000)
        let rows = [
            credit("wrong-type", resetType: "other", expiry: now.addingTimeInterval(60)),
            credit("consumed", status: "consumed", expiry: now.addingTimeInterval(60)),
            credit("no-expiry", expiry: nil),
            credit("valid", expiry: now.addingTimeInterval(60)),
        ]
        let reminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 4, credits: rows),
            now: now
        )

        XCTAssertEqual(reminder?.expiringCredits.map(\.id), ["valid"])
    }

    func testAvailableCountIsAuthoritativeWhenDetailsDisagree() {
        let now = date(50_000)
        let details = [
            credit("later", expiry: now.addingTimeInterval(60 * 60)),
            credit("earlier", expiry: now.addingTimeInterval(30 * 60)),
        ]

        let oneAvailable = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 1, credits: details),
            now: now
        )
        XCTAssertEqual(oneAvailable?.availableCount, 1)
        XCTAssertEqual(oneAvailable?.expiringCredits.map(\.id), ["earlier"])

        XCTAssertNil(ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 0, credits: details),
            now: now
        ))
    }

    func testDismissedBatchLeavesNewCreditVisibleAndDoesNotSaveRawAccountID() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ResetExpiryDismissalStore(defaults: defaults)
        let now = date(100_000)
        let oldCredit = credit("opaque-old-credit", expiry: now.addingTimeInterval(60 * 60))
        let newCredit = credit("opaque-new-credit", expiry: now.addingTimeInterval(90 * 60))
        let accountID = "private-account-id-for-test"

        store.prepare(accountID: accountID, now: now)
        store.dismiss([oldCredit], accountID: accountID, now: now)
        let dismissed = store.dismissedIDs(accountID: accountID, now: now)
        XCTAssertEqual(dismissed, ["opaque-old-credit"])

        let reminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 2, credits: [oldCredit, newCredit]),
            dismissedIDs: dismissed,
            now: now
        )
        XCTAssertEqual(reminder?.expiringCredits.map(\.id), ["opaque-new-credit"])

        let stored = try XCTUnwrap(defaults.data(forKey: "ResetExpiryDismissals.v1"))
        let storedText = String(decoding: stored, as: UTF8.self)
        XCTAssertFalse(storedText.contains(accountID))
        XCTAssertTrue(storedText.contains("opaque-old-credit"))
    }

    func testDismissalsAreScopedToCurrentAccountAndExpireLocally() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ResetExpiryDismissalStore(defaults: defaults)
        let now = date(200_000)
        let credit = self.credit("id-a", expiry: now.addingTimeInterval(60))

        store.prepare(accountID: "account-a", now: now)
        store.dismiss([credit], accountID: "account-a", now: now)
        XCTAssertEqual(store.dismissedIDs(accountID: "account-a", now: now), ["id-a"])

        store.prepare(accountID: "account-b", now: now)
        XCTAssertTrue(store.dismissedIDs(accountID: "account-b", now: now).isEmpty)
        XCTAssertTrue(store.dismissedIDs(accountID: "account-a", now: now).isEmpty)

        store.dismiss([credit], accountID: "account-b", now: now)
        XCTAssertTrue(store.dismissedIDs(accountID: "account-b", now: now.addingTimeInterval(61)).isEmpty)
    }

    func testFailureAndStaleCacheHideReminderUntilSuccessfulRefresh() {
        let now = date(300_000)
        let lastRead = now.addingTimeInterval(-30)
        XCTAssertTrue(ResetReminderFreshness.canPresent(
            lastRefreshDate: lastRead,
            hasRefreshError: false,
            isAwaitingFreshRead: false,
            refreshInterval: 30,
            now: now
        ))
        XCTAssertFalse(ResetReminderFreshness.canPresent(
            lastRefreshDate: lastRead,
            hasRefreshError: true,
            isAwaitingFreshRead: false,
            refreshInterval: 30,
            now: now
        ))
        XCTAssertFalse(ResetReminderFreshness.canPresent(
            lastRefreshDate: lastRead,
            hasRefreshError: false,
            isAwaitingFreshRead: true,
            refreshInterval: 30,
            now: now
        ))
        XCTAssertFalse(ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-121),
            hasRefreshError: false,
            isAwaitingFreshRead: false,
            refreshInterval: 60,
            now: now
        ))
        XCTAssertTrue(ResetReminderFreshness.canPresent(
            lastRefreshDate: now,
            hasRefreshError: false,
            isAwaitingFreshRead: false,
            refreshInterval: 60,
            now: now
        ))
    }

    func testCountdownUsesHoursOrDaysWithoutSeconds() {
        let now = date(400_000)
        XCTAssertEqual(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(30), now: now), "1 hour")
        XCTAssertEqual(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(60 * 60 + 1), now: now), "2 hours")
        XCTAssertEqual(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(48 * 60 * 60), now: now), "2 days")
    }

    func testCompactHoverUsesLocalTimeAndDoesNotChangeAboutTooltip() throws {
        let timeZone = TimeZone(identifier: "America/Chicago")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 50))!
        let usage = try makeUsage(
            fiveHourReset: now.addingTimeInterval(70 * 60),
            weeklyReset: calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 13))
        )

        XCTAssertEqual(
            usage.hoverTooltip(now: now, locale: Locale(identifier: "en_US"), timeZone: timeZone),
            "5h · Tomorrow 01:00 · in 1h 10m\n7-day · 10/30 13:00"
        )
        XCTAssertEqual(
            usage.hoverTooltip(now: now, locale: Locale(identifier: "en_US"), timeZone: timeZone, showingLastKnownReadings: true),
            "5h · Tomorrow 01:00 · in 1h 10m\n7-day · 10/30 13:00\nShowing last known readings"
        )
        XCTAssertTrue(usage.tooltip(formatter: DateFormatter(), now: now).contains("Codex usage"), "About keeps its detailed diagnostic tooltip")
    }

    func testCompactHoverUsesActualLaterDateAndKeepsUnknownTimesUnknown() throws {
        let timeZone = TimeZone(identifier: "America/Chicago")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 50))!
        let usage = try makeUsage(fiveHourReset: now.addingTimeInterval(49 * 3_600), weeklyReset: nil)

        XCTAssertEqual(
            usage.hoverTooltip(now: now, locale: Locale(identifier: "en_US"), timeZone: timeZone),
            "5h · 11/01 00:50 · in 2d 1h\n7-day · reset time unknown"
        )
    }

    private func decode(_ json: String) throws -> RateLimitsResponse {
        try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
    }

    private func credit(
        _ id: String,
        resetType: String = "codexRateLimits",
        status: String = "available",
        expiry: Date?
    ) -> RateLimitResetCredit {
        RateLimitResetCredit(
            id: id,
            resetType: resetType,
            status: status,
            grantedAt: nil,
            expiresAt: expiry?.timeIntervalSince1970,
            title: nil,
            description: nil
        )
    }

    private func date(_ timestamp: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timestamp)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ResetExpiryReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeUsage(fiveHourReset: Date?, weeklyReset: Date?) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: 35, windowDurationMins: 300, resetsAt: fiveHourReset?.timeIntervalSince1970),
                secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 10_080, resetsAt: weeklyReset?.timeIntervalSince1970),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil,
            accountId: "tooltip-test-account"
        ))
    }
}
