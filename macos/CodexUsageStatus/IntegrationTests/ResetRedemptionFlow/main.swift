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
            creditID: "credit-5h", idempotencyKey: "attempt-1", previousUsage: previous, now: now
        )
        switch resetResult {
        case .confirmed(let usage, let windows):
            check(usage.fiveHour.remainingPercent == 100, "a confirmed redemption returns the fresh usage read")
            check(windows == [.fiveHour], "only the window that recovered is marked for reset animation")
        default:
            check(false, "a successful redemption followed by a fresh read is confirmed")
        }
        let resetCounts = await resetClient.callCounts()
        check(resetCounts == (1, 2), "a successful redemption verifies the active account before consuming, then reads refreshed usage")

        let weeklyPrevious = try makeUsage(fiveHour: 52, weekly: 16, now: now, fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400)
        let weeklyFresh = try makeUsage(
            fiveHour: 50, weekly: 100, now: now,
            fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400 + 5.6 * 86_400
        )
        let weeklyClient = StubResetClient(consume: .success("alreadyRedeemed"), read: .success(weeklyFresh))
        let weeklyResult = await ResetRedemptionFlow(client: weeklyClient).redeem(
            creditID: nil, idempotencyKey: "attempt-2", previousUsage: weeklyPrevious, now: now
        )
        if case .confirmed(_, let windows) = weeklyResult {
            check(windows == [.weekly], "an idempotent success can highlight only the recovered weekly window")
        } else {
            check(false, "alreadyRedeemed is confirmed after a successful fresh read")
        }

        let unchangedClient = StubResetClient(consume: .success("reset"), read: .success(previous))
        let unchangedResult = await ResetRedemptionFlow(client: unchangedClient).redeem(
            creditID: "credit-unchanged", idempotencyKey: "attempt-3", previousUsage: previous, now: now
        )
        if case .confirmed(_, let windows) = unchangedResult {
            check(windows.isEmpty, "a successful request without changed fresh readings triggers no green window")
        } else {
            check(false, "an unchanged fresh read still confirms the server response")
        }

        for outcome in ["noCredit", "nothingToReset"] {
            let client = StubResetClient(consume: .success(outcome), read: .success(previous))
            let result = await ResetRedemptionFlow(client: client).redeem(
                creditID: "unused", idempotencyKey: "attempt-\(outcome)", previousUsage: previous, now: now
            )
            let counts = await client.callCounts()
            check(counts == (1, 1), "\(outcome) verifies account identity before consume and skips post-consume read")
            if outcome == "noCredit" {
                if case .noCredit = result {} else { check(false, "noCredit remains a distinct outcome") }
            } else if case .nothingToReset = result {
            } else {
                check(false, "nothingToReset remains a distinct outcome")
            }
        }

        let unknownClient = StubResetClient(consume: .success("futureOutcome"), read: .success(previous))
        let unknownResult = await ResetRedemptionFlow(client: unknownClient).redeem(
            creditID: "credit", idempotencyKey: "attempt-unknown", previousUsage: previous, now: now
        )
        let unknownCounts = await unknownClient.callCounts()
        check(unknownCounts == (1, 1), "an unknown outcome cannot accidentally request a post-consume read")
        if case .statusUnclear = unknownResult {} else { check(false, "an unrecognized response stays status unclear") }

        let consumeFailure = StubResetClient(consume: .failure(.transport), read: .success(previous))
        let consumeFailureResult = await ResetRedemptionFlow(client: consumeFailure).redeem(
            creditID: "credit", idempotencyKey: "attempt-failed", previousUsage: previous, now: now
        )
        let consumeFailureCounts = await consumeFailure.callCounts()
        check(consumeFailureCounts == (1, 1), "a failed consume happens only after active-account preflight")
        if case .statusUnclear = consumeFailureResult {} else { check(false, "a failed consume remains safely retryable") }

        let readFailure = StubResetClient(consume: .success("reset"), read: .failure(.transport))
        let readFailureResult = await ResetRedemptionFlow(client: readFailure).redeem(
            creditID: "credit", idempotencyKey: "attempt-pending", previousUsage: previous, now: now
        )
        let readFailureCounts = await readFailure.callCounts()
        check(readFailureCounts == (0, 1), "a failed account preflight does not send a reset request")
        if case .preflightFailed = readFailureResult {} else { check(false, "failed preflight is reported before any reset request") }

        let wrongAccount = try makeUsage(
            fiveHour: 18, weekly: 67, now: now,
            fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400,
            accountID: "different-account"
        )
        let accountChangedClient = StubResetClient(consume: .success("reset"), read: .success(wrongAccount))
        let accountChangedResult = await ResetRedemptionFlow(client: accountChangedClient).redeem(
            creditID: "credit", idempotencyKey: "attempt-account-change", previousUsage: previous, now: now
        )
        let accountChangedCounts = await accountChangedClient.callCounts()
        check(accountChangedCounts == (0, 1), "a changed active account blocks consume after one preflight read")
        if case .accountChanged = accountChangedResult {} else { check(false, "account switch before consume is reported explicitly") }

        let missingAccount = try makeUsage(
            fiveHour: 18, weekly: 67, now: now,
            fiveHourResetOffset: 3_600, weeklyResetOffset: 86_400,
            accountID: nil
        )
        let missingAccountClient = StubResetClient(consume: .success("reset"), read: .success(previous))
        let missingAccountResult = await ResetRedemptionFlow(client: missingAccountClient).redeem(
            creditID: "credit", idempotencyKey: "attempt-missing-account", previousUsage: missingAccount, now: now
        )
        let missingAccountCounts = await missingAccountClient.callCounts()
        check(missingAccountCounts == (0, 0), "a missing account identity blocks all network operations")
        if case .accountIdentityUnavailable = missingAccountResult {} else { check(false, "missing account identity is explicit") }

        let acceptedThenUnreadable = StubResetClient(consume: .success("reset"), read: [
            .success(previous), .failure(.transport)
        ])
        let acceptedReadFailureResult = await ResetRedemptionFlow(client: acceptedThenUnreadable).redeem(
            creditID: "credit", idempotencyKey: "attempt-refresh-pending", previousUsage: previous, now: now
        )
        let acceptedReadFailureCounts = await acceptedThenUnreadable.callCounts()
        check(acceptedReadFailureCounts == (1, 2), "an accepted reset performs account preflight before a failed post-consume refresh")
        if case .refreshPending = acceptedReadFailureResult {} else { check(false, "accepted redemption with failed post-consume read is reported as refresh pending") }

        let switchedAfterConsume = StubResetClient(consume: .success("reset"), read: [
            .success(previous), .success(wrongAccount)
        ])
        let switchedAfterConsumeResult = await ResetRedemptionFlow(client: switchedAfterConsume).redeem(
            creditID: "credit", idempotencyKey: "attempt-post-account-change", previousUsage: previous, now: now
        )
        let switchedAfterConsumeCounts = await switchedAfterConsume.callCounts()
        check(switchedAfterConsumeCounts == (1, 2), "post-consume account changes are detected after the idempotent request")
        if case .refreshPending = switchedAfterConsumeResult {} else { check(false, "a response read from another account cannot falsely confirm a reset") }

        print("RESET REDEMPTION FLOW PASS: \(assertions) assertions; account preflight, account-scope safety, mock consume and fresh-read paths")
    }

    private static func makeUsage(
        fiveHour: Int,
        weekly: Int,
        now: Date,
        fiveHourResetOffset: TimeInterval,
        weeklyResetOffset: TimeInterval,
        accountID: String? = "flow-test-account"
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
    private let readResults: [Result<UsageSummary, FixtureError>]
    private var consumeCallCount = 0
    private var readCallCount = 0

    init(consume: Result<String, FixtureError>, read: Result<UsageSummary, FixtureError>) {
        consumeResult = consume
        readResults = [read]
    }

    init(consume: Result<String, FixtureError>, read: [Result<UsageSummary, FixtureError>]) {
        consumeResult = consume
        readResults = read.isEmpty ? [.failure(.transport)] : read
    }

    func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String {
        consumeCallCount += 1
        return try consumeResult.get()
    }

    func fetchUsage() async throws -> UsageSummary {
        readCallCount += 1
        let index = min(readCallCount - 1, readResults.count - 1)
        return try readResults[index].get()
    }

    func callCounts() -> (Int, Int) { (consumeCallCount, readCallCount) }
}

private enum FixtureError: Error, LocalizedError, Sendable {
    case transport

    var errorDescription: String? { "Synthetic transport failure" }
}
