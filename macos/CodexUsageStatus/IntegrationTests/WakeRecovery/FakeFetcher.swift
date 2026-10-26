import Foundation

enum FetchError: Error { case invalidOutput }

@MainActor
enum CodexUsageFetcher {
    static var shouldFail = false
    static var fiveHourResetOffset: TimeInterval = 3_600
    static var fiveHourUsedPercent = 35.1
    static var resetCreditID = "synthetic-credit-1"
    static var resetExpiryOffset: TimeInterval = 3_600
    static var hasResetExpiry = true
    static var resetAvailableCount = 1
    static var resetConsumeOutcome = "reset"
    static var resetConsumeShouldFail = false
    static var failReadAfterConsume = false
    static var suspendReadAfterConsume = false
    static var resetConsumeCount = 0
    static var lastConsumedCreditID: String?
    static var lastResetIdempotencyKey: String?
    static var count = 0
    static var clockOffset: TimeInterval = 0
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime + clockOffset }
    static var suspendNext = false
    static var continuation: CheckedContinuation<Void, Never>?

    static func fetch() async throws -> UsageSummary {
        count += 1
        let failThisAttempt = shouldFail
        if suspendNext {
            suspendNext = false
            await withCheckedContinuation { continuation = $0 }
        }
        if failThisAttempt { throw FetchError.invalidOutput }
        return try fixture()
    }

    static func consumeReset(creditID: String, idempotencyKey: String) async throws -> String {
        resetConsumeCount += 1
        lastConsumedCreditID = creditID
        lastResetIdempotencyKey = idempotencyKey
        if resetConsumeShouldFail { throw FetchError.invalidOutput }
        fiveHourUsedPercent = 0
        resetAvailableCount = max(0, resetAvailableCount - 1)
        if failReadAfterConsume { shouldFail = true }
        if suspendReadAfterConsume { suspendNext = true }
        return resetConsumeOutcome
    }

    static func fixture(missingUsed: Bool = false, weeklyOnly: Bool = false) throws -> UsageSummary {
        let now = Date().timeIntervalSince1970
        let used = missingUsed ? "null" : String(fiveHourUsedPercent)
        let expiry = hasResetExpiry ? String(now + resetExpiryOffset) : "null"
        let primary = weeklyOnly ? "null" : """
        {"usedPercent":\(used),"windowDurationMins":300,"resetsAt":\(now + fiveHourResetOffset)}
        """
        let json = """
        {"accountId":"synthetic-account","rateLimitResetCredits":{"availableCount":\(resetAvailableCount),"credits":[{"id":"\(resetCreditID)","resetType":"codexRateLimits","status":"available","grantedAt":\(now - 1_000),"expiresAt":\(expiry)}]},"rateLimits":{"limitId":"codex","primary":\(primary),"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":\(now + 86_400)}}}
        """
        return try UsageSummary(response: JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8)))
    }
}
