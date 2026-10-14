import AppKit

@MainActor
final class ApplicationAppearanceObserver: NSObject {
    static let systemAppearanceChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    private var observation: NSKeyValueObservation?
    private var distributedObserver: NSObjectProtocol?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()

        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }

        distributedObserver = DistributedNotificationCenter.default.addObserver(
            forName: Self.systemAppearanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }
    }

    deinit {
        observation?.invalidate()
        if let distributedObserver {
            DistributedNotificationCenter.default.removeObserver(distributedObserver)
        }
    }
}
