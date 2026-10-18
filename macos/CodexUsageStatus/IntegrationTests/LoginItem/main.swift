import Foundation

@main
struct LoginItemAudit {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("codex-login-item-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("launchctl-loaded")
        let launchctl = root.appendingPathComponent("launchctl")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try writeMockLaunchctl(at: launchctl, state: state)

        let executable = "/Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus"
        let controller = LoginItemController(
            homeURL: home,
            executablePath: executable,
            launchctlURL: launchctl,
            userID: 501,
            fileManager: fileManager
        )
        let plistURL = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(LoginItemController.label).plist")

        var assertions = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            assertions += 1
        }

        check(!controller.isEnabled, "fresh controller starts disabled")
        try controller.setEnabled(true)
        check(controller.isEnabled, "enable creates a checked login profile")
        check(fileManager.fileExists(atPath: state.path), "enable bootstraps the LaunchAgent")
        var profile = try readProfile(at: plistURL)
        check(profile["Label"] as? String == LoginItemController.label, "profile label")
        check((profile["ProgramArguments"] as? [String])?.first == executable, "profile executable")
        check(profile["RunAtLoad"] as? Bool == true, "profile RunAtLoad")
        check(profile["KeepAlive"] as? Bool == true, "profile KeepAlive")

        try controller.setEnabled(false)
        check(!controller.isEnabled, "disable clears the checked login profile")
        check(!fileManager.fileExists(atPath: plistURL.path), "disable removes the profile")
        check(!fileManager.fileExists(atPath: state.path), "disable boots out the LaunchAgent")

        profile = [
            "Label": LoginItemController.label,
            "ProgramArguments": ["/old/CodexUsageStatus", "preserve-this-argument"],
            "RunAtLoad": false,
            "KeepAlive": false,
            "EnvironmentVariables": ["CODEX_BIN": "/custom/codex/bin"],
        ]
        try writeProfile(profile, to: plistURL)
        try fileManager.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: state.path, contents: Data())
        try controller.setEnabled(true)
        let preservedProfile = try readProfile(at: plistURL)
        check((preservedProfile["ProgramArguments"] as? [String]) == [executable, "preserve-this-argument"],
              "enable updates only the executable argument")
        check((preservedProfile["EnvironmentVariables"] as? [String: String])?["CODEX_BIN"] == "/custom/codex/bin",
              "enable preserves custom Codex executable configuration")
        check(preservedProfile["RunAtLoad"] as? Bool == true && preservedProfile["KeepAlive"] as? Bool == true,
              "enable repairs disabled launch flags")

        print("LOGIN ITEM PASS: \(assertions) assertions")
    }

    private static func writeMockLaunchctl(at url: URL, state: URL) throws {
        let statePath = shellQuote(state.path)
        let script = """
        #!/bin/sh
        state=\(statePath)
        case "$1" in
          print) test -f "$state" ;;
          bootstrap) touch "$state" ;;
          bootout) rm -f "$state" ;;
          *) exit 1 ;;
        esac
        """
        try script.data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func readProfile(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw AuditError.invalidProfile
        }
        return propertyList
    }

    private static func writeProfile(_ profile: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum AuditError: Error {
    case invalidProfile
}
