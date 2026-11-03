import Foundation

struct UsageBadgeAnimationFrame: Equatable, Sendable {
    let fiveHourPercent: Double
    let weeklyPercent: Double
    let resetWindows: Set<UsageWindowKind>
    let resetHighlightAlpha: Double
    let isComplete: Bool
}

struct UsageBadgeTransition: Sendable {
    static let frameInterval: TimeInterval = 1.0 / 60.0

    let fromFiveHour: Double
    let fromWeekly: Double
    let toFiveHour: Double
    let toWeekly: Double
    let startUptime: TimeInterval
    let duration: TimeInterval
    let resetWindows: Set<UsageWindowKind>
    let isConfirmedReset: Bool

    var shouldAnimate: Bool {
        isConfirmedReset
            || abs(fromFiveHour - toFiveHour) >= 0.01
            || abs(fromWeekly - toWeekly) >= 0.01
    }

    init(
        fromFiveHour: Double,
        fromWeekly: Double,
        toFiveHour: Double,
        toWeekly: Double,
        startUptime: TimeInterval,
        resetWindows: Set<UsageWindowKind> = [],
        isConfirmedReset: Bool = false
    ) {
        self.fromFiveHour = Self.clamp(fromFiveHour)
        self.fromWeekly = Self.clamp(fromWeekly)
        self.toFiveHour = Self.clamp(toFiveHour)
        self.toWeekly = Self.clamp(toWeekly)
        self.startUptime = startUptime
        let confirmedReset = isConfirmedReset || !resetWindows.isEmpty
        self.isConfirmedReset = confirmedReset
        duration = confirmedReset ? 0.92 : 0.36
        self.resetWindows = resetWindows
    }

    func frame(at uptime: TimeInterval) -> UsageBadgeAnimationFrame {
        let elapsed = max(0, uptime - startUptime)
        let linearProgress = elapsed >= duration - 0.000_001 ? 1 : min(1, elapsed / duration)
        let easedProgress = 1 - pow(1 - linearProgress, 3)
        let resetAlpha: Double
        if !isConfirmedReset {
            resetAlpha = 0
        } else {
            let fadeStart = 0.78
            resetAlpha = linearProgress <= fadeStart
                ? 1
                : max(0, 1 - (linearProgress - fadeStart) / (1 - fadeStart))
        }

        return UsageBadgeAnimationFrame(
            fiveHourPercent: interpolate(fromFiveHour, toFiveHour, easedProgress),
            weeklyPercent: interpolate(fromWeekly, toWeekly, easedProgress),
            resetWindows: resetWindows,
            resetHighlightAlpha: resetAlpha,
            isComplete: linearProgress >= 1
        )
    }

    private func interpolate(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }

    private static func clamp(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        return min(100, max(0, percent))
    }
}
