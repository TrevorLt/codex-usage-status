import XCTest
@testable import CodexUsageStatus

final class CodexPathResolverTests: XCTestCase {
    func testEmptyEnvironmentDoesNotOverrideKnownInstallLocations() {
        let candidates = CodexPathResolver.candidatePaths(
            environmentValue: "   ",
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )

        XCTAssertTrue(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"))
        XCTAssertTrue(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"))
    }

    func testConfiguredEnvironmentPathIsTriedFirst() {
        let candidates = CodexPathResolver.candidatePaths(
            environmentValue: "/custom/Codex.app/Contents/Resources/codex",
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )

        XCTAssertEqual(candidates.first, "/custom/Codex.app/Contents/Resources/codex")
    }

    func testFirstExecutablePathSkipsMissingCandidates() {
        let path = CodexPathResolver.firstExecutablePath(
            in: ["/missing/codex", "/working/codex", "/later/codex"],
            isExecutable: { $0 == "/working/codex" }
        )

        XCTAssertEqual(path, "/working/codex")
    }
}
