import AppKit
import SwiftUI

enum SettingsPanelMetrics {
    static let defaultWidth: CGFloat = 860
    static let defaultHeight: CGFloat = 640
    static let minWidth: CGFloat = 720
    static let minHeight: CGFloat = 560
}

@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        if window == nil {
            let contentView = SettingsView()
                .environmentObject(model!)
                .environmentObject(model!)
                .frame(
                    minWidth: SettingsPanelMetrics.defaultWidth,
                    minHeight: SettingsPanelMetrics.defaultHeight
                )

            let hosting = NSHostingController(rootView: contentView)
            hosting.sizingOptions = []
            hosting.preferredContentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )
            hosting.view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hosting.view.setContentHuggingPriority(.defaultLow, for: .vertical)
            hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

            let contentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Umbrella Helper Settings"
            window.delegate = self
            window.contentViewController = hosting
            window.setContentSize(contentSize)
            window.minSize = NSSize(
                width: SettingsPanelMetrics.minWidth,
                height: SettingsPanelMetrics.minHeight
            )
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            self.window = window
        } else if let window, window.frame.height < SettingsPanelMetrics.minHeight {
            let contentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )
            window.setContentSize(contentSize)
            window.center()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePanel() {
        window?.orderOut(nil)
        model?.isSettingsVisible = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.isSettingsVisible = false
        sender.orderOut(nil)
        return false
    }
}
