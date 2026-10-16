import Foundation

struct RateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: TimeInterval?
}

struct UsageSummary: Sendable {
    let limitId: String?
    let planType: String?
    let fiveHour: UsageWindow
    let weekly: UsageWindow

    init(response: RateLimitsResponse) throws {
        let snapshot = response.rateLimitsByLimitId?["codex"]
            ?? response.rateLimits

        guard let snapshot else {
            throw FetchError.invalidOutput
        }

        let windows = try [snapshot.primary, snapshot.secondary].compactMap { $0 }.map(UsageWindow.init)
        let fiveHour = windows.first { approximately($0.windowDurationMins, 300) }
        let weekly = windows.first { approximately($0.windowDurationMins, 10080) }

        guard let fiveHour, let weekly else {
            throw FetchError.invalidOutput
        }

        self.limitId = snapshot.limitId
        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    var menuTitle: String {
        "5h \(fiveHour.remainingPercent)% 7d \(weekly.remainingPercent)%"
    }

    var verboseTitle: String {
        "Codex usage: 5-hour \(fiveHour.remainingPercent)% · weekly \(weekly.remainingPercent)%"
    }

    func tooltip(formatter: DateFormatter, now: Date = Date()) -> String {
        let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        let fiveHourReading = fiveHour.isExpired(at: now) ? "unknown (previous window expired)" : "\(fiveHour.remainingPercent)%"
        let weeklyReading = weekly.isExpired(at: now) ? "unknown (previous window expired)" : "\(weekly.remainingPercent)%"
        return "Codex usage\n5-hour remaining: \(fiveHourReading) · resets \(fiveHourReset)\nWeekly remaining: \(weeklyReading) · resets \(weeklyReset)"
    }
}

struct UsageWindow: Sendable {
    let rawUsedPercent: Double
    let remainingPercent: Int
    let windowDurationMins: Double?
    let resetsAt: Date?

    init(_ window: RateLimitWindow) throws {
        guard let used = window.usedPercent, used.isFinite, (0...100).contains(used),
              let duration = window.windowDurationMins, duration.isFinite, duration > 0,
              window.resetsAt.map({ $0.isFinite }) ?? true else {
            throw FetchError.invalidOutput
        }
        rawUsedPercent = used
        remainingPercent = min(100, max(0, Int((100 - used).rounded())))
        windowDurationMins = window.windowDurationMins
        resetsAt = window.resetsAt.map { Date(timeIntervalSince1970: $0) }
    }

    func isExpired(at date: Date) -> Bool {
        resetsAt.map { $0 <= date } ?? false
    }

    func displayText(formatter: DateFormatter) -> String {
        guard let resetsAt else {
            return "\(remainingPercent)% remaining, reset unknown"
        }
        return "\(remainingPercent)% remaining, resets \(formatter.string(from: resetsAt))"
    }
}

private func approximately(_ value: Double?, _ target: Double) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - target) <= 1
}
