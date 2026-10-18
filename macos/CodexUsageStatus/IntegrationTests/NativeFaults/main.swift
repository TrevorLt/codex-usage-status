import Foundation

do {
    let summary = try CodexUsageFetcher.fetchSync()
    print("FETCH SUCCESS: \(summary.menuTitle)")
    exit(0)
} catch {
    print("FETCH ERROR: \(error.localizedDescription)")
    exit(1)
}
