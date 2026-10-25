import Foundation

/// The two service operations needed by a user-confirmed reset redemption.
/// Tests and previews inject a local fake; the app uses the Codex app-server adapter.
protocol ResetRedemptionClient: Sendable {
    func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String
    func fetchUsage() async throws -> UsageSummary
}

struct CodexResetRedemptionClient: ResetRedemptionClient {
    func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String {
        try await CodexUsageFetcher.consumeReset(creditID: creditID, idempotencyKey: idempotencyKey)
    }

    func fetchUsage() async throws -> UsageSummary {
        try await CodexUsageFetcher.fetch()
    }
}

enum ResetRedemptionResult: Sendable {
    case confirmed(usage: UsageSummary, changedWindows: Set<UsageWindowKind>)
    case nothingToReset
    case noCredit
    case preflightFailed(message: String)
    case accountChanged
    case accountIdentityUnavailable
    case refreshPending(message: String)
    case statusUnclear(message: String)
}

struct ResetRedemptionFlowError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ResetRedemptionFlow: Sendable {
    private let client: any ResetRedemptionClient

    init(client: any ResetRedemptionClient) {
        self.client = client
    }

    func redeem(
        creditID: String?,
        idempotencyKey: String,
        previousUsage: UsageSummary?,
        now: Date = Date()
    ) async -> ResetRedemptionResult {
        guard let expectedAccountID = previousUsage?.accountID, !expectedAccountID.isEmpty else {
            return .accountIdentityUnavailable
        }

        do {
            let currentUsage = try await client.fetchUsage()
            guard currentUsage.accountID == expectedAccountID else { return .accountChanged }
        } catch {
            return .preflightFailed(message: error.localizedDescription)
        }

        let outcome: String
        do {
            outcome = try await client.consumeReset(creditID: creditID, idempotencyKey: idempotencyKey)
        } catch {
            return .statusUnclear(message: error.localizedDescription)
        }

        switch outcome {
        case "reset", "alreadyRedeemed":
            do {
                let currentUsage = try await client.fetchUsage()
                guard currentUsage.accountID == expectedAccountID else {
                    return .refreshPending(message: "Codex switched accounts after the reset request was sent. Switch back to the account that confirmed the reset and retry to check the same request safely.")
                }
                return .confirmed(
                    usage: currentUsage,
                    changedWindows: Self.changedWindows(from: previousUsage, to: currentUsage, now: now)
                )
            } catch {
                return .refreshPending(message: error.localizedDescription)
            }
        case "nothingToReset":
            return .nothingToReset
        case "noCredit":
            return .noCredit
        default:
            return .statusUnclear(message: "Codex returned an unrecognized reset result.")
        }
    }

    private static func changedWindows(from previous: UsageSummary?, to current: UsageSummary, now: Date) -> Set<UsageWindowKind> {
        guard let previous else { return [] }
        var changed = Set<UsageWindowKind>()
        if indicatesReset(from: previous.fiveHour, to: current.fiveHour, now: now) {
            changed.insert(.fiveHour)
        }
        if indicatesReset(from: previous.weekly, to: current.weekly, now: now) {
            changed.insert(.weekly)
        }
        return changed
    }

    private static func indicatesReset(from previous: UsageWindow, to current: UsageWindow, now: Date) -> Bool {
        guard !previous.isExpired(at: now), !current.isExpired(at: now) else { return false }
        let usageRecovered = current.remainingPercent - previous.remainingPercent >= 10
        let resetAdvanced: Bool
        if let previousReset = previous.resetsAt,
           let currentReset = current.resetsAt,
           let durationMins = current.windowDurationMins ?? previous.windowDurationMins,
           durationMins.isFinite, durationMins > 0 {
            resetAdvanced = currentReset.timeIntervalSince(previousReset)
                >= durationMins * 60 * AppConfig.windowResetDetectionRatio
        } else {
            resetAdvanced = false
        }
        return usageRecovered || resetAdvanced
    }
}
