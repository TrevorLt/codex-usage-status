import AppKit
import Foundation

@MainActor
final class ResetReminderMenuContent {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "")
    let viewItem = NSMenuItem(title: "Use one reset…", action: nil, keyEquivalent: "")
    let separatorItem = NSMenuItem.separator()
    let dismissItem = NSMenuItem(title: "Dismiss this expiry reminder", action: nil, keyEquivalent: "")

    init() {
        item.submenu = menu
        item.isHidden = true
        menu.addItem(viewItem)
        separatorItem.isHidden = true
        menu.addItem(separatorItem)
        dismissItem.isHidden = true
        menu.addItem(dismissItem)
    }

    func setTargets(_ target: AnyObject, viewAction: Selector, dismissAction: Selector) {
        viewItem.target = target
        viewItem.action = viewAction
        dismissItem.target = target
        dismissItem.action = dismissAction
    }

    func update(_ reminder: ResetExpiryReminder?, dateFormatter: DateFormatter, hasPendingReset: Bool = false) {
        viewItem.title = hasPendingReset ? "Check previous reset…" : "Use one reset…"
        if hasPendingReset {
            item.isHidden = false
            item.title = "Reset status needs checking"
            separatorItem.isHidden = true
            dismissItem.isHidden = true
            return
        }
        guard let reminder else {
            item.isHidden = true
            item.title = ""
            separatorItem.isHidden = true
            dismissItem.isHidden = true
            return
        }

        item.title = reminder.menuTitle(dateFormatter: dateFormatter)
        item.isHidden = false
        let hasExpiringCredits = !reminder.expiringCredits.isEmpty
        separatorItem.isHidden = !hasExpiringCredits
        dismissItem.isHidden = !hasExpiringCredits
    }
}
