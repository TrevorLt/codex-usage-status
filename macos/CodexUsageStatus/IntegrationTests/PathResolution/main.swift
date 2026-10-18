import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("PATH RESOLVER FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let candidates = CodexPathResolver.candidatePaths(
    environmentValue: "   ",
    homeDirectory: URL(fileURLWithPath: "/Users/example")
)
expect(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"), "legacy Codex path missing")
expect(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"), "ChatGPT embedded CLI path missing")
expect(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"), "ChatGPT nested app-server path missing")
expect(candidates.contains("/Users/example/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"), "per-user ChatGPT path missing")

let configured = CodexPathResolver.candidatePaths(
    environmentValue: "/custom/Codex.app/Contents/Resources/codex",
    homeDirectory: URL(fileURLWithPath: "/Users/example")
)
expect(configured.first == "/custom/Codex.app/Contents/Resources/codex", "configured path is not first")

let executable = CodexPathResolver.firstExecutablePath(
    in: ["/missing/codex", "/working/codex", "/later/codex"],
    isExecutable: { $0 == "/working/codex" }
)
expect(executable == "/working/codex", "missing candidates were not skipped")

print("PATH RESOLVER PASS")
