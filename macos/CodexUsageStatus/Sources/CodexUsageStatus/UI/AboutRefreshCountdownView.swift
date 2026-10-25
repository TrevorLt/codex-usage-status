import AppKit
import Foundation

@MainActor
final class AboutRefreshCountdownView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.frame = bounds
        label.autoresizingMask = [.width, .minYMargin]
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(true)
        label.setAccessibilityRole(.staticText)
        addSubview(label)
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 360, height: 20))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var visibleText: String { label.stringValue }

    func update(nextRefreshAt: Date?, isRefreshing: Bool, isSleeping: Bool, now: Date = Date()) {
        let state: String
        if isSleeping {
            state = "after wake"
        } else if isRefreshing || nextRefreshAt.map({ $0 <= now }) == true {
            state = "Refreshing…"
        } else if let nextRefreshAt {
            let remaining = max(0, Int(ceil(nextRefreshAt.timeIntervalSince(now))))
            state = remaining >= 60
                ? "in \(remaining / 60)m \(remaining % 60)s"
                : "in \(remaining)s"
        } else {
            state = "not scheduled"
        }

        label.stringValue = "Next refresh: \(state)"
        label.setAccessibilityLabel(label.stringValue)
    }
}
