import AppKit
import Foundation
import Network

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ",")
    private let loginItemController = LoginItemController()

    private var timer: Timer?
    private var displayValidityTimer: Timer?
    private var isRefreshing = false
    private var refreshPolicy = RefreshPolicy()
    private var badgeStyle = BadgeStyle.load()
    private var lastUsage: UsageSummary?
    private var lastRefreshDate: Date?
    private var lastError: Error?
    private var appearanceObserver: ApplicationAppearanceObserver?
    private var isSleeping = false
    private var isAwaitingFreshRead = false
    private var pendingRecovery = false
    private var lastAttemptUptime: TimeInterval?
    private var lifecycleGeneration = 0
    private var nextRefreshAt: Date?
    private let pathMonitor = NWPathMonitor()
    private var networkWasReachable: Bool?
    private let monotonicNow: @MainActor () -> TimeInterval

    init(monotonicNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.monotonicNow = monotonicNow
        super.init()
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Codex usage: waiting for first refresh"
        }
        appearanceObserver = ApplicationAppearanceObserver { [weak self] in
            self?.renderCurrentBadge()
        }
        renderCurrentBadge()

        refreshItem.target = self
        menu.addItem(refreshItem)

        doubleRingItem.target = self
        largeReadoutItem.target = self
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
        displayStyleItem.submenu = displayStyleMenu
        menu.addItem(displayStyleItem)
        updateStyleMenuState()

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        updateLaunchAtLoginMenuState()

        menu.addItem(.separator())

        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let recovered = self.networkWasReachable == false && reachable
                self.networkWasReachable = reachable
                if recovered { self.requestRecoveryRefresh() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "CodexUsageStatus.network", qos: .utility))
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        displayValidityTimer?.invalidate()
        pathMonitor.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func refreshFromMenu() {
        refresh(manual: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        renderCurrentBadge()
        updateLaunchAtLoginMenuState()
    }

    @objc private func systemWillSleep() {
        isSleeping = true
        isAwaitingFreshRead = true
        lifecycleGeneration += 1
        timer?.invalidate()
        displayValidityTimer?.invalidate()
        nextRefreshAt = nil
    }

    @objc private func systemDidWake() {
        isSleeping = false
        isAwaitingFreshRead = true
        renderCurrentBadge()
        requestRecoveryRefresh()
    }

    @objc private func screenDidWake() {
        guard !isSleeping else { return }
        // Also redraw after display sleep without a full device-sleep cycle.
        renderCurrentBadge()
        requestRecoveryRefresh()
    }

    private func requestRecoveryRefresh() {
        guard !isSleeping else { return }
        if isRefreshing {
            pendingRecovery = true
            return
        }
        let elapsed = lastAttemptUptime.map { max(0, monotonicNow() - $0) } ?? AppConfig.minimumRefreshInterval
        let delay = max(3, AppConfig.minimumRefreshInterval - elapsed)
        // Repeated wake/screen events may advance a later retry, never delay it.
        if let nextRefreshAt, nextRefreshAt <= Date().addingTimeInterval(delay) { return }
        scheduleNextRefresh(after: delay)
    }

    @objc private func timerDidFire() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func selectDoubleRingStyle() {
        setBadgeStyle(.doubleRing)
    }

    @objc private func selectLargeReadoutStyle() {
        setBadgeStyle(.largeReadout)
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginItem.state != .on
        do {
            try loginItemController.setEnabled(shouldEnable)
            updateLaunchAtLoginMenuState()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
            updateLaunchAtLoginMenuState()
        }
    }

    @objc private func showAbout() {
        var status: String
        if let lastUsage {
            status = lastUsage.tooltip(formatter: dateFormatter)
            if let lastError { status += "\nLast refresh failed: \(lastError.localizedDescription)" }
        } else if let lastError {
            status = "Last refresh failed: \(lastError.localizedDescription)"
        } else {
            status = "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { dateFormatter.string(from: $0) } ?? "Never"
        let nextRefresh = nextRefreshAt.map { "in \(max(0, Int($0.timeIntervalSinceNow))) seconds" } ?? (isSleeping ? "after wake" : "in progress")
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let codexPath = CodexPathResolver.firstExecutablePath(in: CodexPathResolver.candidatePaths()) ?? "not found in known locations"
        let message = """
        \(status)

        App version: \(appVersion)
        Display style: \(badgeStyle.menuTitle)
        Next refresh: \(nextRefresh)
        Failure retry: \(Int(AppConfig.errorRetryInterval)) seconds
        Last refresh: \(lastRefresh)
        Codex executable: \(codexPath)
        Data source: local Codex app-server
        """

        let alert = NSAlert()
        alert.messageText = "About Codex Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setBadgeStyle(_ style: BadgeStyle) {
        guard badgeStyle != style else {
            return
        }
        badgeStyle = style
        badgeStyle.save()
        updateStyleMenuState()
        renderCurrentBadge()
    }

    private func updateStyleMenuState() {
        doubleRingItem.state = badgeStyle == .doubleRing ? .on : .off
        largeReadoutItem.state = badgeStyle == .largeReadout ? .on : .off
    }

    private func updateLaunchAtLoginMenuState() {
        launchAtLoginItem.state = loginItemController.isEnabled ? .on : .off
    }

    private func refresh(manual: Bool = false) {
        guard !isSleeping else { return }
        guard !isRefreshing else {
            if manual { pendingRecovery = true }
            return
        }

        if !manual, let lastAttemptUptime {
            let remaining = AppConfig.minimumRefreshInterval - (monotonicNow() - lastAttemptUptime)
            if remaining > 0 {
                scheduleNextRefresh(after: remaining)
                return
            }
        }

        // Consume events admitted by this attempt. New events arriving while it
        // runs may set pendingRecovery again, but an old wake must not survive it.
        pendingRecovery = false
        isRefreshing = true
        lastAttemptUptime = monotonicNow()
        let generation = lifecycleGeneration
        timer?.invalidate()
        nextRefreshAt = nil
        refreshItem.isEnabled = false
        refreshItem.title = "Refreshing..."

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let usage = try await CodexUsageFetcher.fetch()
                let previousSnapshot = self.lastUsage.map(UsageRefreshSnapshot.init)
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                guard generation == self.lifecycleGeneration, !self.isSleeping else {
                    self.isAwaitingFreshRead = true
                    self.requestRecoveryRefresh()
                    return
                }
                self.applyUsage(usage)
                let nextInterval = self.refreshPolicy.nextInterval(
                    previous: previousSnapshot,
                    current: UsageRefreshSnapshot(usage),
                    now: self.monotonicNow()
                )
                self.scheduleNextRefresh(after: nextInterval)
                self.finishPendingRecovery()
            } catch {
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                guard generation == self.lifecycleGeneration, !self.isSleeping else {
                    self.requestRecoveryRefresh()
                    return
                }
                self.applyError(error)
                self.scheduleNextRefresh(after: self.refreshPolicy.intervalAfterFailure())
                self.finishPendingRecovery()
            }
        }
    }

    private func scheduleNextRefresh(after seconds: TimeInterval) {
        timer?.invalidate()
        guard !isSleeping else { nextRefreshAt = nil; return }
        nextRefreshAt = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
        timer?.tolerance = seconds * AppConfig.timerToleranceRatio
    }

    private func finishPendingRecovery() {
        guard pendingRecovery else { return }
        pendingRecovery = false
        requestRecoveryRefresh()
    }

    private func applyUsage(_ usage: UsageSummary) {
        lastUsage = usage
        lastRefreshDate = Date()
        lastError = nil
        isAwaitingFreshRead = false
        renderCurrentBadge()
    }

    private func applyError(_ error: Error) {
        lastError = error
        renderCurrentBadge()
    }

    private func renderCurrentBadge() {
        scheduleDisplayValidityCheck()
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        if let button = statusItem.button {
            button.title = ""
            let appearance = button.effectiveAppearance

            if let lastUsage, let lastRefreshDate {
                let age = Date().timeIntervalSince(lastRefreshDate)
                let cacheExpired = age < 0 || age > 86_400
                let stale = lastError != nil || isAwaitingFreshRead || cacheExpired || age > max(120, refreshPolicy.currentInterval * 2)
                    || lastUsage.fiveHour.isExpired(at: Date()) || lastUsage.weekly.isExpired(at: Date())
                let rendering = UsageBadgeRenderer.rendering(for: lastUsage, style: badgeStyle, appearance: appearance, isStale: stale, hideReadings: cacheExpired)
                UsageBadgeRenderer.apply(rendering, to: button)
                var tooltip = stale ? "Last known readings (~ means awaiting a successful update)\n" : ""
                tooltip += cacheExpired ? "Cached readings expired; waiting for a successful update" : lastUsage.tooltip(formatter: dateFormatter)
                tooltip += "\nLast successful read: \(dateFormatter.string(from: lastRefreshDate))"
                if let lastError { tooltip += "\nRefresh failed: \(lastError.localizedDescription)" }
                button.toolTip = tooltip
                button.setAccessibilityLabel(tooltip)
            } else if let lastError {
                UsageBadgeRenderer.apply(UsageBadgeRendering(image: UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: appearance), warningOverlay: nil), to: button)
                button.toolTip = "Codex usage: \(lastError.localizedDescription)"
            } else {
                UsageBadgeRenderer.apply(UsageBadgeRendering(image: UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: appearance), warningOverlay: nil), to: button)
                button.toolTip = "Codex usage: waiting for first refresh"
            }
        }
    }

    @objc private func displayValidityDidChange() {
        renderCurrentBadge()
    }

    private func scheduleDisplayValidityCheck() {
        displayValidityTimer?.invalidate()
        guard !isSleeping, let lastUsage, let lastRefreshDate else { return }
        let now = Date()
        let candidates = [lastUsage.fiveHour.resetsAt, lastUsage.weekly.resetsAt,
                          lastRefreshDate.addingTimeInterval(86_400),
                          lastRefreshDate.addingTimeInterval(max(120, refreshPolicy.currentInterval * 2))]
            .compactMap { $0 }.filter { $0 > now }
        guard let deadline = candidates.min() else { return }
        // A local one-shot redraw at expiry, not an additional account query.
        let validityTimer = Timer(timeInterval: max(0.05, deadline.timeIntervalSince(now)), target: self,
                                  selector: #selector(displayValidityDidChange), userInfo: nil, repeats: false)
        RunLoop.main.add(validityTimer, forMode: .common)
        displayValidityTimer = validityTimer
    }
}
