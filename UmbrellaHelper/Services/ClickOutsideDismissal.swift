import AppKit

@MainActor
final class ClickOutsideDismissal {
    private var backdropPanel: NSPanel?
    private weak var targetWindow: NSWindow?
    private var onDismiss: (() -> Void)?

    func activate(for target: NSWindow, onDismiss: @escaping () -> Void) {
        deactivate()
        targetWindow = target
        self.onDismiss = onDismiss
        showBackdrop(below: target)
    }

    func deactivate() {
        backdropPanel?.orderOut(nil)
        backdropPanel = nil
        targetWindow = nil
        onDismiss = nil
    }

    func handleMouseDown(at screenPoint: NSPoint) {
        guard let targetWindow else { return }
        if !targetWindow.frame.contains(screenPoint) {
            onDismiss?()
        }
    }

    private func showBackdrop(below target: NSWindow) {
        let unionFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let backdrop = NSPanel(
            contentRect: unionFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backdrop.isFloatingPanel = true
        backdrop.level = NSWindow.Level(rawValue: target.level.rawValue - 1)
        backdrop.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        backdrop.isOpaque = false
        backdrop.hasShadow = false
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backdrop.hidesOnDeactivate = false
        backdrop.ignoresMouseEvents = false

        let catcher = BackdropClickView(frame: NSRect(origin: .zero, size: unionFrame.size))
        catcher.autoresizingMask = [.width, .height]
        catcher.onClick = { [weak self] in
            self?.onDismiss?()
        }
        backdrop.contentView = catcher
        backdrop.setFrame(unionFrame, display: true)
        backdrop.orderFront(nil)
        backdropPanel = backdrop
    }
}

private final class BackdropClickView: NSView {
    var onClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}
