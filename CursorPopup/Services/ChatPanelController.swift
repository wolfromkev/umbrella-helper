import AppKit
import SwiftUI

enum ChatPanelMetrics {
    static let panelWidth: CGFloat = 720
    static let compactBaseHeight: CGFloat = 118
    static let compactAttachmentHeight: CGFloat = 78
    static let expandedHeight: CGFloat = 560
    static let margin: CGFloat = 24
    static let contentWidth: CGFloat = panelWidth - 32

    static func compactHeight(attachmentCount: Int) -> CGFloat {
        attachmentCount > 0 ? compactBaseHeight + compactAttachmentHeight : compactBaseHeight
    }
}

@MainActor
final class ChatPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private weak var model: AppModel?
    private var localMonitor: Any?
    private var globalClickMonitor: Any?
    private let clickOutsideDismissal = ClickOutsideDismissal()
    private var activeScreen: NSScreen?

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        if panel == nil {
            let contentView = FloatingChatView()
                .environmentObject(model!)

            let hosting = NSHostingController(rootView: contentView)
            if #available(macOS 13.0, *) {
                hosting.sizingOptions = [.intrinsicContentSize]
            }

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: ChatPanelMetrics.panelWidth, height: ChatPanelMetrics.compactBaseHeight)
            )
            panel.delegate = self
            panel.isMovableByWindowBackground = true
            panel.contentViewController = hosting
            self.panel = panel
            installMonitors()
        }

        resizeToFitContent(animated: false)
        panel?.makeKeyAndOrderFront(nil)
        installClickOutsideDismissal()
        NotificationCenter.default.post(name: .focusChatInputField, object: nil)
    }

    func closePanel() {
        removeClickOutsideDismissal()
        panel?.orderOut(nil)
        model?.isChatBoxVisible = false
    }

    func resizeToFitContent(animated: Bool = true) {
        guard let panel else { return }

        let expanded = model?.hasChatConversation ?? false
        let screen = activeScreen ?? screenForChat()
        activeScreen = screen

        let currentFrame = panel.isVisible ? panel.frame : nil
        let attachmentCount = model?.pendingAttachments.count ?? 0
        let targetFrame = frame(
            forExpanded: expanded,
            attachmentCount: attachmentCount,
            on: screen,
            anchoringTo: currentFrame
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            window === panel,
            model?.isChatBoxVisible == true
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let panel = self.panel,
                self.model?.isChatBoxVisible == true,
                !panel.isKeyWindow
            else {
                return
            }
            self.model?.hideChatBox()
        }
    }

    private func frame(
        forExpanded expanded: Bool,
        attachmentCount: Int,
        on screen: NSScreen,
        anchoringTo currentFrame: NSRect?
    ) -> NSRect {
        let screenFrame = screen.visibleFrame
        let width = ChatPanelMetrics.panelWidth
        let height = expanded
            ? ChatPanelMetrics.expandedHeight
            : ChatPanelMetrics.compactHeight(attachmentCount: attachmentCount)

        var frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + ChatPanelMetrics.margin,
            width: width,
            height: height
        )

        if expanded, let currentFrame, currentFrame.width > width * 0.5 {
            let bottom = currentFrame.origin.y + currentFrame.height
            frame.origin.y = bottom - height
        }

        if frame.maxY > screenFrame.maxY {
            frame.origin.y = screenFrame.maxY - height
        }

        frame.origin.x = min(max(frame.origin.x, screenFrame.minX), screenFrame.maxX - width)
        frame.origin.y = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - height)
        return frame
    }

    private func screenForChat() -> NSScreen {
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
            self?.model?.hideChatBox()
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

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == HistoryKeyCodes.escape {
                self?.model?.hideChatBox()
                return nil
            }

            if HistoryKeyHandler.handle(event: event, model: self?.model) == nil {
                NotificationCenter.default.post(name: .focusChatInputField, object: nil)
                return nil
            }

            return event
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

extension Notification.Name {
    static let focusChatInputField = Notification.Name("focusChatInputField")
}
