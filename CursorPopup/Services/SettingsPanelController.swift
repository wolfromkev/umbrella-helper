import AppKit
import SwiftUI

enum SettingsPanelMetrics {
    static let panelWidth: CGFloat = 528
    static let panelHeight: CGFloat = 548
}

@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private weak var model: AppModel?
    private var keyMonitor: Any?
    private var globalClickMonitor: Any?
    private let clickOutsideDismissal = ClickOutsideDismissal()

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        if panel == nil {
            let contentView = SettingsView()

            let hosting = NSHostingController(rootView: contentView)
            if #available(macOS 13.0, *) {
                hosting.sizingOptions = [.intrinsicContentSize]
            }

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: SettingsPanelMetrics.panelWidth, height: SettingsPanelMetrics.panelHeight)
            )
            panel.delegate = self
            panel.contentViewController = hosting
            self.panel = panel
            installKeyMonitor()
        }

        panel?.setFrame(centeredFrame(), display: false)
        panel?.makeKeyAndOrderFront(nil)
        installClickOutsideDismissal()
    }

    func closePanel() {
        removeClickOutsideDismissal()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            window === panel,
            model?.isSettingsVisible == true
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let panel = self.panel,
                self.model?.isSettingsVisible == true,
                !panel.isKeyWindow
            else {
                return
            }
            self.model?.hideSettings()
        }
    }

    private func centeredFrame() -> NSRect {
        let screen = screenForSettings()
        let screenFrame = screen.visibleFrame
        return NSRect(
            x: screenFrame.midX - SettingsPanelMetrics.panelWidth / 2,
            y: screenFrame.midY - SettingsPanelMetrics.panelHeight / 2,
            width: SettingsPanelMetrics.panelWidth,
            height: SettingsPanelMetrics.panelHeight
        )
    }

    private func screenForSettings() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }
        if let panelScreen = panel?.screen {
            return panelScreen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func installClickOutsideDismissal() {
        guard let panel else { return }

        clickOutsideDismissal.activate(for: panel) { [weak self] in
            self?.model?.hideSettings()
        }

        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.clickOutsideDismissal.handleMouseDown(at: NSEvent.mouseLocation)
            }
        }
    }

    private func removeClickOutsideDismissal() {
        clickOutsideDismissal.deactivate()
        removeGlobalClickMonitor()
    }

    private func removeGlobalClickMonitor() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == HistoryKeyCodes.escape {
                self?.model?.hideSettings()
                return nil
            }
            return event
        }
    }
}
