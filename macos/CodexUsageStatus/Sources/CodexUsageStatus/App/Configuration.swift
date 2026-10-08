import Foundation

enum AppConfig {
    static let defaultCodexPath = "/Applications/Codex.app/Contents/Resources/codex"
    static let minimumRefreshInterval: TimeInterval = 30
    static let defaultRefreshInterval: TimeInterval = 120
    static let maximumRefreshInterval: TimeInterval = 300
    static let significantDropPercentagePoints = 5
    static let stableBackoffInterval: TimeInterval = 60
    static let errorRetryInterval: TimeInterval = 300
    static let appServerTimeout: DispatchTimeInterval = .seconds(20)
}

func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? AppConfig.defaultRefreshInterval
    return max(AppConfig.minimumRefreshInterval, requested)
}
