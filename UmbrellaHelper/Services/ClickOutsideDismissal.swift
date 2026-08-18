import AppKit

/// Dismisses a floating panel when the user clicks outside it.
/// Uses mouse monitors only — no fullscreen backdrop windows (those can glitch Dock / Spaces).
@MainActor
final class ClickOutsideDismissal {
    private weak var targetWindow: NSWindow?
    private var onDismiss: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func activate(for target: NSWindow, onDismiss: @escaping () -> Void) {
        deactivate()
        targetWindow = target
        self.onDismiss = onDismiss

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleMouseDown(at: NSEvent.mouseLocation)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDown(at: NSEvent.mouseLocation)
            }
        }
    }

    func deactivate() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        targetWindow = nil
        onDismiss = nil
    }

    private func handleMouseDown(at screenPoint: NSPoint) {
        guard let targetWindow, targetWindow.isVisible else { return }
        if !targetWindow.frame.contains(screenPoint) {
            onDismiss?()
        }
    }
}
