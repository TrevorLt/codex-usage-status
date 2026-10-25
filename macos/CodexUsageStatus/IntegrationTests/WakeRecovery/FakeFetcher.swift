import Foundation

enum FetchError: Error { case invalidOutput }

@MainActor
enum CodexUsageFetcher {
    static var shouldFail = false
    static var fiveHourResetOffset: TimeInterval = 3_600
    static var fiveHourUsedPercent = 35.1
    static var resetCreditID = "synthetic-credit-1"
    static var resetExpiryOffset: TimeInterval = 3_600
    static var resetAvailableCount = 1
    static var resetConsumeOutcome = "reset"
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

    static func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String {
        resetConsumeCount += 1
        lastConsumedCreditID = creditID
        lastResetIdempotencyKey = idempotencyKey
        return resetConsumeOutcome
    }

    static func fixture(missingUsed: Bool = false, weeklyOnly: Bool = false) throws -> UsageSummary {
        let now = Date().timeIntervalSince1970
        let used = missingUsed ? "null" : String(fiveHourUsedPercent)
        let primary = weeklyOnly ? "null" : """
        {"usedPercent":\(used),"windowDurationMins":300,"resetsAt":\(now + fiveHourResetOffset)}
        """
        let json = """
        {"accountId":"synthetic-account","rateLimitResetCredits":{"availableCount":\(resetAvailableCount),"credits":[{"id":"\(resetCreditID)","resetType":"codexRateLimits","status":"available","grantedAt":\(now - 1_000),"expiresAt":\(now + resetExpiryOffset)}]},"rateLimits":{"limitId":"codex","primary":\(primary),"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":\(now + 86_400)}}}
        """
        return try UsageSummary(response: JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8)))
    }
}
