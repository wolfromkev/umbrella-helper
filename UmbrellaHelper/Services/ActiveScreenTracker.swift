import AppKit

@MainActor
enum ActiveScreenTracker {
    private static var lastClickedScreen: NSScreen?
    private static var clickMonitor: Any?

    static func start() {
        guard clickMonitor == nil else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                recordClick(at: NSEvent.mouseLocation)
            }
        }
    }

    static func stop() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    static func recordClick(at point: NSPoint) {
        lastClickedScreen = screen(containing: point)
    }

    static func presentationScreen(excluding excludedWindow: NSWindow? = nil) -> NSScreen {
        if let screen = screen(containing: NSEvent.mouseLocation) {
            return screen
        }
        if let lastClickedScreen {
            return lastClickedScreen
        }
        if let mainScreen = NSScreen.main {
            return mainScreen
        }
        if let excludedWindow, excludedWindow.isVisible, let panelScreen = excludedWindow.screen {
            return panelScreen
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
