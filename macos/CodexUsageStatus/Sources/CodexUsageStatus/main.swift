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

do {
    guard let instanceGuard = try ApplicationInstanceGuard.acquireForCurrentUser() else {
        // LaunchServices, a Login Item, or launchd may race to start another
        // copy. The existing process already owns the user's menu-bar slot.
        exit(0)
    }

    withExtendedLifetime(instanceGuard) {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
} catch {
    fputs("Could not start Codex Usage Status: \(error.localizedDescription)\n", stderr)
    exit(1)
}
