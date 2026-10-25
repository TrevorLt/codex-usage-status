import AppKit
import Foundation

@main
struct BadgeAnimationPreviewApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = BadgeAnimationPreviewController()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class BadgeAnimationPreviewController: NSObject, NSApplicationDelegate {
    private let now = Date()
    private var window: NSWindow?
    private var cards: [BadgeAnimationPreviewCard] = []
    private var timeline: NSSlider!
    private var timeLabel: NSTextField!
    private var scenarioPicker: NSPopUpButton!
    private var playButton: NSButton!
    private var descriptionLabel: NSTextField!
    private var playbackTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        renderFrame()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        playbackTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage Status · Animation Preview"
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 470))
        window.contentView = content

        let title = NSTextField(labelWithString: "Badge animation preview")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: 24, y: 430, width: 500, height: 24)
        content.addSubview(title)

        let instructions = NSTextField(labelWithString: "No account or reset endpoint is used. Choose a scenario, scrub to any frame, or play it.")
        instructions.font = .systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 24, y: 410, width: 712, height: 16)
        content.addSubview(instructions)

        scenarioPicker = NSPopUpButton(frame: NSRect(x: 24, y: 368, width: 310, height: 30), pullsDown: false)
        PreviewScenario.allCases.forEach { scenarioPicker.addItem(withTitle: $0.title) }
        scenarioPicker.target = self
        scenarioPicker.action = #selector(scenarioChanged)
        content.addSubview(scenarioPicker)

        playButton = NSButton(title: "Play", target: self, action: #selector(togglePlayback))
        playButton.bezelStyle = .rounded
        playButton.frame = NSRect(x: 348, y: 368, width: 90, height: 30)
        content.addSubview(playButton)

        timeline = NSSlider(frame: NSRect(x: 24, y: 333, width: 624, height: 24))
        timeline.minValue = 0
        timeline.maxValue = 100
        timeline.doubleValue = 0
        timeline.isContinuous = true
        timeline.target = self
        timeline.action = #selector(timelineChanged)
        content.addSubview(timeline)

        timeLabel = NSTextField(labelWithString: "0%")
        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.frame = NSRect(x: 660, y: 336, width: 76, height: 18)
        content.addSubview(timeLabel)

        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.frame = NSRect(x: 24, y: 308, width: 712, height: 16)
        content.addSubview(descriptionLabel)

        cards = [
            BadgeAnimationPreviewCard(style: .doubleRing, appearanceName: .aqua, theme: .light, frame: NSRect(x: 24, y: 166, width: 347, height: 128)),
            BadgeAnimationPreviewCard(style: .largeReadout, appearanceName: .aqua, theme: .light, frame: NSRect(x: 389, y: 166, width: 347, height: 128)),
            BadgeAnimationPreviewCard(style: .doubleRing, appearanceName: .darkAqua, theme: .dark, frame: NSRect(x: 24, y: 22, width: 347, height: 128)),
            BadgeAnimationPreviewCard(style: .largeReadout, appearanceName: .darkAqua, theme: .dark, frame: NSRect(x: 389, y: 22, width: 347, height: 128)),
        ]
        cards.forEach { content.addSubview($0) }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    @objc private func scenarioChanged() {
        stopPlayback()
        timeline.doubleValue = 0
        renderFrame()
    }

    @objc private func timelineChanged() {
        renderFrame()
    }

    @objc private func togglePlayback() {
        if playbackTimer == nil {
            if timeline.doubleValue >= 100 { timeline.doubleValue = 0 }
            playButton.title = "Pause"
            let timer = Timer(timeInterval: 1.0 / 30.0, target: self,
                              selector: #selector(advancePlayback), userInfo: nil, repeats: true)
            playbackTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            stopPlayback()
        }
        renderFrame()
    }

    @objc private func advancePlayback() {
        let scenario = selectedScenario
        let duration = scenario.transition.duration
        timeline.doubleValue = min(100, timeline.doubleValue + 100 / (duration * 30))
        renderFrame()
        if timeline.doubleValue >= 100 { stopPlayback() }
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playButton?.title = "Play"
    }

    private var selectedScenario: PreviewScenario {
        PreviewScenario.allCases[max(0, min(PreviewScenario.allCases.count - 1, scenarioPicker?.indexOfSelectedItem ?? 0))]
    }

    private func renderFrame() {
        guard !cards.isEmpty else { return }
        let scenario = selectedScenario
        let progress = min(1, max(0, timeline.doubleValue / 100))
        let elapsed = scenario.transition.duration * progress
        let frame = scenario.transition.frame(at: elapsed)
        timeLabel.stringValue = String(format: "%3.0f%% · %.2fs", timeline.doubleValue, elapsed)
        descriptionLabel.stringValue = scenario.description

        let usage = makeUsage(fiveHour: scenario.toFiveHour, weekly: scenario.toWeekly)
        let staleWindows = scenario.isStale ? Set([UsageWindowKind.fiveHour, .weekly]) : []
        for card in cards {
            let rendering = UsageBadgeRenderer.rendering(
                for: usage,
                style: card.style,
                appearance: card.badgeAppearance,
                staleWindows: staleWindows,
                now: now,
                showExpiryReminder: scenario.showExpiryReminder,
                animationFrame: scenario.isStale ? nil : frame
            )
            card.display(rendering)
        }
    }

    private func makeUsage(fiveHour: Int, weekly: Int) -> UsageSummary {
        // Values are deterministic and local to the preview; no fetch or redemption is made.
        try! UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: Double(100 - fiveHour), windowDurationMins: 300,
                                         resetsAt: now.addingTimeInterval(3_600).timeIntervalSince1970),
                secondary: RateLimitWindow(usedPercent: Double(100 - weekly), windowDurationMins: 10_080,
                                          resetsAt: now.addingTimeInterval(7 * 86_400).timeIntervalSince1970),
                planType: "preview"
            ),
            rateLimitsByLimitId: nil,
            accountId: "preview-only"
        ))
    }
}

private enum PreviewScenario: CaseIterable {
    case refreshDecrease
    case refreshIncrease
    case fiveHourReset
    case weeklyReset
    case bothWindowsReset
    case noConfirmedResetChange
    case expiryReminder
    case lastKnown

    static let allCases: [PreviewScenario] = [
        .refreshDecrease,
        .refreshIncrease,
        .fiveHourReset,
        .weeklyReset,
        .bothWindowsReset,
        .noConfirmedResetChange,
        .expiryReminder,
        .lastKnown,
    ]

    var title: String {
        switch self {
        case .refreshDecrease: "Refresh · decrease"
        case .refreshIncrease: "Refresh · increase"
        case .fiveHourReset: "Confirmed 5h reset"
        case .weeklyReset: "Confirmed 7-day reset"
        case .bothWindowsReset: "Both windows reset"
        case .noConfirmedResetChange: "Reset request · no changed window"
        case .expiryReminder: "Reset expiring soon"
        case .lastKnown: "Last-known readings"
        }
    }

    var description: String {
        switch self {
        case .refreshDecrease: "Both values fall through a normal refresh; no green highlight."
        case .refreshIncrease: "Both values rise through a normal refresh; no green highlight."
        case .fiveHourReset: "Only the 5h window is confirmed to recover."
        case .weeklyReset: "Only the 7-day window is confirmed to recover."
        case .bothWindowsReset: "Both windows are confirmed to recover."
        case .noConfirmedResetChange: "The request alone does not animate green without changed fresh readings."
        case .expiryReminder: "The amber dot signals an earned reset that expires within 72 hours."
        case .lastKnown: "A small independent marker preserves the normal reading size."
        }
    }

    var isStale: Bool { self == .lastKnown }
    var showExpiryReminder: Bool { self == .expiryReminder }

    var fromFiveHour: Double {
        switch self {
        case .refreshDecrease: 62
        case .refreshIncrease: 34
        case .fiveHourReset: 8
        case .weeklyReset: 55
        case .bothWindowsReset: 14
        case .noConfirmedResetChange: 46
        case .expiryReminder: 62
        case .lastKnown: 62
        }
    }

    var fromWeekly: Double {
        switch self {
        case .refreshDecrease: 81
        case .refreshIncrease: 46
        case .fiveHourReset: 82
        case .weeklyReset: 9
        case .bothWindowsReset: 18
        case .noConfirmedResetChange: 73
        case .expiryReminder: 81
        case .lastKnown: 88
        }
    }

    var toFiveHour: Int {
        switch self {
        case .refreshDecrease: 54
        case .refreshIncrease: 71
        case .fiveHourReset: 100
        case .weeklyReset: 55
        case .bothWindowsReset: 100
        case .noConfirmedResetChange: 46
        case .expiryReminder: 62
        case .lastKnown: 62
        }
    }

    var toWeekly: Int {
        switch self {
        case .refreshDecrease: 76
        case .refreshIncrease: 68
        case .fiveHourReset: 82
        case .weeklyReset: 100
        case .bothWindowsReset: 100
        case .noConfirmedResetChange: 73
        case .expiryReminder: 81
        case .lastKnown: 88
        }
    }

    var resetWindows: Set<UsageWindowKind> {
        switch self {
        case .fiveHourReset: [.fiveHour]
        case .weeklyReset: [.weekly]
        case .bothWindowsReset: [.fiveHour, .weekly]
        default: []
        }
    }

    var transition: UsageBadgeTransition {
        UsageBadgeTransition(
            fromFiveHour: fromFiveHour,
            fromWeekly: fromWeekly,
            toFiveHour: Double(toFiveHour),
            toWeekly: Double(toWeekly),
            startUptime: 0,
            resetWindows: resetWindows
        )
    }
}

@MainActor
private final class BadgeAnimationPreviewCard: NSView {
    let style: BadgeStyle
    let badgeAppearance: NSAppearance
    private let button: NSButton

    fileprivate init(style: BadgeStyle, appearanceName: NSAppearance.Name, theme: Theme, frame: NSRect) {
        self.style = style
        badgeAppearance = NSAppearance(named: appearanceName) ?? NSAppearance.currentDrawing()
        button = NSButton(frame: NSRect(x: 128, y: 48, width: 90, height: 28))
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = theme.border.cgColor
        appearance = badgeAppearance

        let title = NSTextField(labelWithString: style.menuTitle)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = theme.foreground
        title.frame = NSRect(x: 14, y: 94, width: 160, height: 18)
        addSubview(title)

        let mode = NSTextField(labelWithString: theme.name)
        mode.alignment = .right
        mode.font = .systemFont(ofSize: 10)
        mode.textColor = theme.secondary
        mode.frame = NSRect(x: 190, y: 95, width: 143, height: 16)
        addSubview(mode)

        button.isBordered = false
        button.title = ""
        button.imagePosition = .imageOnly
        button.contentTintColor = theme.foreground
        button.appearance = badgeAppearance
        addSubview(button)

        let caption = NSTextField(labelWithString: "90 pt menu-bar badge")
        caption.alignment = .center
        caption.font = .systemFont(ofSize: 9)
        caption.textColor = theme.secondary
        caption.frame = NSRect(x: 14, y: 21, width: 319, height: 14)
        addSubview(caption)
    }

    required init?(coder: NSCoder) { nil }

    func display(_ rendering: UsageBadgeRendering) {
        UsageBadgeRenderer.apply(rendering, to: button)
        button.layoutSubtreeIfNeeded()
    }

    fileprivate struct Theme {
        let name: String
        let background: NSColor
        let border: NSColor
        let foreground: NSColor
        let secondary: NSColor

        fileprivate static let light = Theme(
            name: "Light appearance",
            background: NSColor(calibratedWhite: 0.98, alpha: 1),
            border: NSColor(calibratedWhite: 0.84, alpha: 1),
            foreground: .black,
            secondary: .secondaryLabelColor
        )
        fileprivate static let dark = Theme(
            name: "Dark appearance",
            background: NSColor(calibratedWhite: 0.16, alpha: 1),
            border: NSColor(calibratedWhite: 0.32, alpha: 1),
            foreground: .white,
            secondary: NSColor(calibratedWhite: 0.7, alpha: 1)
        )
    }
}
