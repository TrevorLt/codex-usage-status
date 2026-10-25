import AppKit
import Foundation

enum FetchError: Error {
    case invalidOutput
}

@MainActor
private final class MenuMutationProbe: NSObject {
    var insertedItems = 0

    @objc func itemWasAdded(_ notification: Notification) {
        insertedItems += 1
    }
}

@main
struct MenuStabilityAudit {
    @MainActor
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let credit = RateLimitResetCredit(
            id: "synthetic-credit",
            resetType: "codexRateLimits",
            status: "available",
            grantedAt: now.timeIntervalSince1970 - 100,
            expiresAt: now.addingTimeInterval(3_600).timeIntervalSince1970,
            title: nil,
            description: nil
        )
        let reminder = ResetExpiryReminder(
            credits: RateLimitResetCredits(availableCount: 1, credits: [credit]),
            now: now
        )!
        let content = ResetReminderMenuContent()
        let probe = MenuMutationProbe()
        NotificationCenter.default.addObserver(
            probe,
            selector: #selector(MenuMutationProbe.itemWasAdded(_:)),
            name: Notification.Name("NSMenuDidAddItemNotification"),
            object: content.menu
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        content.update(reminder, dateFormatter: formatter)
        NotificationCenter.default.removeObserver(probe)
        guard probe.insertedItems == 0 else {
            fputs("FAIL: updating reset menu inserted \(probe.insertedItems) submenu rows\n", stderr)
            exit(1)
        }
        guard content.item.title == "1 reset expires in 1 hour",
              !content.item.isHidden,
              content.menu.items.map(\.title) == ["Use one reset…", "", "Dismiss this expiry reminder"] else {
            fputs("FAIL: reset submenu content is incomplete\n", stderr)
            exit(1)
        }
        guard !content.separatorItem.isHidden, !content.dismissItem.isHidden else {
            fputs("FAIL: imminent expiry actions are not visible\n", stderr)
            exit(1)
        }

        let transitionProbe = MenuMutationProbe()
        NotificationCenter.default.addObserver(
            transitionProbe,
            selector: #selector(MenuMutationProbe.itemWasAdded(_:)),
            name: Notification.Name("NSMenuDidAddItemNotification"),
            object: content.menu
        )
        content.update(nil, dateFormatter: formatter)
        guard content.item.isHidden,
              content.separatorItem.isHidden,
              content.dismissItem.isHidden,
              content.menu.items.map(\.title) == ["Use one reset…", "", "Dismiss this expiry reminder"] else {
            fputs("FAIL: dismissible rows remain visible without a reminder\n", stderr)
            exit(1)
        }

        content.update(reminder, dateFormatter: formatter)
        NotificationCenter.default.removeObserver(transitionProbe)
        guard transitionProbe.insertedItems == 0 else {
            fputs("FAIL: reset state changes inserted \(transitionProbe.insertedItems) submenu rows\n", stderr)
            exit(1)
        }
        guard !content.item.isHidden && !content.dismissItem.isHidden else {
            fputs("FAIL: a new expiry could not restore the reminder rows\n", stderr)
            exit(1)
        }

        print("MENU STABILITY PASS: stable submenu structure across reminder updates")
    }
}
