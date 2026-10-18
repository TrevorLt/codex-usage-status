import Foundation

enum AppConfig {
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

enum CodexPathResolver {
    private static let applicationNames = ["Codex.app", "ChatGPT.app"]
    private static let relativeExecutablePaths = [
        "Contents/Resources/codex",
        "Contents/Resources/codex-cli/bin/codex",
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/CodexCLI.app/Contents/MacOS/codex"
    ]

    static func candidatePaths(
        environmentValue: String? = ProcessInfo.processInfo.environment["CODEX_BIN"],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        var candidates: [String] = []

        if let environmentValue {
            let trimmed = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                candidates.append((trimmed as NSString).expandingTildeInPath)
            }
        }

        let applicationRoots = [
            URL(fileURLWithPath: "/Applications"),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in applicationRoots {
            for applicationName in applicationNames {
                let applicationURL = root.appendingPathComponent(applicationName, isDirectory: true)
                for relativePath in relativeExecutablePaths {
                    candidates.append(applicationURL.appendingPathComponent(relativePath).path)
                }
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    static func firstExecutablePath(
        in candidates: [String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidates.first(where: isExecutable)
    }
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
