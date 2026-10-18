import Foundation
import Darwin

enum LoginItemControllerError: LocalizedError {
    case invalidExistingProfile
    case unableToWriteProfile
    case launchctlFailed

    var errorDescription: String? {
        switch self {
        case .invalidExistingProfile:
            return "The existing Codex Usage Status login configuration is invalid."
        case .unableToWriteProfile:
            return "Codex Usage Status could not update its login configuration."
        case .launchctlFailed:
            return "macOS could not update the Launch at Login setting."
        }
    }
}

struct LoginItemController {
    static let label = "dev.local.CodexUsageStatus"

    private let fileManager: FileManager
    private let plistURL: URL
    private let executablePath: String
    private let launchctlURL: URL
    private let domain: String

    init(
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        executablePath: String = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "",
        launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl"),
        userID: uid_t = getuid(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.plistURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
        self.executablePath = executablePath
        self.launchctlURL = launchctlURL
        self.domain = "gui/\(userID)"
    }

    var isEnabled: Bool {
        guard fileManager.fileExists(atPath: plistURL.path) else { return false }
        guard let profile = try? readProfile() else { return false }
        return profile["Label"] as? String == Self.label
            && profile["RunAtLoad"] as? Bool == true
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private func enable() throws {
        guard !executablePath.isEmpty else { throw LoginItemControllerError.invalidExistingProfile }

        let hadProfile = fileManager.fileExists(atPath: plistURL.path)
        let originalData = hadProfile ? fileManager.contents(atPath: plistURL.path) : nil
        var profile = try loadProfileOrCreate()
        profile["Label"] = Self.label

        var arguments = profile["ProgramArguments"] as? [String] ?? []
        if arguments.isEmpty {
            arguments = [executablePath]
        } else {
            arguments[0] = executablePath
        }
        profile["ProgramArguments"] = arguments
        profile["RunAtLoad"] = true
        profile["KeepAlive"] = true

        do {
            try writeProfile(profile)
            if !isLoaded {
                guard runLaunchctl(["bootstrap", domain, plistURL.path]) == 0 else {
                    throw LoginItemControllerError.launchctlFailed
                }
            }
        } catch {
            restoreProfile(data: originalData, existed: hadProfile)
            throw error
        }
    }

    private func disable() throws {
        guard fileManager.fileExists(atPath: plistURL.path) else { return }
        let originalData = fileManager.contents(atPath: plistURL.path)

        // Remove the file before booting out the current job. If launchd stops
        // this process as the owner of the job, the disabled preference is
        // already durable and will not be recreated at the next login.
        do {
            try fileManager.removeItem(at: plistURL)
            if isLoaded, runLaunchctl(["bootout", "\(domain)/\(Self.label)"]) != 0 {
                throw LoginItemControllerError.launchctlFailed
            }
        } catch {
            restoreProfile(data: originalData, existed: true)
            throw error
        }
    }

    private func loadProfileOrCreate() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: plistURL.path) else {
            return [
                "Label": Self.label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "KeepAlive": true,
            ]
        }
        return try readProfile()
    }

    private func readProfile() throws -> [String: Any] {
        guard let data = fileManager.contents(atPath: plistURL.path),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let profile = propertyList as? [String: Any],
              profile["Label"] as? String == Self.label else {
            throw LoginItemControllerError.invalidExistingProfile
        }
        return profile
    }

    private func writeProfile(_ profile: [String: Any]) throws {
        let parent = plistURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            throw LoginItemControllerError.unableToWriteProfile
        }
    }

    private func restoreProfile(data: Data?, existed: Bool) {
        if existed, let data {
            try? data.write(to: plistURL, options: .atomic)
        } else {
            try? fileManager.removeItem(at: plistURL)
        }
    }

    private var isLoaded: Bool {
        runLaunchctl(["print", "\(domain)/\(Self.label)"]) == 0
    }

    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = launchctlURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
