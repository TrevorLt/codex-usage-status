import Foundation
import CryptoKit

enum UsageWindowKind: Hashable, Sendable {
    case fiveHour
    case weekly
}

struct RateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCredits?
    let accountId: String?

    init(
        rateLimits: RateLimitSnapshot?,
        rateLimitsByLimitId: [String: RateLimitSnapshot]?,
        rateLimitResetCredits: RateLimitResetCredits? = nil,
        accountId: String? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
        self.accountId = accountId
    }
}

struct RateLimitResetCredits: Decodable, Sendable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]?
}

struct RateLimitResetCredit: Decodable, Sendable, Equatable {
    let id: String?
    let resetType: String?
    let status: String?
    let grantedAt: TimeInterval?
    let expiresAt: TimeInterval?
    let title: String?
    let description: String?

    var availableCodexExpiry: Date? {
        guard let id, !id.isEmpty,
              resetType == "codexRateLimits",
              status == "available",
              let expiresAt, expiresAt.isFinite else {
            return nil
        }
        return Date(timeIntervalSince1970: expiresAt)
    }
}

/// Expiration timestamps that About can show for each currently available reset.
/// Missing detail rows remain explicit so the UI never invents an expiration.
struct ResetCreditExpiryDetails: Sendable {
    let expirations: [Date?]

    init(credits summary: RateLimitResetCredits?) {
        guard let summary else {
            expirations = []
            return
        }

        let count = max(0, summary.availableCount)
        guard count > 0 else {
            expirations = []
            return
        }

        let knownExpirations = (summary.credits ?? [])
            .filter { $0.resetType == "codexRateLimits" && $0.status == "available" }
            .compactMap { credit -> Date? in
                guard let timestamp = credit.expiresAt, timestamp.isFinite else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }
            .sorted()
            .prefix(count)

        let known = Array(knownExpirations)
        expirations = known.map(Optional.some)
            + Array(repeating: nil, count: max(0, count - known.count))
    }

    func aboutLines(dateFormatter: DateFormatter) -> [String] {
        expirations.enumerated().map { index, expiry in
            let value = expiry.map { dateFormatter.string(from: $0) } ?? "expiration time unavailable"
            return "Reset \(index + 1): \(value)"
        }
    }
}

struct ResetExpiryReminder: Sendable {
    static let threshold: TimeInterval = 72 * 60 * 60

    let availableCount: Int
    let expiringCredits: [RateLimitResetCredit]
    let earliestKnownExpiry: Date?

    init?(
        credits summary: RateLimitResetCredits?,
        dismissedIDs: Set<String> = [],
        now: Date = Date()
    ) {
        guard let summary, summary.availableCount > 0 else {
            return nil
        }

        let detailedCredits = (summary.credits ?? [])
            .compactMap { credit -> (RateLimitResetCredit, Date)? in
                guard let expiry = credit.availableCodexExpiry, expiry > now else { return nil }
                return (credit, expiry)
            }
            .reduce(into: [String: (RateLimitResetCredit, Date)]()) { result, entry in
                guard let id = entry.0.id else { return }
                result[id] = entry
            }
            .values
            .sorted { $0.1 < $1.1 }
            .prefix(summary.availableCount)

        let detailed = Array(detailedCredits)
        availableCount = summary.availableCount
        let undismissed = detailed.filter { entry in
            guard let id = entry.0.id else { return false }
            return !dismissedIDs.contains(id)
        }
        earliestKnownExpiry = undismissed.first?.1
        expiringCredits = undismissed.compactMap { credit, expiry in
            guard expiry.timeIntervalSince(now) <= Self.threshold,
                  credit.id != nil else {
                return nil
            }
            return credit
        }
    }

    static func remainingTimeText(until expiry: Date, now: Date = Date()) -> String {
        let hours = max(1, Int(ceil(expiry.timeIntervalSince(now) / 3_600)))
        if hours >= 24 {
            let days = Int(ceil(Double(hours) / 24))
            return days == 1 ? "1 day" : "\(days) days"
        }
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    func menuTitle(dateFormatter: DateFormatter, now: Date = Date()) -> String {
        let count = expiringCredits.count
        if count == 1, let expiry = expiringCredits.first?.availableCodexExpiry {
            return "1 reset expires in \(Self.remainingTimeText(until: expiry, now: now))"
        }
        if count > 1, let expiry = expiringCredits.first?.availableCodexExpiry {
            return "\(count) resets expiring · earliest in \(Self.remainingTimeText(until: expiry, now: now))"
        }
        if let earliestKnownExpiry {
            let availableText = availableCount == 1 ? "1 reset available" : "\(availableCount) resets available"
            return "\(availableText) · earliest expires \(dateFormatter.string(from: earliestKnownExpiry))"
        }
        return availableCount == 1 ? "1 reset available" : "\(availableCount) resets available"
    }

    func nextDisplayTransition(after now: Date) -> Date? {
        let dates = expiringCredits.compactMap { credit -> Date? in
            guard let expiry = credit.availableCodexExpiry else { return nil }
            let remaining = expiry.timeIntervalSince(now)
            let transition: Date
            if remaining >= 24 * 60 * 60 {
                let days = ceil(remaining / (24 * 60 * 60))
                let nextBoundaryHours = days == 1 ? 23.0 : (days - 1) * 24.0
                transition = expiry.addingTimeInterval(-nextBoundaryHours * 60 * 60)
            } else {
                let hours = ceil(remaining / (60 * 60))
                transition = expiry.addingTimeInterval(-(hours - 1) * 60 * 60)
            }
            return transition > now ? transition : nil
        }
        return dates.min()
    }
}

struct ResetReminderFreshness {
    static func maximumAge(refreshInterval: TimeInterval) -> TimeInterval {
        min(86_400, max(120, refreshInterval * 2))
    }

    static func canPresent(
        lastRefreshDate: Date?,
        hasRefreshError: Bool,
        isAwaitingFreshRead: Bool,
        refreshInterval: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let lastRefreshDate, !hasRefreshError, !isAwaitingFreshRead else { return false }
        let age = now.timeIntervalSince(lastRefreshDate)
        return age >= 0 && age < maximumAge(refreshInterval: refreshInterval)
    }
}

struct ResetExpiryDismissalStore {
    private struct Entry: Codable, Sendable {
        let id: String
        let expiresAt: Date
    }

    private struct Record: Codable, Sendable {
        let accountFingerprint: String
        var entries: [Entry]
    }

    private static let defaultsKey = "ResetExpiryDismissals.v1"
    private static let maximumStoredIDs = 128
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func prepare(accountID: String?, now: Date = Date()) {
        guard let fingerprint = Self.fingerprint(for: accountID) else { return }
        var record = readRecord()
        if record?.accountFingerprint != fingerprint {
            record = Record(accountFingerprint: fingerprint, entries: [])
        }
        guard var record else { return }
        let pruned = record.entries.filter { $0.expiresAt > now }
        guard pruned.count != record.entries.count || readRecord()?.accountFingerprint != fingerprint else { return }
        record.entries = pruned
        write(record)
    }

    func dismissedIDs(accountID: String?, now: Date = Date()) -> Set<String> {
        guard let fingerprint = Self.fingerprint(for: accountID),
              let record = readRecord(),
              record.accountFingerprint == fingerprint else {
            return []
        }
        return Set(record.entries.filter { $0.expiresAt > now }.map(\.id))
    }

    func dismiss(_ credits: [RateLimitResetCredit], accountID: String?, now: Date = Date()) {
        guard let fingerprint = Self.fingerprint(for: accountID) else { return }
        let current = readRecord()
        var record: Record
        if let current, current.accountFingerprint == fingerprint {
            record = current
        } else {
            record = Record(accountFingerprint: fingerprint, entries: [])
        }
        var entries: [String: Entry] = [:]
        for entry in record.entries where entry.expiresAt > now {
            entries[entry.id] = entry
        }

        for credit in credits {
            guard let id = credit.id, !id.isEmpty,
                  let expiry = credit.availableCodexExpiry,
                  expiry > now,
                  expiry.timeIntervalSince(now) <= ResetExpiryReminder.threshold else { continue }
            entries[id] = Entry(id: id, expiresAt: expiry)
        }

        record.entries = Array(entries.values
            .sorted { $0.expiresAt < $1.expiresAt }
            .suffix(Self.maximumStoredIDs))
        write(record)
    }

    private func readRecord() -> Record? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func write(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func fingerprint(for accountID: String?) -> String? {
        guard let accountID, !accountID.isEmpty else { return nil }
        return SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct PendingResetConsumptionAttempt: Codable, Sendable, Equatable {
    let creditID: String?
    let idempotencyKey: String
    let accountFingerprint: String?

    func belongs(to accountID: String) -> Bool {
        guard let fingerprint = ResetExpiryDismissalStore.fingerprint(for: accountID) else { return false }
        return accountFingerprint == fingerprint
    }


}

@MainActor
final class ResetConsumptionAttemptStore {
    private static let defaultsKey = "PendingResetConsumptionAttempt.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pending: PendingResetConsumptionAttempt? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PendingResetConsumptionAttempt.self, from: data)
    }

    func begin(creditID: String?, accountID: String) -> PendingResetConsumptionAttempt? {
        guard !accountID.isEmpty else { return nil }
        if let pending {
            return pending.belongs(to: accountID) ? pending : nil
        }

        let pending = PendingResetConsumptionAttempt(
            creditID: creditID,
            idempotencyKey: UUID().uuidString,
            accountFingerprint: ResetExpiryDismissalStore.fingerprint(for: accountID)
        )
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        return pending
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
    let credits: RateLimitCreditsSnapshot?

    init(
        limitId: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        planType: String?,
        credits: RateLimitCreditsSnapshot? = nil
    ) {
        self.limitId = limitId
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.credits = credits
    }
}

struct RateLimitCreditsSnapshot: Decodable, Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasCredits == rhs.hasCredits
            && lhs.unlimited == rhs.unlimited
            && lhs.decimalBalance == rhs.decimalBalance
    }

    var decimalBalance: Decimal? {
        guard hasCredits,
              let balance,
              let value = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else {
            return nil
        }
        return value
    }

    var availabilityDescription: String? {
        if unlimited { return "Unlimited credits available" }
        guard hasCredits else { return nil }
        guard var balance = decimalBalance else { return "Credits available" }
        guard balance > 0 else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &balance, 3, .plain)
        let formattedBalance = rounded > 0 ? NSDecimalNumber(decimal: rounded).stringValue : "<0.001"
        return "\(formattedBalance) credits available"
    }
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: TimeInterval?
}

struct UsageSummary: Sendable {
    let limitId: String?
    let planType: String?
    let accountID: String?
    let credits: RateLimitCreditsSnapshot?
    let resetCredits: RateLimitResetCredits?
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
        self.accountID = response.accountId
        self.credits = snapshot.credits
        self.resetCredits = response.rateLimitResetCredits
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

    func hoverTooltip(
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        showingLastKnownReadings: Bool = false
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "MM/dd"

        let fiveHourText = hoverFiveHourResetText(
            fiveHour.resetsAt,
            now: now,
            calendar: calendar,
            timeFormatter: timeFormatter,
            dateFormatter: dateFormatter
        )
        let weeklyText = hoverWeeklyResetText(weekly.resetsAt, now: now, timeFormatter: timeFormatter, dateFormatter: dateFormatter)
        var lines = [
            hoverLine(label: "5h", value: fiveHourText),
            hoverLine(label: "7-day", value: weeklyText),
        ]
        if fiveHour.remainingPercent == 0, !fiveHour.isExpired(at: now),
           let creditDescription = credits?.availabilityDescription {
            lines.append(creditDescription)
        }
        if showingLastKnownReadings {
            lines.append("Showing last known readings")
        }
        return lines.joined(separator: "\n")
    }

    private func hoverFiveHourResetText(
        _ resetAt: Date?,
        now: Date,
        calendar: Calendar,
        timeFormatter: DateFormatter,
        dateFormatter: DateFormatter
    ) -> String {
        guard let resetAt else { return "reset time unknown" }
        guard resetAt > now else { return "expired" }

        let time = timeFormatter.string(from: resetAt)
        let datePrefix: String
        if calendar.isDate(resetAt, inSameDayAs: now) {
            datePrefix = time
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  calendar.isDate(resetAt, inSameDayAs: tomorrow) {
            datePrefix = "Tomorrow \(time)"
        } else {
            datePrefix = "\(dateFormatter.string(from: resetAt)) \(time)"
        }
        return "\(datePrefix) · \(relativeDuration(until: resetAt, now: now))"
    }

    private func hoverWeeklyResetText(
        _ resetAt: Date?,
        now: Date,
        timeFormatter: DateFormatter,
        dateFormatter: DateFormatter
    ) -> String {
        guard let resetAt else { return "reset time unknown" }
        guard resetAt > now else { return "expired" }
        return "\(dateFormatter.string(from: resetAt)) \(timeFormatter.string(from: resetAt))"
    }

    private func relativeDuration(until resetAt: Date, now: Date) -> String {
        let remainingMinutes = max(0, Int(floor((resetAt.timeIntervalSince(now) + 0.001) / 60)))
        let days = remainingMinutes / (24 * 60)
        let hours = (remainingMinutes % (24 * 60)) / 60
        let minutes = remainingMinutes % 60

        if days > 0 {
            return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h"
        }
        return minutes > 0 ? "in \(minutes)m" : "in <1m"
    }

    private func hoverLine(label: String, value: String) -> String {
        "\(label) · \(value)"
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
