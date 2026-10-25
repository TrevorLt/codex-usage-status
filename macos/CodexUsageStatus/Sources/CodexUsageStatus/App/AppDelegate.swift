import AppKit
import Foundation
import Network

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let resetReminderMenuContent = ResetReminderMenuContent()
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ",")
    private let loginItemController = LoginItemController()
    private let resetExpiryDismissalStore: ResetExpiryDismissalStore
    private let resetConsumptionAttemptStore: ResetConsumptionAttemptStore
    private let resetRedemptionFlow: ResetRedemptionFlow

    private var timer: Timer?
    private var displayValidityTimer: Timer?
    private var aboutRefreshTimer: Timer?
    private var badgeAnimationTimer: Timer?
    private var badgeTransition: UsageBadgeTransition?
    private var badgeAnimationFrame: UsageBadgeAnimationFrame?
    private weak var aboutAlert: NSAlert?
    private var aboutCountdownView: AboutRefreshCountdownView?
    private var isRefreshing = false
    private var isConsumingReset = false
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

    init(
        monotonicNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        resetExpiryDismissalStore: ResetExpiryDismissalStore = ResetExpiryDismissalStore(),
        resetConsumptionAttemptStore: ResetConsumptionAttemptStore = ResetConsumptionAttemptStore(),
        resetRedemptionFlow: ResetRedemptionFlow = ResetRedemptionFlow(client: CodexResetRedemptionClient())
    ) {
        self.monotonicNow = monotonicNow
        self.resetExpiryDismissalStore = resetExpiryDismissalStore
        self.resetConsumptionAttemptStore = resetConsumptionAttemptStore
        self.resetRedemptionFlow = resetRedemptionFlow
        super.init()
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private lazy var resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Waiting for first refresh"
            button.setAccessibilityLabel("Waiting for first refresh")
        }
        appearanceObserver = ApplicationAppearanceObserver { [weak self] in
            self?.renderCurrentBadge()
        }
        renderCurrentBadge()

        refreshItem.target = self
        menu.addItem(refreshItem)

        resetReminderMenuContent.setTargets(
            self,
            viewAction: #selector(viewOrUseResets),
            dismissAction: #selector(dismissResetExpiryReminder)
        )
        menu.addItem(resetReminderMenuContent.item)

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
        aboutRefreshTimer?.invalidate()
        badgeAnimationTimer?.invalidate()
        pathMonitor.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func refreshFromMenu() {
        refresh(manual: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuState()
    }

    @objc private func systemWillSleep() {
        isSleeping = true
        isAwaitingFreshRead = true
        lifecycleGeneration += 1
        timer?.invalidate()
        displayValidityTimer?.invalidate()
        stopBadgeAnimation()
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
        let alert = NSAlert()
        alert.messageText = "About Codex Usage Status"
        alert.addButton(withTitle: "OK")
        let countdownView = AboutRefreshCountdownView()
        alert.accessoryView = countdownView

        aboutRefreshTimer?.invalidate()
        aboutAlert = alert
        aboutCountdownView = countdownView
        updateAboutAlert()

        let refreshTimer = Timer(timeInterval: 1, target: self, selector: #selector(aboutRefreshTimerDidFire), userInfo: nil, repeats: true)
        aboutRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
        defer {
            refreshTimer.invalidate()
            if aboutRefreshTimer === refreshTimer { aboutRefreshTimer = nil }
            if aboutAlert === alert { aboutAlert = nil }
            if aboutCountdownView === countdownView { aboutCountdownView = nil }
        }

        alert.runModal()
    }

    @objc private func aboutRefreshTimerDidFire() {
        updateAboutAlert()
    }

    private func updateAboutAlert() {
        guard let alert = aboutAlert, let countdownView = aboutCountdownView else { return }
        alert.informativeText = aboutMessage()
        countdownView.update(nextRefreshAt: nextRefreshAt, isRefreshing: isRefreshing, isSleeping: isSleeping)
    }

    private func aboutMessage() -> String {
        let aboutFormatter = dateFormatter
        aboutFormatter.locale = Locale.current
        aboutFormatter.timeZone = TimeZone.current

        var status: String
        if let lastUsage {
            status = lastUsage.tooltip(formatter: aboutFormatter)
            if let lastError { status += "\nLast refresh failed: \(lastError.localizedDescription)" }
        } else if let lastError {
            status = "Last refresh failed: \(lastError.localizedDescription)"
        } else {
            status = "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { aboutFormatter.string(from: $0) } ?? "Never"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let codexPath = CodexPathResolver.firstExecutablePath(in: CodexPathResolver.candidatePaths()) ?? "not found in known locations"
        let resetExpiryLines = ResetCreditExpiryDetails(credits: lastUsage?.resetCredits)
            .aboutLines(dateFormatter: aboutFormatter)
        let resetExpirySection = resetExpiryLines.isEmpty
            ? ""
            : "\n\nEarned reset expirations:\n" + resetExpiryLines.joined(separator: "\n")
        return """
        \(status)\(resetExpirySection)

        App version: \(appVersion)
        Display style: \(badgeStyle.menuTitle)
        Failure retry: \(Int(AppConfig.errorRetryInterval)) seconds
        Last refresh: \(lastRefresh)
        Codex executable: \(codexPath)
        Data source: local Codex app-server
        """
    }

    @objc private func viewOrUseResets() {
        guard let resetSummary = lastUsage?.resetCredits,
              resetSummary.availableCount > 0 else {
            showResetNotice(title: "No reset available", message: "No earned reset is available in the latest account read. Refresh usage and try again.")
            return
        }
        guard let accountID = lastUsage?.accountID, !accountID.isEmpty else {
            showResetNotice(
                title: "Account unavailable",
                message: ResetConsumptionAttemptStoreError.accountIdentityUnavailable.localizedDescription
            )
            return
        }
        if resetConsumptionAttemptStore.hasUnresolvedAttempt(forAccountID: accountID) {
            showResetNotice(
                title: "Previous reset unresolved",
                message: ResetConsumptionAttemptStoreError.unresolvedAttemptForDifferentAccount.localizedDescription
            )
            return
        }

        let selectedCredit = (resetSummary.credits ?? [])
            .compactMap { credit -> (RateLimitResetCredit, Date)? in
                guard let expiry = credit.availableCodexExpiry, expiry > Date() else { return nil }
                return (credit, expiry)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0

        let alert = NSAlert()
        alert.messageText = "Use one earned reset?"
        if let expiry = selectedCredit?.availableCodexExpiry {
            let expiryText = resetDateFormatter.string(from: expiry)
            alert.informativeText = "This will immediately use one reset credit, expiring \(expiryText), through Codex. The action cannot be undone."
        } else {
            alert.informativeText = "This will immediately use one reset credit chosen by Codex. The action cannot be undone."
        }
        alert.addButton(withTitle: "Use reset")
        alert.addButton(withTitle: "Close")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        consumeReset(creditID: selectedCredit?.id, accountID: accountID)
    }

    private func consumeReset(creditID: String?, accountID: String) {
        guard !isConsumingReset else { return }
        let attempt: PendingResetConsumptionAttempt
        do {
            attempt = try resetConsumptionAttemptStore.begin(creditID: creditID, accountID: accountID)
        } catch {
            showResetNotice(title: "Previous reset unresolved", message: error.localizedDescription)
            return
        }
        isConsumingReset = true
        renderCurrentBadge()

        Task { [weak self] in
            guard let self else { return }
            let result = await self.resetRedemptionFlow.redeem(
                creditID: attempt.creditID,
                idempotencyKey: attempt.idempotencyKey,
                previousUsage: self.lastUsage,
                now: Date()
            )
            switch result {
            case .confirmed(let usage, let changedWindows):
                self.applyUsage(usage, confirmedResetWindows: changedWindows)
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(title: "Reset used", message: "Codex confirmed the reset and the usage status has been refreshed.")
            case .refreshPending(let detail):
                self.lastError = ResetRedemptionFlowError(message: detail)
                self.renderCurrentBadge()
                self.showResetNotice(
                    title: "Reset sent; refresh pending",
                    message: "Codex accepted this redemption, but the latest usage could not be read. Retry the reset action to check the same redemption safely, or refresh again later. Details: \(detail)"
                )
            case .nothingToReset:
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(title: "Nothing to reset", message: "Codex has no rate-limit window eligible for a reset right now.")
                self.refresh(manual: true)
            case .noCredit:
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(title: "No reset available", message: "Codex reports that no earned reset credit is available.")
                self.refresh(manual: true)
            case .preflightFailed(let detail):
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(
                    title: "Account could not be verified",
                    message: "No reset request was sent. Refresh usage and try again. Details: \(detail)"
                )
            case .accountChanged:
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(
                    title: "Codex account changed",
                    message: "No reset request was sent. Refresh usage, then confirm the reset for the active account."
                )
            case .accountIdentityUnavailable:
                self.resetConsumptionAttemptStore.clear()
                self.showResetNotice(
                    title: "Account unavailable",
                    message: ResetConsumptionAttemptStoreError.accountIdentityUnavailable.localizedDescription
                )
            case .statusUnclear(let detail):
                self.showResetNotice(
                    title: "Reset status unclear",
                    message: "The app could not confirm whether Codex used the reset. Retry this action to check the same redemption safely. Details: \(detail)"
                )
            }
            self.isConsumingReset = false
            self.renderCurrentBadge()
        }
    }

    private func showResetNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func dismissResetExpiryReminder() {
        let now = Date()
        guard let accountID = lastUsage?.accountID,
              let reminder = currentResetExpiryReminder(at: now),
              !reminder.expiringCredits.isEmpty else {
            return
        }
        resetExpiryDismissalStore.dismiss(reminder.expiringCredits, accountID: accountID, now: now)
        renderCurrentBadge()
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
        renderCurrentBadge()

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
        let refreshTimer = Timer(timeInterval: seconds, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
        timer = refreshTimer
        timer?.tolerance = seconds * AppConfig.timerToleranceRatio
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    private func finishPendingRecovery() {
        guard pendingRecovery else { return }
        pendingRecovery = false
        requestRecoveryRefresh()
    }

    private func applyUsage(_ usage: UsageSummary, confirmedResetWindows: Set<UsageWindowKind> = []) {
        let previousUsage = lastUsage
        resetExpiryDismissalStore.prepare(accountID: usage.accountID)
        lastUsage = usage
        lastRefreshDate = Date()
        lastError = nil
        isAwaitingFreshRead = false
        startBadgeTransition(from: previousUsage, to: usage, resetWindows: confirmedResetWindows)
        renderCurrentBadge()
    }

    private func startBadgeTransition(
        from previous: UsageSummary?,
        to current: UsageSummary,
        resetWindows: Set<UsageWindowKind>
    ) {
        let currentVisualFrame = badgeAnimationFrame
        stopBadgeAnimation()
        guard let previous else { return }

        let transition = UsageBadgeTransition(
            fromFiveHour: currentVisualFrame?.fiveHourPercent ?? Double(previous.fiveHour.remainingPercent),
            fromWeekly: currentVisualFrame?.weeklyPercent ?? Double(previous.weekly.remainingPercent),
            toFiveHour: Double(current.fiveHour.remainingPercent),
            toWeekly: Double(current.weekly.remainingPercent),
            startUptime: monotonicNow(),
            resetWindows: resetWindows
        )
        guard abs(transition.fromFiveHour - transition.toFiveHour) >= 0.01
                || abs(transition.fromWeekly - transition.toWeekly) >= 0.01 else {
            return
        }

        badgeTransition = transition
        badgeAnimationFrame = transition.frame(at: monotonicNow())
        let animationTimer = Timer(timeInterval: 1.0 / 30.0, target: self,
                                   selector: #selector(badgeAnimationTimerDidFire), userInfo: nil, repeats: true)
        badgeAnimationTimer = animationTimer
        RunLoop.main.add(animationTimer, forMode: .common)
    }

    private func stopBadgeAnimation() {
        badgeAnimationTimer?.invalidate()
        badgeAnimationTimer = nil
        badgeTransition = nil
        badgeAnimationFrame = nil
    }

    @objc private func badgeAnimationTimerDidFire() {
        guard let transition = badgeTransition else {
            stopBadgeAnimation()
            renderCurrentBadge()
            return
        }

        let frame = transition.frame(at: monotonicNow())
        badgeAnimationFrame = frame
        if frame.isComplete {
            stopBadgeAnimation()
            renderCurrentBadge()
        } else {
            renderBadgeVisual(updateAccessibility: false, resetReminder: currentResetExpiryReminder(at: Date()))
        }
    }

    private func applyError(_ error: Error) {
        lastError = error
        renderCurrentBadge()
    }

    private func renderCurrentBadge() {
        scheduleDisplayValidityCheck()
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        let resetReminder = currentResetExpiryReminder(at: Date())
        updateResetReminderMenu(for: resetReminder)
        renderBadgeVisual(updateAccessibility: true, resetReminder: resetReminder)
    }

    private func renderBadgeVisual(updateAccessibility: Bool, resetReminder: ResetExpiryReminder?) {
        if let button = statusItem.button {
            button.title = ""
            let appearance = button.effectiveAppearance

            if let lastUsage, let lastRefreshDate {
                let age = Date().timeIntervalSince(lastRefreshDate)
                let cacheExpired = age < 0 || age > 86_400
                let stale = lastError != nil || isAwaitingFreshRead || cacheExpired || age > max(120, refreshPolicy.currentInterval * 2)
                let now = Date()
                var staleWindows = Set<UsageWindowKind>()
                if stale && !lastUsage.fiveHour.isExpired(at: now) { staleWindows.insert(.fiveHour) }
                if stale && !lastUsage.weekly.isExpired(at: now) { staleWindows.insert(.weekly) }
                let rendering = UsageBadgeRenderer.rendering(
                    for: lastUsage,
                    style: badgeStyle,
                    appearance: appearance,
                    staleWindows: staleWindows,
                    hideReadings: cacheExpired,
                    showExpiryReminder: resetReminder.map { !$0.expiringCredits.isEmpty } ?? false,
                    animationFrame: badgeAnimationFrame
                )
                UsageBadgeRenderer.apply(rendering, to: button)
                if updateAccessibility {
                    let tooltip = lastUsage.hoverTooltip(showingLastKnownReadings: stale)
                    button.toolTip = tooltip
                    button.setAccessibilityLabel(tooltip)
                }
            } else if lastError != nil {
                UsageBadgeRenderer.apply(UsageBadgeRendering(image: UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: appearance), warningOverlay: nil, expiryReminder: false), to: button)
                if updateAccessibility {
                    button.toolTip = "Usage unavailable"
                    button.setAccessibilityLabel("Usage unavailable")
                }
            } else {
                UsageBadgeRenderer.apply(UsageBadgeRendering(image: UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: appearance), warningOverlay: nil, expiryReminder: false), to: button)
                if updateAccessibility {
                    button.toolTip = "Waiting for first refresh"
                    button.setAccessibilityLabel("Waiting for first refresh")
                }
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
                          lastRefreshDate.addingTimeInterval(ResetReminderFreshness.maximumAge(refreshInterval: refreshPolicy.currentInterval))]
            .compactMap { $0 }.filter { $0 > now }
        let resetTransitions = (lastUsage.resetCredits?.credits ?? [])
            .compactMap(\.availableCodexExpiry)
            .flatMap { [$0.addingTimeInterval(-ResetExpiryReminder.threshold), $0] }
            .filter { $0 > now }
        let reminderTransition = currentResetExpiryReminder(at: now)?.nextDisplayTransition(after: now)
        let deadline = (candidates + resetTransitions + [reminderTransition].compactMap { $0 }).min()
        guard let deadline else { return }
        // A local one-shot redraw at expiry, not an additional account query.
        let validityTimer = Timer(timeInterval: max(0.05, deadline.timeIntervalSince(now)), target: self,
                                  selector: #selector(displayValidityDidChange), userInfo: nil, repeats: false)
        RunLoop.main.add(validityTimer, forMode: .common)
        displayValidityTimer = validityTimer
    }

    private func currentResetExpiryReminder(at now: Date) -> ResetExpiryReminder? {
        guard let usage = lastUsage,
              let accountID = usage.accountID,
              ResetReminderFreshness.canPresent(
                lastRefreshDate: lastRefreshDate,
                hasRefreshError: lastError != nil,
                isAwaitingFreshRead: isAwaitingFreshRead,
                refreshInterval: refreshPolicy.currentInterval,
                now: now
              ) else {
            return nil
        }
        return ResetExpiryReminder(
            credits: usage.resetCredits,
            dismissedIDs: resetExpiryDismissalStore.dismissedIDs(accountID: accountID, now: now),
            now: now
        )
    }

    private func updateResetReminderMenu(for reminder: ResetExpiryReminder?) {
        resetReminderMenuContent.update(reminder, dateFormatter: resetDateFormatter)
        resetReminderMenuContent.viewItem.isEnabled = !isRefreshing && !isConsumingReset
    }

}
