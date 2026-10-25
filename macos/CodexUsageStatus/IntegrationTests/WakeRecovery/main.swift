import AppKit
import Foundation

@MainActor
private final class MenuOpenForwarder: NSObject, NSMenuDelegate {
    var openCount = 0
    var forward: (@MainActor (NSMenu) -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        openCount += 1
        forward?(menu)
    }
}

@MainActor
private final class MenuMutationProbe: NSObject {
    var addedItems = 0

    @objc func itemWasAdded(_ notification: Notification) {
        addedItems += 1
    }
}

private let harnessResultURL = CommandLine.arguments.dropFirst().first.map {
    URL(fileURLWithPath: $0 + ".status")
}

private func writeHarnessResult(_ value: String) {
    guard let harnessResultURL else { return }
    try? Data(value.utf8).write(to: harnessResultURL, options: .atomic)
}

// Drives real AppDelegate, renderer, policy and models. Only the fetcher is fake.
// Workspace notifications below stay in this test process; the Mac never sleeps.
let app = NSApplication.shared
let dismissalSuite = "CodexUsageStatus-WakeRecovery-\(UUID().uuidString)"
let expectsInitialFailure = CommandLine.arguments.contains("--first-refresh-failure-smoke")
guard let dismissalDefaults = UserDefaults(suiteName: dismissalSuite) else {
    fputs("FAIL: wake-recovery could not create isolated dismissal storage.\n", stderr)
    exit(2)
}
let dismissalStore = ResetExpiryDismissalStore(defaults: dismissalDefaults)
MainActor.assumeIsolated {
    let delegate = AppDelegate(
        monotonicNow: { CodexUsageFetcher.uptime },
        resetExpiryDismissalStore: dismissalStore
    )
    app.delegate = delegate
    app.finishLaunching()
    CodexUsageFetcher.shouldFail = expectsInitialFailure
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    Task { @MainActor in
        func require(_ condition: Bool, _ message: String) {
            guard condition else {
                writeHarnessResult("FAIL: \(message)")
                print("FAIL: \(message)")
                exit(1)
            }
            print("PASS: \(message)")
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard let item = Mirror(reflecting: delegate).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let button = item.button,
              let menu = Mirror(reflecting: delegate).children.first(where: { $0.label == "menu" })?.value as? NSMenu,
              let reminderContent = Mirror(reflecting: delegate).children.first(where: { $0.label == "resetReminderMenuContent" })?.value as? ResetReminderMenuContent else {
            print("FAIL: no real status item")
            exit(1)
        }
        let reminderItem = reminderContent.item
        @MainActor func hasSubview(named name: String) -> Bool {
            button.subviews.contains { String(describing: type(of: $0)).contains(name) }
        }
        @MainActor func hasMenuTitle(_ title: String) -> Bool {
            reminderItem.submenu?.items.contains { $0.title == title } == true
        }

        if expectsInitialFailure {
            require(CodexUsageFetcher.count == 1, "launch starts exactly one initial refresh")
            require(button.toolTip == "Usage unavailable", "initial refresh failure replaces waiting with a bounded unavailable state")
            let result = "INITIAL REFRESH FAILURE PASS"
            writeHarnessResult(result)
            print(result)
            exit(0)
        }

        require(button.toolTip?.hasPrefix("5h · ") == true, "initial success displays the compact hover format")
        require(button.toolTip?.components(separatedBy: "\n").count == 2, "fresh hover has exactly two lines")
        require(!reminderItem.isHidden && reminderItem.title == "1 reset expires in 1 hour", "real menu shows the current synthetic expiry")
        require(hasMenuTitle("Use one reset…") && hasMenuTitle("Dismiss this expiry reminder"), "expiry submenu exposes direct reset use and batch dismissal")

        let countdownView = AboutRefreshCountdownView()
        let countdownNow = Date(timeIntervalSince1970: 1_900_000_000)
        countdownView.update(nextRefreshAt: countdownNow.addingTimeInterval(60), isRefreshing: false, isSleeping: false, now: countdownNow)
        require(countdownView.visibleText == "Next refresh: in 1m 0s", "About countdown renders as a live accessory label")
        countdownView.update(nextRefreshAt: countdownNow, isRefreshing: false, isSleeping: false, now: countdownNow)
        require(countdownView.visibleText == "Next refresh: Refreshing…", "countdown does not remain stuck at zero when its deadline arrives")
        countdownView.update(nextRefreshAt: countdownNow.addingTimeInterval(120), isRefreshing: false, isSleeping: false, now: countdownNow)
        require(countdownView.visibleText == "Next refresh: in 2m 0s", "a completed refresh replaces zero with the next interval")
        let aboutAlert = NSAlert()
        aboutAlert.accessoryView = countdownView
        _ = aboutAlert.window
        require(countdownView.window != nil, "live countdown is attached to the visible About alert")
        require(hasSubview(named: "BadgeExpiryReminderDotView"), "real status item contains the amber expiry dot")
        let menuOpenForwarder = MenuOpenForwarder()
        menuOpenForwarder.forward = { [weak delegate] menu in
            delegate?.menuWillOpen(menu)
        }
        menu.delegate = menuOpenForwarder
        let menuMutationProbe = MenuMutationProbe()
        NotificationCenter.default.addObserver(menuMutationProbe, selector: #selector(MenuMutationProbe.itemWasAdded(_:)), name: Notification.Name("NSMenuDidAddItemNotification"), object: menu)
        NotificationCenter.default.addObserver(menuMutationProbe, selector: #selector(MenuMutationProbe.itemWasAdded(_:)), name: Notification.Name("NSMenuDidAddItemNotification"), object: reminderContent.menu)
        menuOpenForwarder.menuWillOpen(menu)
        NotificationCenter.default.removeObserver(menuMutationProbe)
        require(menuOpenForwarder.openCount == 1, "simulated status-item open reaches the production menuWillOpen callback")
        require(menuMutationProbe.addedItems == 0, "opening the menu does not insert or rebuild menu rows")
        require(reminderItem.title == "1 reset expires in 1 hour" && hasSubview(named: "BadgeExpiryReminderDotView"), "opening the menu does not dismiss the reminder")

        guard let dismissIndex = reminderItem.submenu?.items.firstIndex(where: { $0.title == "Dismiss this expiry reminder" }),
              let resetSubmenu = reminderItem.submenu else {
            require(false, "dismiss action remains in the stable submenu structure")
            return
        }
        resetSubmenu.performActionForItem(at: dismissIndex)
        require(reminderItem.title == "1 reset available" && !hasSubview(named: "BadgeExpiryReminderDotView"), "dismissing removes only the active batch reminder")
        require(reminderContent.dismissItem.isHidden, "dismiss action hides when no undismissed expiring IDs remain")

        if CommandLine.arguments.contains("--menu-smoke") {
            dismissalDefaults.removePersistentDomain(forName: dismissalSuite)
            let result = "APPKIT MENU INTERACTION PASS (simulated menuWillOpen callback and NSMenu action)"
            writeHarnessResult(result)
            print(result)
            exit(0)
        }

        CodexUsageFetcher.resetCreditID = "synthetic-credit-2"
        let beforeNewCredit = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let newCreditDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeNewCredit && ProcessInfo.processInfo.systemUptime < newCreditDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(reminderItem.title == "1 reset expires in 1 hour" && hasSubview(named: "BadgeExpiryReminderDotView"), "a new reset ID is not suppressed by the previous dismissal")

        CodexUsageFetcher.fiveHourUsedPercent = 81
        let beforeLowUsage = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let lowUsageDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeLowUsage && ProcessInfo.processInfo.systemUptime < lowUsageDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(hasSubview(named: "BadgeWarningOverlayView") && hasSubview(named: "BadgeExpiryReminderDotView"), "actual red low-usage and amber expiry overlays coexist")
        CodexUsageFetcher.fiveHourUsedPercent = 35.1
        let beforeNormalUsage = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let normalUsageDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeNormalUsage && ProcessInfo.processInfo.systemUptime < normalUsageDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))

        CodexUsageFetcher.resetAvailableCount = 0
        let beforeNoCredits = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let noCreditsDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeNoCredits && ProcessInfo.processInfo.systemUptime < noCreditsDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(reminderItem.isHidden && !hasSubview(named: "BadgeExpiryReminderDotView"), "zero available resets removes the summary and dot")

        CodexUsageFetcher.resetAvailableCount = 1
        CodexUsageFetcher.resetCreditID = "synthetic-credit-expired"
        CodexUsageFetcher.resetExpiryOffset = -1
        let beforeExpiredCredit = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let expiredCreditDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeExpiredCredit && ProcessInfo.processInfo.systemUptime < expiredCreditDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(reminderItem.title == "1 reset available" && !hasSubview(named: "BadgeExpiryReminderDotView"), "an already expired detail no longer shows the expiry dot")

        CodexUsageFetcher.resetCreditID = "synthetic-credit-3"
        CodexUsageFetcher.resetExpiryOffset = 3_600
        let beforeRestoredCredit = CodexUsageFetcher.count
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        let restoredCreditDeadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeRestoredCredit && ProcessInfo.processInfo.systemUptime < restoredCreditDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))

        let freshImage = button.image?.tiffRepresentation
        CodexUsageFetcher.shouldFail = true
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        require(button.toolTip?.contains("Showing last known readings") == true, "failure appends only the brief cached-data status")
        require(button.toolTip?.components(separatedBy: "\n").count == 3, "stale hover keeps its two readings and one short status line")
        require(reminderItem.isHidden && !hasSubview(named: "BadgeExpiryReminderDotView"), "refresh failure hides reset data from the previous account read")
        require(button.image?.tiffRepresentation != freshImage, "stale badge is visually distinguishable")

        let workspace = NSWorkspace.shared.notificationCenter
        CodexUsageFetcher.clockOffset += 31
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        CodexUsageFetcher.shouldFail = false
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        require(button.toolTip?.contains("Showing last known readings") == true, "wake redraws cached values before any query")
        let beforeWakeAttempt = CodexUsageFetcher.count
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while CodexUsageFetcher.count == beforeWakeAttempt && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        require(CodexUsageFetcher.count == beforeWakeAttempt + 1, "wake and duplicate display notifications produce one automatic query")
        require(button.toolTip?.contains("Showing last known readings") == false, "wake automatically recovers without manual refresh")
        require(reminderItem.title == "1 reset expires in 1 hour" && hasSubview(named: "BadgeExpiryReminderDotView"), "successful recovery restores the fresh reset reminder")

        CodexUsageFetcher.fiveHourResetOffset = -1
        delegate.perform(NSSelectorFromString("refreshFromMenu"))
        try? await Task.sleep(for: .milliseconds(150))
        require(button.toolTip?.contains("5h · expired") == true, "expired 5H value is not presented as current")
        require(button.toolTip?.contains("7-day · ") == true, "weekly reset time stays visible")

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
        require(button.toolTip?.contains("5h · ") == true && button.toolTip?.contains("expired") == false, "near-expiry value initially appears")
        try? await Task.sleep(for: .milliseconds(1_100))
        require(button.toolTip?.contains("5h · expired") == true, "expiry deadline replaces a stale reset time with the compact expired state")
        require(CodexUsageFetcher.count == expiryRequestCount, "expiry redraw performs no account query")

        for (missing, weeklyOnly) in [(true, false), (false, true)] {
            do {
                _ = try CodexUsageFetcher.fixture(missingUsed: missing, weeklyOnly: weeklyOnly)
                require(false, "invalid snapshot must be rejected")
            } catch { print("PASS: invalid/missing-window sample rejected") }
        }
        if CommandLine.arguments.count > 1,
           let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            button.cacheDisplay(in: button.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])
            if let png {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
        }
        dismissalDefaults.removePersistentDomain(forName: dismissalSuite)
        let result = "WAKE RECOVERY INTEGRATION PASS (synthetic workspace events, not physical lid verification)"
        writeHarnessResult(result)
        print(result)
        let defaultHold = CommandLine.arguments.count == 1 ? "45" : "0"
        if let holdSeconds = Double(ProcessInfo.processInfo.environment["CODEX_USAGE_GUI_HOLD_SECONDS"] ?? defaultHold), holdSeconds > 0 {
            try? await Task.sleep(for: .seconds(holdSeconds))
        }
        exit(0)
    }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 42) {
    print("FAIL: integration timeout")
    exit(2)
}
// Keep AppKit on the OS main thread; dispatchMain() may retire that thread.
CFRunLoopRun()
