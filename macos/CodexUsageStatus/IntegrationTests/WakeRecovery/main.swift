import AppKit
import Foundation

// Drives real AppDelegate, renderer, policy and models. Only the fetcher is fake.
// Workspace notifications below stay in this test process; the Mac never sleeps.
let app = NSApplication.shared
guard app.setActivationPolicy(.accessory) else {
    fputs("FAIL: wake-recovery requires an accessory app in the logged-in GUI session; a command-line process cannot create its real status item.\n", stderr)
    exit(2)
}
MainActor.assumeIsolated {
    let delegate = AppDelegate(monotonicNow: { CodexUsageFetcher.uptime })
    app.delegate = delegate
    app.finishLaunching()
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    Task { @MainActor in
        func require(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL: \(message)"); exit(1) }
            print("PASS: \(message)")
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard let item = Mirror(reflecting: delegate).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let button = item.button else {
            print("FAIL: no real status item")
            exit(1)
        }
        require(button.toolTip?.contains("65%") == true, "initial success displays actual fixture values")
        let freshImage = button.image?.tiffRepresentation
        CodexUsageFetcher.shouldFail = true
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        require(button.toolTip?.contains("65%") == true && button.toolTip?.contains("88%") == true, "failure preserves both last-good values")
        require(button.toolTip?.contains("Refresh failed") == true && button.toolTip?.contains("Last known") == true, "failure discloses stale data and error")
        require(button.image?.tiffRepresentation != freshImage, "stale badge is visually distinguishable")

        let workspace = NSWorkspace.shared.notificationCenter
        CodexUsageFetcher.clockOffset += 31
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        CodexUsageFetcher.shouldFail = false
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        require(button.toolTip?.contains("65%") == true, "wake redraws cached values before any query")
        let beforeWakeAttempt = CodexUsageFetcher.count
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeWakeAttempt && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(CodexUsageFetcher.count == beforeWakeAttempt + 1, "wake and duplicate display notifications produce one automatic query")
        require(button.toolTip?.contains("65%") == true && button.toolTip?.contains("Refresh failed") == false, "wake automatically recovers without manual refresh")

        CodexUsageFetcher.fiveHourResetOffset = -1
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        require(button.toolTip?.contains("5-hour remaining: unknown") == true, "expired 5H value is not presented as current")
        require(button.toolTip?.contains("Weekly remaining: 88%") == true, "unexpired weekly window stays visible")

        // A starts before sleep and is suspended. B must consume that wake's
        // pending bit, so B's failure keeps its 300-second retry (no extra C).
        CodexUsageFetcher.fiveHourResetOffset = 3_600
        CodexUsageFetcher.suspendNext = true
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        require(CodexUsageFetcher.continuation != nil, "pre-sleep request is genuinely in flight")
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        CodexUsageFetcher.shouldFail = true
        CodexUsageFetcher.clockOffset += 31
        let beforeRecovery = CodexUsageFetcher.count
        CodexUsageFetcher.continuation?.resume()
        CodexUsageFetcher.continuation = nil
        let recoveryDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeRecovery && ProcessInfo.processInfo.systemUptime < recoveryDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(CodexUsageFetcher.count == beforeRecovery + 1, "discarded sleep-era request leads to exactly one recovery attempt")
        let retryTimer = Mirror(reflecting: delegate).children.first(where: { $0.label == "timer" })?.value as? Timer
        require((retryTimer?.fireDate.timeIntervalSinceNow ?? 0) > 280, "consumed wake intent does not overwrite failure backoff")

        CodexUsageFetcher.shouldFail = false
        CodexUsageFetcher.fiveHourResetOffset = 0.8
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        let expiryRequestCount = CodexUsageFetcher.count
        require(button.toolTip?.contains("5-hour remaining: 65%") == true, "near-expiry value initially appears")
        try? await Task.sleep(for: .milliseconds(1_100))
        require(button.toolTip?.contains("5-hour remaining: unknown") == true, "expiry deadline hides a value without menu interaction or refresh")
        require(CodexUsageFetcher.count == expiryRequestCount, "expiry redraw performs no account query")

        for (missing, weeklyOnly) in [(true, false), (false, true)] {
            do {
                _ = try CodexUsageFetcher.fixture(missingUsed: missing, weeklyOnly: weeklyOnly)
                require(false, "invalid snapshot must be rejected")
            } catch { print("PASS: invalid/missing-window sample rejected") }
        }
        if CommandLine.arguments.count > 1, let tiff = button.image?.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("WAKE RECOVERY INTEGRATION PASS (synthetic workspace events, not physical lid verification)")
        exit(0)
    }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 42) {
    print("FAIL: integration timeout")
    exit(2)
}
// Keep AppKit on the OS main thread; dispatchMain() may retire that thread.
CFRunLoopRun()
