import AppKit

// NotificationCenter permits removal from any thread. Keep the opaque token
// behind immutable ownership so Swift 6 can safely release it during deinit.
private final class DistributedAppearanceRegistration: @unchecked Sendable {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { DistributedNotificationCenter.default.removeObserver(token) }
}

@MainActor
final class ApplicationAppearanceObserver: NSObject {
    static let systemAppearanceChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    private var observation: NSKeyValueObservation?
    private var distributedObserver: DistributedAppearanceRegistration?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()

        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }

        distributedObserver = DistributedAppearanceRegistration(DistributedNotificationCenter.default.addObserver(
            forName: Self.systemAppearanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        })
    }

    deinit {
        observation?.invalidate()
    }
}
