import Foundation

struct UsageRefreshSnapshot: Equatable, Sendable {
    let fiveHourUsedPercent: Double
    let weeklyUsedPercent: Double
    let fiveHourWindowDurationMins: Double?
    let weeklyWindowDurationMins: Double?
    let fiveHourResetsAt: Date?
    let weeklyResetsAt: Date?
    let credits: RateLimitCreditsSnapshot?

    init(_ usage: UsageSummary) {
        fiveHourUsedPercent = usage.fiveHour.rawUsedPercent
        weeklyUsedPercent = usage.weekly.rawUsedPercent
        fiveHourWindowDurationMins = usage.fiveHour.windowDurationMins
        weeklyWindowDurationMins = usage.weekly.windowDurationMins
        fiveHourResetsAt = usage.fiveHour.resetsAt
        weeklyResetsAt = usage.weekly.resetsAt
        credits = usage.credits
    }

    init(
        fiveHourRemaining: Int,
        weeklyRemaining: Int,
        fiveHourRawUsedPercent: Double? = nil,
        weeklyRawUsedPercent: Double? = nil,
        fiveHourWindowDurationMins: Double? = nil,
        weeklyWindowDurationMins: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        credits: RateLimitCreditsSnapshot? = nil
    ) {
        fiveHourUsedPercent = fiveHourRawUsedPercent ?? Double(100 - fiveHourRemaining)
        weeklyUsedPercent = weeklyRawUsedPercent ?? Double(100 - weeklyRemaining)
        self.fiveHourWindowDurationMins = fiveHourWindowDurationMins
        self.weeklyWindowDurationMins = weeklyWindowDurationMins
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyResetsAt = weeklyResetsAt
        self.credits = credits
    }
}

struct RefreshPolicy: Sendable {
    private let fixedIntervalOverride: TimeInterval?
    private var lastActivityAt: TimeInterval?

    private(set) var currentInterval: TimeInterval

    init(fixedIntervalOverride: TimeInterval? = configuredRefreshIntervalOverride()) {
        let validOverride = fixedIntervalOverride.flatMap { interval in
            interval.isFinite ? max(AppConfig.minimumRefreshInterval, interval) : nil
        }
        self.fixedIntervalOverride = validOverride
        currentInterval = validOverride ?? AppConfig.minimumRefreshInterval
    }

    mutating func nextInterval(
        previous: UsageRefreshSnapshot?,
        current: UsageRefreshSnapshot,
        now: TimeInterval
    ) -> TimeInterval {
        if let fixedIntervalOverride {
            currentInterval = fixedIntervalOverride
            return currentInterval
        }

        guard now.isFinite else {
            currentInterval = AppConfig.minimumRefreshInterval
            return currentInterval
        }

        if lastActivityAt == nil {
            lastActivityAt = now
        }

        if let previous, hasActivity(from: previous, to: current) {
            lastActivityAt = now
        }

        let elapsed = max(0, now - (lastActivityAt ?? now))
        if elapsed >= AppConfig.maximumRefreshAfterSeconds {
            currentInterval = AppConfig.maximumRefreshInterval
        } else if elapsed >= AppConfig.intermediateRefreshAfterSeconds {
            currentInterval = AppConfig.intermediateRefreshInterval
        } else {
            currentInterval = AppConfig.minimumRefreshInterval
        }

        return currentInterval
    }

    mutating func intervalAfterFailure() -> TimeInterval {
        currentInterval = AppConfig.errorRetryInterval
        return currentInterval
    }

    private func hasActivity(from previous: UsageRefreshSnapshot, to current: UsageRefreshSnapshot) -> Bool {
        previous.credits != current.credits
            || rawUsageChanged(previous.fiveHourUsedPercent, current.fiveHourUsedPercent)
            || rawUsageChanged(previous.weeklyUsedPercent, current.weeklyUsedPercent)
            || windowDidCycle(
                previousResetsAt: previous.fiveHourResetsAt,
                currentResetsAt: current.fiveHourResetsAt,
                previousDurationMins: previous.fiveHourWindowDurationMins,
                currentDurationMins: current.fiveHourWindowDurationMins
            )
            || windowDidCycle(
                previousResetsAt: previous.weeklyResetsAt,
                currentResetsAt: current.weeklyResetsAt,
                previousDurationMins: previous.weeklyWindowDurationMins,
                currentDurationMins: current.weeklyWindowDurationMins
            )
    }

    private func rawUsageChanged(_ previous: Double, _ current: Double) -> Bool {
        guard isValidUsage(previous), isValidUsage(current) else {
            return false
        }

        // Rising usage is consumption; falling usage signals a window reset or rebuilt baseline.
        return current > previous + AppConfig.rawUsageChangeEpsilon
            || current < previous - AppConfig.rawUsageChangeEpsilon
    }

    private func isValidUsage(_ value: Double) -> Bool {
        value.isFinite && (0...100).contains(value)
    }

    private func windowDidCycle(
        previousResetsAt: Date?,
        currentResetsAt: Date?,
        previousDurationMins: Double?,
        currentDurationMins: Double?
    ) -> Bool {
        guard
            let previousResetsAt,
            let currentResetsAt,
            let durationMins = currentDurationMins ?? previousDurationMins,
            durationMins.isFinite,
            durationMins > 0
        else {
            return false
        }

        let resetAdvance = currentResetsAt.timeIntervalSince(previousResetsAt)
        return resetAdvance >= durationMins * 60 * AppConfig.windowResetDetectionRatio
    }
}
