import Foundation

@main
struct ResetExpiryAudit {
    static func main() throws {
        var assertions = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            assertions += 1
        }

        let now = Date(timeIntervalSince1970: 1_000_000)
        let missing = try decode(#"{"rateLimits":null}"#)
        check(missing.rateLimitResetCredits == nil, "a missing reset field stays unknown")
        let explicitNull = try decode(#"{"rateLimitResetCredits":null}"#)
        check(explicitNull.rateLimitResetCredits == nil, "a null reset field stays unknown")

        let countOnly = try decode(#"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#)
        let countOnlyReminder = ResetExpiryReminder(credits: countOnly.rateLimitResetCredits, now: now)
        check(countOnlyReminder?.availableCount == 2, "availableCount is retained when details are null")
        check(countOnlyReminder?.expiringCredits.isEmpty == true, "null details do not invent an expiry")
        check(countOnlyReminder?.earliestKnownExpiry == nil, "null details do not invent an expiry date")

        let expiryDetails = ResetCreditExpiryDetails(credits: RateLimitResetCredits(availableCount: 3, credits: [
            credit("later", expiry: now.addingTimeInterval(7_200)),
            credit("soon", expiry: now.addingTimeInterval(1_800)),
            credit("wrong-type", resetType: "other", expiry: now.addingTimeInterval(900)),
            credit("used", status: "consumed", expiry: now.addingTimeInterval(1_200)),
            credit(nil, expiry: now.addingTimeInterval(3_600)),
        ]))
        check(expiryDetails.expirations == [
            now.addingTimeInterval(1_800), now.addingTimeInterval(3_600), now.addingTimeInterval(7_200),
        ], "About expiry details are sorted, filtered and do not require a credit ID")
        let aboutLocalTimeZone = TimeZone(identifier: "America/Chicago")!
        let aboutLocalFormatter = DateFormatter()
        aboutLocalFormatter.locale = Locale(identifier: "en_US_POSIX")
        aboutLocalFormatter.timeZone = aboutLocalTimeZone
        aboutLocalFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        check(expiryDetails.aboutLines(dateFormatter: aboutLocalFormatter) == [
            "Reset 1: 1970-01-12 08:16:40 CST",
            "Reset 2: 1970-01-12 08:46:40 CST",
            "Reset 3: 1970-01-12 09:46:40 CST",
        ], "About reset expirations use the same explicit local time zone as the other timestamps")
        let aboutReferenceText = aboutLocalFormatter.string(from: now.addingTimeInterval(1_800))
        let aboutUsage = try makeUsage(
            fiveHourReset: now.addingTimeInterval(1_800),
            weeklyReset: now.addingTimeInterval(3_600)
        )
        check(
            aboutUsage.tooltip(formatter: aboutLocalFormatter, now: now).contains("resets \(aboutReferenceText)")
                && expiryDetails.aboutLines(dateFormatter: aboutLocalFormatter)[0].hasSuffix(aboutReferenceText),
            "About usage and earned-reset timestamps share one local date/time reference"
        )
        let partialExpiryDetails = ResetCreditExpiryDetails(credits: RateLimitResetCredits(
            availableCount: 2,
            credits: [credit("known", expiry: now.addingTimeInterval(4_000))]
        ))
        check(partialExpiryDetails.aboutLines(dateFormatter: aboutLocalFormatter) == [
            "Reset 1: 1970-01-12 08:53:20 CST",
            "Reset 2: expiration time unavailable",
        ], "missing reset details stay explicit in About")
        check(ResetCreditExpiryDetails(credits: RateLimitResetCredits(availableCount: 0, credits: nil)).expirations.isEmpty,
            "zero available resets do not add an About section")

        let boundary = RateLimitResetCredits(
            availableCount: 3,
            credits: [
                credit("edge", expiry: now.addingTimeInterval(ResetExpiryReminder.threshold)),
                credit("later", expiry: now.addingTimeInterval(ResetExpiryReminder.threshold + 1)),
                credit("expired", expiry: now.addingTimeInterval(-1)),
            ]
        )
        let boundaryReminder = ResetExpiryReminder(credits: boundary, now: now)
        check(boundaryReminder?.expiringCredits.map(\.id) == ["edge"], "72-hour boundary includes exact expiry and excludes later/expired rows")
        check(boundaryReminder?.earliestKnownExpiry == now.addingTimeInterval(ResetExpiryReminder.threshold), "earliest known future expiry is selected")

        let filtered = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 4, credits: [
                credit("wrong-type", resetType: "other", expiry: now.addingTimeInterval(60)),
                credit("consumed", status: "consumed", expiry: now.addingTimeInterval(60)),
                credit("no-expiry", expiry: nil),
                credit("valid", expiry: now.addingTimeInterval(60)),
            ]),
            now: now
        )
        check(filtered?.expiringCredits.map(\.id) == ["valid"], "only available Codex credits with known expiry qualify")

        let mismatched = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 1, credits: [
                credit("one", expiry: now.addingTimeInterval(3_600)),
                credit("two", expiry: now.addingTimeInterval(1_800)),
            ]),
            now: now
        )
        check(mismatched?.availableCount == 1, "service count remains authoritative")
        check(mismatched?.expiringCredits.map(\.id) == ["two"], "detail rows are capped to the authoritative available count")
        let zeroCount = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 0, credits: [credit("x", expiry: now.addingTimeInterval(60))]),
            now: now
        )
        check({ if case nil = zeroCount { return true }; return false }(), "zero available count hides detail rows")

        let suite = "ResetExpiryAudit-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw AuditFailure(message: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ResetExpiryDismissalStore(defaults: defaults)
        let oldCredit = credit("old-credit-id", expiry: now.addingTimeInterval(3_600))
        let newCredit = credit("new-credit-id", expiry: now.addingTimeInterval(5_400))
        let accountA = "private-account-id"
        store.prepare(accountID: accountA, now: now)
        store.dismiss([oldCredit], accountID: accountA, now: now)
        let dismissed = store.dismissedIDs(accountID: accountA, now: now)
        check(dismissed == ["old-credit-id"], "dismissed IDs persist within the current account scope")
        let afterNewCredit = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 2, credits: [oldCredit, newCredit]),
            dismissedIDs: dismissed,
            now: now
        )
        check(afterNewCredit?.expiringCredits.map(\.id) == ["new-credit-id"], "a newly received credit is not suppressed by the prior dismissal")
        if let data = defaults.data(forKey: "ResetExpiryDismissals.v1") {
            check(!String(decoding: data, as: UTF8.self).contains(accountA), "persisted scope does not contain the raw account identity")
        } else {
            check(false, "dismissal record is persisted")
        }

        store.prepare(accountID: "private-account-b", now: now)
        check(store.dismissedIDs(accountID: "private-account-b", now: now).isEmpty, "account switch clears the active dismissal batch")
        check(store.dismissedIDs(accountID: accountA, now: now).isEmpty, "old account dismissals cannot suppress the current account")
        store.dismiss([oldCredit], accountID: "private-account-b", now: now)
        check(store.dismissedIDs(accountID: "private-account-b", now: now.addingTimeInterval(3_601)).isEmpty, "expired dismissed IDs are pruned")

        check(ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-30), hasRefreshError: false, isAwaitingFreshRead: false,
            refreshInterval: 30, now: now
        ), "fresh successful data permits a reminder")
        check(!ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-30), hasRefreshError: true, isAwaitingFreshRead: false,
            refreshInterval: 30, now: now
        ), "refresh failure hides cached reset data")
        check(!ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-30), hasRefreshError: false, isAwaitingFreshRead: true,
            refreshInterval: 30, now: now
        ), "wake recovery hides reset data until a fresh read")
        check(!ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-121), hasRefreshError: false, isAwaitingFreshRead: false,
            refreshInterval: 60, now: now
        ), "stale data hides reset availability")
        check(!ResetReminderFreshness.canPresent(
            lastRefreshDate: now.addingTimeInterval(-120), hasRefreshError: false, isAwaitingFreshRead: false,
            refreshInterval: 60, now: now
        ), "stale cache is hidden at its exact age boundary")
        check(ResetReminderFreshness.canPresent(
            lastRefreshDate: now, hasRefreshError: false, isAwaitingFreshRead: false,
            refreshInterval: 60, now: now
        ), "a successful refresh restores reset availability")

        check(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(30), now: now) == "1 hour", "sub-hour labels never show seconds")
        check(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(3_601), now: now) == "2 hours", "hour labels round up")
        check(ResetExpiryReminder.remainingTimeText(until: now.addingTimeInterval(172_800), now: now) == "2 days", "day labels use whole days")
        let twoDaysReminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 1, credits: [credit("two-days", expiry: now.addingTimeInterval(172_800))]),
            now: now
        )
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "MMM d"
        check(twoDaysReminder?.menuTitle(dateFormatter: dateFormatter, now: now) == "1 reset expires in 2 days", "near-expiry menu wording matches the concise English UI")
        let plainReminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 2, credits: [credit("later", expiry: now.addingTimeInterval(100 * 3_600))]),
            now: now
        )
        let expectedPlainTitle = "2 resets available · earliest expires \(dateFormatter.string(from: now.addingTimeInterval(100 * 3_600)))"
        check(plainReminder?.menuTitle(dateFormatter: dateFormatter, now: now) == expectedPlainTitle, "normal menu wording uses count and earliest known date")
        let transitionReminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 1, credits: [credit("transition", expiry: now.addingTimeInterval(49 * 3_600))]),
            now: now
        )
        check(transitionReminder?.nextDisplayTransition(after: now) == now.addingTimeInterval(3_600), "countdown label has a local hour-level redraw deadline")

        var chicago = Calendar(identifier: .gregorian)
        let chicagoTimeZone = TimeZone(identifier: "America/Chicago")!
        chicago.timeZone = chicagoTimeZone
        let chicagoNow = chicago.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 50))!
        let tomorrow = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(70 * 60),
            weeklyReset: chicago.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 13, minute: 0))
        )
        let tomorrowTooltip = tomorrow.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
        check(tomorrowTooltip == "5h · Tomorrow 01:00 · in 1h 10m\n7-day · 10/30 13:00",
            "hover uses local 24-hour time, Tomorrow, and a concise relative duration; got \(tomorrowTooltip.debugDescription)")

        let exhaustedWithCredits = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(3_600),
            weeklyReset: chicagoNow.addingTimeInterval(86_400),
            fiveHourUsedPercent: 100,
            availableCreditBalance: "1234.56789"
        )
        check(exhaustedWithCredits.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            == "5h · Tomorrow 00:50 · in 1h\n7-day · 10/30 23:50\n1234.568 credits available",
            "hover rounds the purchased-credit balance to three decimal places")
        let tinyCreditBalance = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(3_600),
            weeklyReset: chicagoNow.addingTimeInterval(86_400),
            fiveHourUsedPercent: 100,
            availableCreditBalance: "0.0004"
        )
        check(tinyCreditBalance.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            .hasSuffix("<0.001 credits available"),
            "a positive balance below the display precision is not rounded down to zero")
        let emptyCreditBalance = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(3_600),
            weeklyReset: chicagoNow.addingTimeInterval(86_400),
            fiveHourUsedPercent: 100,
            availableCreditBalance: "0"
        )
        check(emptyCreditBalance.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            == "5h · Tomorrow 00:50 · in 1h\n7-day · 10/30 23:50",
            "an explicit zero balance does not imply credits are available")
        let almostExhaustedHover = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(3_600),
            weeklyReset: chicagoNow.addingTimeInterval(86_400),
            fiveHourUsedPercent: 99.6,
            availableCreditBalance: "1234"
        )
        check(!almostExhaustedHover.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            .contains("credits available"),
            "rounded zero usage does not describe credits as available before the quota is fully used")
        let malformedCreditHover = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(3_600),
            weeklyReset: chicagoNow.addingTimeInterval(86_400),
            fiveHourUsedPercent: 100,
            availableCreditBalance: "12abc"
        )
        check(malformedCreditHover.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            .hasSuffix("Credits available"),
            "malformed balance text is not partially parsed into a misleading number")

        let farther = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(49 * 3_600),
            weeklyReset: nil
        )
        let fartherTooltip = farther.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
        check(fartherTooltip == "5h · 11/01 00:50 · in 2d 1h\n7-day · reset time unknown",
            "a reset beyond tomorrow uses its actual date and missing weekly time stays unknown; got \(fartherTooltip.debugDescription)")

        let unknown = try makeUsage(fiveHourReset: nil, weeklyReset: nil)
        check(unknown.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            == "5h · reset time unknown\n7-day · reset time unknown",
            "missing reset timestamps do not become fabricated dates")
        check(unknown.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone, showingLastKnownReadings: true)
            == "5h · reset time unknown\n7-day · reset time unknown\nShowing last known readings",
            "stale hover adds only the brief cached-data status line")
        let expiredHover = try makeUsage(
            fiveHourReset: chicagoNow.addingTimeInterval(-1),
            weeklyReset: chicagoNow.addingTimeInterval(-1),
            fiveHourUsedPercent: 100,
            availableCredits: 3,
            availableCreditBalance: "100"
        )
        check(expiredHover.hoverTooltip(now: chicagoNow, locale: Locale(identifier: "en_US"), timeZone: chicagoTimeZone)
            == "5h · expired\n7-day · expired",
            "expired windows are labeled without displaying stale future times")

        let many = (0..<140).map { index in
            credit("bounded-\(index)", expiry: now.addingTimeInterval(Double(index + 1)))
        }
        store.prepare(accountID: "bounded-account", now: now)
        store.dismiss(many, accountID: "bounded-account", now: now)
        check(store.dismissedIDs(accountID: "bounded-account", now: now).count == 128, "persisted dismissal IDs have a fixed upper bound")

        let attemptSuite = "ResetConsumptionAttemptAudit-\(UUID().uuidString)"
        guard let attemptDefaults = UserDefaults(suiteName: attemptSuite) else {
            throw AuditFailure(message: "could not create reset-attempt test storage")
        }
        defer { attemptDefaults.removePersistentDomain(forName: attemptSuite) }
        let attemptRetryIsSafe = MainActor.assumeIsolated { () -> Bool in
            let attemptStore = ResetConsumptionAttemptStore(defaults: attemptDefaults)
            let first = attemptStore.begin(creditID: "earliest-credit", accountID: "account-a")!
            let retry = attemptStore.begin(creditID: "different-credit", accountID: "account-a")!
            guard first == retry, retry.creditID == "earliest-credit" else { return false }
            guard attemptStore.begin(creditID: "other-account-credit", accountID: "account-b") == nil,
                  attemptStore.pending == first else { return false }
            guard attemptStore.begin(creditID: nil, accountID: "") == nil else { return false }
            guard let stored = attemptDefaults.data(forKey: "PendingResetConsumptionAttempt.v1"),
                  !String(decoding: stored, as: UTF8.self).contains("account-a") else { return false }
            attemptStore.clear()
            let next = attemptStore.begin(creditID: "different-credit", accountID: "account-a")!
            guard next.idempotencyKey != first.idempotencyKey && next.creditID == "different-credit" else { return false }
            attemptDefaults.set(Data(#"{"creditID":"legacy-credit","idempotencyKey":"legacy-key"}"#.utf8),
                                forKey: "PendingResetConsumptionAttempt.v1")
            return attemptStore.pending?.idempotencyKey == "legacy-key"
                && attemptStore.begin(creditID: "new-credit", accountID: "account-a") == nil
        }
        check(attemptRetryIsSafe, "retries preserve their key and credit, reject other accounts, and retain unbound legacy requests")

        print("RESET EXPIRY PASS: \(assertions) assertions; boundaries, unknown details, account scope, freshness and dismissal")
    }

    private static func decode(_ json: String) throws -> RateLimitsResponse {
        try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
    }

    private static func credit(
        _ id: String?,
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

    private static func makeUsage(
        fiveHourReset: Date?,
        weeklyReset: Date?,
        fiveHourUsedPercent: Double = 35,
        availableCredits: Int? = nil,
        availableCreditBalance: String? = nil
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: fiveHourUsedPercent, windowDurationMins: 300, resetsAt: fiveHourReset?.timeIntervalSince1970),
                secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 10_080, resetsAt: weeklyReset?.timeIntervalSince1970),
                planType: "plus",
                credits: availableCreditBalance.map { RateLimitCreditsSnapshot(hasCredits: true, unlimited: false, balance: $0) }
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: availableCredits.map { RateLimitResetCredits(availableCount: $0, credits: nil) },
            accountId: "tooltip-test-account"
        ))
    }
}

private struct AuditFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
