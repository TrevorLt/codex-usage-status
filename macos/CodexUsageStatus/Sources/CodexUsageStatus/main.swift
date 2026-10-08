import AppKit
import Foundation

if CommandLine.arguments.contains("--once") {
    do {
        let usage = try CodexUsageFetcher.fetchSync()
        print(usage.menuTitle)
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
