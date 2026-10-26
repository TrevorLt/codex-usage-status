import Foundation

@main
struct NativeFaultsHarness {
    static func main() async {
        do {
            if CommandLine.arguments.dropFirst().first == "consume" {
                let key = CommandLine.arguments[2]
                let creditID = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
                let outcome = try await CodexUsageFetcher.consumeReset(creditID: creditID, idempotencyKey: key)
                print("CONSUME SUCCESS: \(outcome)")
            } else {
                let summary = try CodexUsageFetcher.fetchSync()
                print("FETCH SUCCESS: \(summary.menuTitle)")
            }
            exit(0)
        } catch {
            print("FETCH ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }
}
