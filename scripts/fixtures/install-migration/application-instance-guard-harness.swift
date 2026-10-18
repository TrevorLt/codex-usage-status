import Foundation

@main
struct ApplicationInstanceGuardHarness {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "try" {
            let claim = try ApplicationInstanceGuard.acquire(
                lockFileURL: URL(fileURLWithPath: CommandLine.arguments[2])
            )
            exit(claim == nil ? 17 : 0)
        }

        guard CommandLine.arguments.count == 2 else {
            fputs("expected a lock file path\n", stderr)
            exit(2)
        }
        let lockURL = URL(fileURLWithPath: CommandLine.arguments[1])
        var heldClaim = try ApplicationInstanceGuard.acquire(lockFileURL: lockURL)
        guard heldClaim != nil else {
            fputs("first claim unexpectedly contended\n", stderr)
            exit(3)
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let contender = Process()
        contender.executableURL = executable
        contender.arguments = ["try", lockURL.path]
        try contender.run()
        contender.waitUntilExit()
        guard contender.terminationStatus == 17 else {
            fputs("second process acquired the held lock\n", stderr)
            exit(4)
        }

        heldClaim = nil
        let replacement = Process()
        replacement.executableURL = executable
        replacement.arguments = ["try", lockURL.path]
        try replacement.run()
        replacement.waitUntilExit()
        guard replacement.terminationStatus == 0 else {
            fputs("lock was not released when its owner exited\n", stderr)
            exit(5)
        }
        print("APPLICATION INSTANCE GUARD PASS")
    }
}
