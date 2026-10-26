import Foundation

@main
struct ResetRedemptionFlowAudit {
    static func main() async throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("RESET REDEMPTION FLOW FAIL: \(message)\n", stderr)
                exit(1)
            }
            assertions += 1
        }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = try makeUsage(fiveHour: 18, weekly: 67, now: now, fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400)
        let afterFiveHourReset = try makeUsage(
            fiveHour: 100, weekly: 64, now: now,
            fiveHourResetOffset: 3_600 + 14_400, weeklyResetOffset: 86_400
        )

        let resetClient = StubResetClient(consume: .success("reset"), read: .success(afterFiveHourReset))
        let resetResult = await ResetRedemptionFlow(client: resetClient).redeem(
            creditID: "credit-5h", idempotencyKey: "attempt-1", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        switch resetResult {
        case .confirmed(let usage, let windows):
            check(usage.fiveHour.remainingPercent == 100, "a confirmed redemption returns the fresh usage read")
            check(windows == [.fiveHour], "only the window that recovered is marked for reset animation")
        default:
            check(false, "a successful redemption followed by a fresh read is confirmed")
        }
        let resetCounts = await resetClient.callCounts()
        check(resetCounts == (1, 2), "a successful redemption performs one consume with account verification and a follow-up read")

        let weeklyPrevious = try makeUsage(fiveHour: 52, weekly: 16, now: now, fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400)
        let weeklyFresh = try makeUsage(
            fiveHour: 50, weekly: 100, now: now,
            fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400 + 5.6 * 86_400
        )
        let weeklyClient = StubResetClient(consume: .success("alreadyRedeemed"), read: .success(weeklyFresh))
        let weeklyResult = await ResetRedemptionFlow(client: weeklyClient).redeem(
            creditID: "credit-weekly", idempotencyKey: "attempt-2", accountID: "flow-test-account", previousUsage: weeklyPrevious, now: now
        )
        if case .confirmed(_, let windows) = weeklyResult {
            check(windows == [.weekly], "an idempotent success can highlight only the recovered weekly window")
        } else {
            check(false, "alreadyRedeemed is confirmed after a successful fresh read")
        }

        let unchangedClient = StubResetClient(consume: .success("reset"), read: .success(previous))
        let unchangedResult = await ResetRedemptionFlow(client: unchangedClient).redeem(
            creditID: "credit-unchanged", idempotencyKey: "attempt-3", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        if case .confirmed(_, let windows) = unchangedResult {
            check(windows.isEmpty, "a successful request without changed fresh readings triggers no green window")
        } else {
            check(false, "an unchanged fresh read still confirms the server response")
        }

        for outcome in ["noCredit", "nothingToReset"] {
            let client = StubResetClient(consume: .success(outcome), read: .success(previous))
            let result = await ResetRedemptionFlow(client: client).redeem(
                creditID: "unused", idempotencyKey: "attempt-\(outcome)", accountID: "flow-test-account", previousUsage: previous, now: now
            )
            let counts = await client.callCounts()
            check(counts.0 == 1 && counts.1 == 1, "\(outcome) does not trigger a follow-up usage read")
            if outcome == "noCredit" {
                if case .noCredit = result {} else { check(false, "noCredit remains a distinct outcome") }
            } else if case .nothingToReset = result {
            } else {
                check(false, "nothingToReset remains a distinct outcome")
            }
        }

        let unknownClient = StubResetClient(consume: .success("futureOutcome"), read: .success(previous))
        let unknownResult = await ResetRedemptionFlow(client: unknownClient).redeem(
            creditID: "credit", idempotencyKey: "attempt-unknown", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        let unknownCounts = await unknownClient.callCounts()
        check(unknownCounts == (1, 1), "an unknown outcome cannot accidentally request a fresh read")
        if case .statusUnclear = unknownResult {} else { check(false, "an unrecognized response stays status unclear") }

        let consumeFailure = StubResetClient(consume: .failure(.transport), read: .success(previous))
        let consumeFailureResult = await ResetRedemptionFlow(client: consumeFailure).redeem(
            creditID: "credit", idempotencyKey: "attempt-failed", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        let consumeFailureCounts = await consumeFailure.callCounts()
        check(consumeFailureCounts == (1, 1), "a failed consume does not perform a follow-up read or claim a reset")
        if case .statusUnclear = consumeFailureResult {} else { check(false, "a failed consume remains safely retryable") }

        let readFailure = StubResetClient(consume: .success("reset"), read: .failure(.transport), preflight: previous)
        let readFailureResult = await ResetRedemptionFlow(client: readFailure).redeem(
            creditID: "credit", idempotencyKey: "attempt-pending", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        if case .refreshPending = readFailureResult {} else { check(false, "accepted redemption with failed read is reported as refresh pending") }

        let switchedAccount = StubResetClient(consume: .success("reset"), read: .success(previous))
        let switchedResult = await ResetRedemptionFlow(client: switchedAccount).redeem(
            creditID: "old-account-credit", idempotencyKey: "old-account-key", accountID: "different-account", previousUsage: previous, now: now
        )
        let switchedCounts = await switchedAccount.callCounts()
        check(switchedCounts == (0, 1), "an account switch after confirmation sends no consume request")
        if case .accountNotVerified = switchedResult {} else { check(false, "a changed account requires verification") }

        let unavailableAccount = StubResetClient(consume: .success("reset"), read: .failure(.transport))
        let unavailableResult = await ResetRedemptionFlow(client: unavailableAccount).redeem(
            creditID: "unverified-credit", idempotencyKey: "unverified-key", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        let unavailableCounts = await unavailableAccount.callCounts()
        check(unavailableCounts == (0, 1), "failed account verification sends no consume request")
        if case .accountNotVerified = unavailableResult {} else { check(false, "unreadable account stays unverified") }

        for creditID in [nil, "", " \n "] as [String?] {
            let missingID = StubResetClient(consume: .success("reset"), read: .success(previous))
            let missingResult = await ResetRedemptionFlow(client: missingID).redeem(
                creditID: creditID, idempotencyKey: "missing-credit-key", accountID: "flow-test-account", previousUsage: previous, now: now
            )
            let counts = await missingID.callCounts()
            check(counts == (0, 0), "a missing credit ID cannot reach account lookup or consumption")
            if case .accountNotVerified = missingResult {} else { check(false, "a missing credit ID must be handled in Codex") }
        }

        let otherUsage = try makeUsage(fiveHour: 100, weekly: 100, now: now,
            fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400, accountID: "other-account")
        let switchedAfterConsume = StubResetClient(consume: .success("reset"), read: .success(otherUsage), preflight: previous)
        let switchedAfterResult = await ResetRedemptionFlow(client: switchedAfterConsume).redeem(
            creditID: "account-bound-credit", idempotencyKey: "follow-up-switch", accountID: "flow-test-account", previousUsage: previous, now: now
        )
        if case .refreshPending = switchedAfterResult {
            check(true, "a different account's follow-up read cannot be confirmed or highlighted")
        } else {
            check(false, "a different account's usage must not be applied to the redemption")
        }

        print("RESET REDEMPTION FLOW PASS: \(assertions) assertions; mock consume and fresh-read paths")
    }

    private static func makeUsage(
        fiveHour: Int,
        weekly: Int,
        now: Date,
        fiveHourResetOffset: TimeInterval,
        weeklyResetOffset: TimeInterval,
        accountID: String = "flow-test-account"
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: Double(100 - fiveHour), windowDurationMins: 300,
                    resetsAt: now.addingTimeInterval(fiveHourResetOffset).timeIntervalSince1970
                ),
                secondary: RateLimitWindow(
                    usedPercent: Double(100 - weekly), windowDurationMins: 10_080,
                    resetsAt: now.addingTimeInterval(weeklyResetOffset).timeIntervalSince1970
                ),
                planType: "preview"
            ),
            rateLimitsByLimitId: nil,
            accountId: accountID
        ))
    }
}

private actor StubResetClient: ResetRedemptionClient {
    private let consumeResult: Result<String, FixtureError>
    private let readResult: Result<UsageSummary, FixtureError>
    private let preflight: UsageSummary?
    private var consumeCallCount = 0
    private var readCallCount = 0

    init(consume: Result<String, FixtureError>, read: Result<UsageSummary, FixtureError>, preflight: UsageSummary? = nil) {
        self.preflight = preflight
        consumeResult = consume
        readResult = read
    }

    func consumeReset(creditID: String, idempotencyKey: String) async throws -> String {
        consumeCallCount += 1
        return try consumeResult.get()
    }

    func fetchUsage() async throws -> UsageSummary {
        readCallCount += 1
        if readCallCount == 1, let preflight { return preflight }
        return try readResult.get()
    }

    func callCounts() -> (Int, Int) { (consumeCallCount, readCallCount) }
}

private enum FixtureError: Error, LocalizedError, Sendable {
    case transport

    var errorDescription: String? { "Synthetic transport failure" }
}
