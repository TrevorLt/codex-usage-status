import Foundation

enum AppConfig {
    static let defaultCodexPath = "/Applications/Codex.app/Contents/Resources/codex"
    static let minimumRefreshInterval: TimeInterval = 30
    static let intermediateRefreshInterval: TimeInterval = 60
    static let intermediateRefreshAfterSeconds: TimeInterval = 90
    static let defaultRefreshInterval: TimeInterval = 120
    static let maximumRefreshInterval: TimeInterval = 120
    static let maximumRefreshAfterSeconds: TimeInterval = 300
    static let errorRetryInterval: TimeInterval = 300
    static let timerToleranceRatio: Double = 0.1
    static let windowResetDetectionRatio: Double = 0.8
    static let rawUsageChangeEpsilon: Double = 1e-9
    static let appServerTimeout: DispatchTimeInterval = .seconds(20)
}

func configuredRefreshInterval() -> TimeInterval {
    configuredRefreshIntervalOverride() ?? AppConfig.defaultRefreshInterval
}

func configuredRefreshIntervalOverride() -> TimeInterval? {
    configuredRefreshIntervalOverride(
        environmentValue: ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    )
}

func configuredRefreshIntervalOverride(environmentValue: String?) -> TimeInterval? {
    guard
        let environmentValue,
        let requested = Double(environmentValue),
        requested.isFinite
    else {
        return nil
    }

    return max(AppConfig.minimumRefreshInterval, requested)
}
