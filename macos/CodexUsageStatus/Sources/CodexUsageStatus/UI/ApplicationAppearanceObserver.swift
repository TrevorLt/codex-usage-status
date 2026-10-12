import AppKit

@MainActor
final class ApplicationAppearanceObserver {
    private var observation: NSKeyValueObservation?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }
    }

    deinit {
        observation?.invalidate()
    }
}
