import Foundation

struct UsageRefreshSnapshot: Equatable, Sendable {
    let fiveHourRemaining: Int
    let weeklyRemaining: Int

    init(_ usage: UsageSummary) {
        fiveHourRemaining = usage.fiveHour.remainingPercent
        weeklyRemaining = usage.weekly.remainingPercent
    }

    init(fiveHourRemaining: Int, weeklyRemaining: Int) {
        self.fiveHourRemaining = fiveHourRemaining
        self.weeklyRemaining = weeklyRemaining
    }
}

struct RefreshPolicy: Sendable {
    private let baseInterval: TimeInterval
    private let maximumInterval: TimeInterval
    private let fastInterval = AppConfig.minimumRefreshInterval
    private var lastSignificantDropAt: Date?

    private(set) var currentInterval: TimeInterval

    init(baseInterval: TimeInterval = configuredRefreshInterval()) {
        self.baseInterval = baseInterval
        maximumInterval = max(AppConfig.maximumRefreshInterval, baseInterval)
        currentInterval = baseInterval
    }

    mutating func nextInterval(
        previous: UsageRefreshSnapshot?,
        current: UsageRefreshSnapshot,
        now: Date
    ) -> TimeInterval {
        if let previous, largestDrop(from: previous, to: current) >= AppConfig.significantDropPercentagePoints {
            lastSignificantDropAt = now
            currentInterval = fastInterval
            return currentInterval
        }

        guard let lastSignificantDropAt else {
            currentInterval = baseInterval
            return currentInterval
        }

        if now.timeIntervalSince(lastSignificantDropAt) < AppConfig.stableBackoffInterval {
            currentInterval = fastInterval
            return currentInterval
        }

        currentInterval = min(maximumInterval, max(baseInterval, currentInterval * 2))
        return currentInterval
    }

    mutating func intervalAfterFailure() -> TimeInterval {
        currentInterval = AppConfig.errorRetryInterval
        return currentInterval
    }

    private func largestDrop(from previous: UsageRefreshSnapshot, to current: UsageRefreshSnapshot) -> Int {
        max(
            previous.fiveHourRemaining - current.fiveHourRemaining,
            previous.weeklyRemaining - current.weeklyRemaining
        )
    }
}
