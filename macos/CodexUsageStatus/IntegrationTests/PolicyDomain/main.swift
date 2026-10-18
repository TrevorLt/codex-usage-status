import Foundation

enum FetchError: Error {
    case invalidOutput
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("POLICY DOMAIN FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectInvalidOutput<T>(_ message: String, _ operation: () throws -> T) {
    do {
        _ = try operation()
        expect(false, "\(message) was accepted")
    } catch is FetchError {
        expect(true, "\(message) should be rejected")
    } catch {
        expect(false, "\(message) threw an unexpected error: \(error)")
    }
}

private func window(
    used: Double? = 25,
    duration: Double? = 300,
    resetsAt: Double? = nil
) -> RateLimitWindow {
    RateLimitWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resetsAt)
}

private func snapshot(
    fiveHourUsed: Double = 30,
    weeklyUsed: Double = 50,
    fiveHourDuration: Double? = 300,
    weeklyDuration: Double? = 10_080,
    fiveHourReset: Date? = nil,
    weeklyReset: Date? = nil
) -> UsageRefreshSnapshot {
    UsageRefreshSnapshot(
        fiveHourRemaining: Int((100 - fiveHourUsed).rounded()),
        weeklyRemaining: Int((100 - weeklyUsed).rounded()),
        fiveHourRawUsedPercent: fiveHourUsed,
        weeklyRawUsedPercent: weeklyUsed,
        fiveHourWindowDurationMins: fiveHourDuration,
        weeklyWindowDurationMins: weeklyDuration,
        fiveHourResetsAt: fiveHourReset,
        weeklyResetsAt: weeklyReset
    )
}

private func policyInterval(
    _ policy: inout RefreshPolicy,
    previous: UsageRefreshSnapshot?,
    current: UsageRefreshSnapshot,
    now: TimeInterval
) -> TimeInterval {
    policy.nextInterval(previous: previous, current: current, now: now)
}

// Missing rate-limit data, fields, and required window durations must remain unknown.
expectInvalidOutput("missing rateLimits") {
    try UsageSummary(response: RateLimitsResponse(rateLimits: nil, rateLimitsByLimitId: nil))
}
expectInvalidOutput("missing usedPercent") {
    try UsageWindow(window(used: nil))
}
expectInvalidOutput("missing windowDurationMins") {
    try UsageWindow(window(duration: nil))
}
expectInvalidOutput("missing five-hour window") {
    try UsageSummary(response: RateLimitsResponse(
        rateLimits: RateLimitSnapshot(limitId: nil, primary: window(duration: 10_080), secondary: nil, planType: nil),
        rateLimitsByLimitId: nil
    ))
}
expectInvalidOutput("missing weekly window") {
    try UsageSummary(response: RateLimitsResponse(
        rateLimits: RateLimitSnapshot(limitId: nil, primary: window(duration: 300), secondary: nil, planType: nil),
        rateLimitsByLimitId: nil
    ))
}

// Window selection accepts the documented duration tolerance and is order-independent.
let selected = try UsageSummary(response: RateLimitsResponse(
    rateLimits: RateLimitSnapshot(
        limitId: "codex",
        primary: window(used: 35.5, duration: 10_081),
        secondary: window(used: 12.5, duration: 299),
        planType: "test"
    ),
    rateLimitsByLimitId: nil
))
expect(selected.fiveHour.rawUsedPercent == 12.5, "five-hour window was not selected by duration")
expect(selected.weekly.rawUsedPercent == 35.5, "weekly window was not selected by duration")
expect(selected.fiveHour.remainingPercent == 88, "half-percent rounding for five-hour use changed")
expect(selected.weekly.remainingPercent == 65, "half-percent rounding for weekly use changed")
let emptyWindow = try UsageWindow(window(used: 0))
let fullWindow = try UsageWindow(window(used: 100))
let unknownResetWindow = try UsageWindow(window(resetsAt: nil))
expect(emptyWindow.remainingPercent == 100, "zero usage should show 100% remaining")
expect(fullWindow.remainingPercent == 0, "full usage should show 0% remaining")
expect(unknownResetWindow.resetsAt == nil, "missing optional reset time should remain unknown")

// Non-finite values are rejected before conversion or date creation.
for invalid in [Double.nan, Double.infinity, -Double.infinity] {
    expectInvalidOutput("non-finite usedPercent") { try UsageWindow(window(used: invalid)) }
    expectInvalidOutput("non-finite duration") { try UsageWindow(window(duration: invalid)) }
    expectInvalidOutput("non-finite reset time") { try UsageWindow(window(resetsAt: invalid)) }
}
for invalid in [-0.01, 100.01] {
    expectInvalidOutput("out-of-range usedPercent") { try UsageWindow(window(used: invalid)) }
}

// The activity epsilon is applied to raw values, independently of integer display rounding.
let stable = snapshot(fiveHourUsed: 50, weeklyUsed: 40)
let belowEpsilon = snapshot(fiveHourUsed: 50 + AppConfig.rawUsageChangeEpsilon / 2, weeklyUsed: 40)
let aboveEpsilon = snapshot(fiveHourUsed: 50 + AppConfig.rawUsageChangeEpsilon * 2, weeklyUsed: 40)
var smallChangePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&smallChangePolicy, previous: nil, current: stable, now: 0) == 30, "initial policy interval should be 30 seconds")
expect(policyInterval(&smallChangePolicy, previous: stable, current: belowEpsilon, now: 90) == 60, "sub-epsilon raw change should not reset activity")
var meaningfulChangePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&meaningfulChangePolicy, previous: nil, current: stable, now: 0) == 30, "initial policy interval should be 30 seconds")
expect(policyInterval(&meaningfulChangePolicy, previous: stable, current: aboveEpsilon, now: 90) == 30, "above-epsilon raw change should reset activity")

// Stable readings move through the 30/60/120-second cadence at exact boundaries.
var cadencePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&cadencePolicy, previous: nil, current: stable, now: 0) == 30, "cadence should start at 30 seconds")
expect(policyInterval(&cadencePolicy, previous: stable, current: stable, now: 89) == 30, "cadence changed before 90 seconds")
expect(policyInterval(&cadencePolicy, previous: stable, current: stable, now: 90) == 60, "cadence should become 60 seconds at 90 seconds")
expect(policyInterval(&cadencePolicy, previous: stable, current: stable, now: 299) == 60, "cadence changed before 300 seconds")
expect(policyInterval(&cadencePolicy, previous: stable, current: stable, now: 300) == 120, "cadence should become 120 seconds at 300 seconds")
expect(policyInterval(&cadencePolicy, previous: stable, current: stable, now: .nan) == 30, "non-finite clock should fall back to 30 seconds")

// A cycle at 80% of the window duration resets the activity baseline.
let oldFiveHourReset = Date(timeIntervalSince1970: 20_000)
let priorCycle = snapshot(fiveHourReset: oldFiveHourReset)
let beforeCycleThreshold = snapshot(fiveHourReset: oldFiveHourReset.addingTimeInterval(14_399))
let atCycleThreshold = snapshot(fiveHourReset: oldFiveHourReset.addingTimeInterval(14_400))
var noCyclePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&noCyclePolicy, previous: nil, current: priorCycle, now: 0) == 30, "cycle test should start at 30 seconds")
expect(policyInterval(&noCyclePolicy, previous: priorCycle, current: beforeCycleThreshold, now: 300) == 120, "early reset-time movement should not count as a cycle")
var cyclePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&cyclePolicy, previous: nil, current: priorCycle, now: 0) == 30, "cycle test should start at 30 seconds")
expect(policyInterval(&cyclePolicy, previous: priorCycle, current: atCycleThreshold, now: 300) == 30, "window cycle should rebuild the activity baseline")

// Failures use the fixed five-minute retry interval.
var failurePolicy = RefreshPolicy(fixedIntervalOverride: nil)
expect(policyInterval(&failurePolicy, previous: nil, current: stable, now: 0) == 30, "failure test should start at 30 seconds")
expect(failurePolicy.intervalAfterFailure() == 300, "failure retry should be 300 seconds")
expect(failurePolicy.currentInterval == 300, "failure retry should update currentInterval")

// Environment and direct overrides reject malformed/non-finite values; low finite values clamp to 30.
expect(configuredRefreshIntervalOverride(environmentValue: nil) == nil, "missing override should be ignored")
expect(configuredRefreshIntervalOverride(environmentValue: "invalid") == nil, "malformed override should be ignored")
expect(configuredRefreshIntervalOverride(environmentValue: "NaN") == nil, "NaN override should be ignored")
expect(configuredRefreshIntervalOverride(environmentValue: "infinity") == nil, "infinite override should be ignored")
expect(configuredRefreshIntervalOverride(environmentValue: "15") == 30, "sub-minimum override should clamp to 30 seconds")
expect(configuredRefreshIntervalOverride(environmentValue: "42.5") == 42.5, "valid fractional override should be retained")
var invalidDirectOverride = RefreshPolicy(fixedIntervalOverride: .infinity)
expect(policyInterval(&invalidDirectOverride, previous: nil, current: stable, now: 0) == 30, "non-finite direct override should use automatic policy")

print("POLICY DOMAIN PASS")
