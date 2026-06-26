import AppKit
import SwiftUI

enum ChatPanelMetrics {
    static let panelWidth: CGFloat = 720
    static let compactBaseHeight: CGFloat = 118
    static let compactAttachmentHeight: CGFloat = 78
    static let expandedMaxHeight: CGFloat = 560
    static let expandedMinHeight: CGFloat = 220
    static let margin: CGFloat = 24
    static let contentWidth: CGFloat = panelWidth - 32
    static let outerPadding: CGFloat = 16
    static let messageBubbleMaxWidth: CGFloat = contentWidth - 88

    /// Header, dividers, input, footer — everything except the messages scroll area.
    static let expandedChromeHeight: CGFloat = 178
    static let messagesMaxHeight: CGFloat = expandedMaxHeight - expandedChromeHeight

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
    private var isClosing = false

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        isClosing = false
        activeScreen = ActiveScreenTracker.presentationScreen(excluding: panel)

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
        presentFromBottom()
        installClickOutsideDismissal()
        NotificationCenter.default.post(name: .focusChatInputField, object: nil)
    }

    func closePanel() {
        guard let panel, !isClosing else { return }

        isClosing = true
        activeScreen = nil
        removeClickOutsideDismissal()

        let targetOrigin = NSPoint(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y - PanelAnimation.slideOffset
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelAnimation.hideDuration
            context.timingFunction = PanelAnimation.hideTiming
            panel.animator().setFrameOrigin(targetOrigin)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
            self.isClosing = false
            self.model?.isChatBoxVisible = false
        }
    }

    func resizeToFitContent(animated: Bool = true) {
        guard let panel else { return }

        let expanded = model?.hasChatConversation ?? false
        let screen = activeScreen ?? ActiveScreenTracker.presentationScreen(excluding: panel)
        activeScreen = screen

        let currentFrame = panel.isVisible ? panel.frame : nil
        let attachmentCount = model?.pendingAttachments.count ?? 0

        let height: CGFloat
        if expanded, let contentView = panel.contentView {
            contentView.layoutSubtreeIfNeeded()
            let fittingHeight = contentView.fittingSize.height
            height = max(
                ChatPanelMetrics.expandedMinHeight,
                min(fittingHeight, ChatPanelMetrics.expandedMaxHeight)
            )
        } else {
            height = ChatPanelMetrics.compactHeight(attachmentCount: attachmentCount)
        }

        let targetFrame = frame(
            width: ChatPanelMetrics.panelWidth,
            height: height,
            on: screen,
            anchoringTo: currentFrame,
            expanded: expanded
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelAnimation.resizeDuration
                context.timingFunction = PanelAnimation.resizeTiming
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
            model?.isChatBoxVisible == true,
            model?.preventsAutoDismiss != true
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let panel = self.panel,
                self.model?.isChatBoxVisible == true,
                self.model?.preventsAutoDismiss != true,
                !panel.isKeyWindow,
                !self.isClosing
            else {
                return
            }
            self.model?.hideChatBox()
        }
    }

    private func frame(
        width: CGFloat,
        height: CGFloat,
        on screen: NSScreen,
        anchoringTo currentFrame: NSRect?,
        expanded: Bool
    ) -> NSRect {
        let screenFrame = screen.visibleFrame

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

    private func presentFromBottom() {
        guard let panel else { return }

        let screen = activeScreen ?? ActiveScreenTracker.presentationScreen(excluding: panel)
        let screenFrame = screen.visibleFrame
        let targetFrame = panel.frame
        let startFrame = NSRect(
            x: targetFrame.origin.x,
            y: screenFrame.minY + ChatPanelMetrics.margin - PanelAnimation.slideOffset,
            width: targetFrame.width,
            height: targetFrame.height
        )

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.level = .floating

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelAnimation.showDuration
            context.timingFunction = PanelAnimation.showTiming
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func installClickOutsideDismissal() {
        guard let panel else { return }

        clickOutsideDismissal.activate(for: panel) { [weak self] in
            guard self?.model?.preventsAutoDismiss != true else { return }
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
            guard let self, let panel = self.panel, panel.isKeyWindow else {
                return event
            }

            if event.keyCode == HistoryKeyCodes.escape {
                self.model?.hideChatBox()
                return nil
            }

            if HistoryKeyHandler.handle(event: event, model: self.model) == nil {
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
