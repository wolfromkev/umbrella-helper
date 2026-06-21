import AppKit
import SwiftUI

@MainActor
final class NotionTaskPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private weak var model: AppModel?
    private var keyMonitor: Any?
    private var mouseDownMonitor: Any?
    private var globalClickMonitor: Any?
    private let clickOutsideDismissal = ClickOutsideDismissal()
    private var isClosing = false
    private var activeScreen: NSScreen?

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        isClosing = false
        activeScreen = ActiveScreenTracker.presentationScreen(excluding: panel)

        if panel == nil {
            let contentView = NotionTaskContentView()
                .environmentObject(model!)

            let hosting = NSHostingController(rootView: contentView)
            if #available(macOS 13.0, *) {
                hosting.sizingOptions = [.intrinsicContentSize]
            }

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 588, height: 120)
            )
            panel.delegate = self
            panel.contentViewController = hosting
            self.panel = panel
            installKeyMonitor()
        }

        resizeToFitContent(animated: false)
        presentFromBottom()
        installClickOutsideDismissal()
        focusTaskField()
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
            self.model?.isNotionTaskVisible = false
        }
    }

    func focusTaskField() {
        NotificationCenter.default.post(name: .focusNotionTaskField, object: nil)
    }

    var hasKeyboardFocus: Bool {
        guard model?.isNotionTaskVisible == true else { return false }
        return panel?.isKeyWindow == true
    }

    func resizeToFitContent(animated: Bool = true) {
        guard let panel, let contentView = panel.contentView else { return }

        let screen = activeScreen ?? ActiveScreenTracker.presentationScreen(excluding: panel)
        activeScreen = screen

        contentView.layoutSubtreeIfNeeded()
        let fittingHeight = contentView.fittingSize.height
        let width = max(contentView.fittingSize.width + 28, 588)
        let height = max(PanelMetrics.minHeight, min(fittingHeight, PanelMetrics.maxHeight))
        let targetFrame = bottomCenterFrame(width: width, height: height, on: screen)

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
            model?.isNotionTaskVisible == true,
            !isClosing
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let panel = self.panel,
                self.model?.isNotionTaskVisible == true,
                !panel.isKeyWindow,
                !self.isClosing
            else {
                return
            }
            self.model?.hideNotionTask()
        }
    }

    private func bottomCenterFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + PanelAnimation.bottomMargin,
            width: width,
            height: height
        )
    }

    private func presentFromBottom() {
        guard let panel else { return }

        let screen = activeScreen ?? ActiveScreenTracker.presentationScreen(excluding: panel)
        let screenFrame = screen.visibleFrame
        let targetFrame = bottomCenterFrame(
            width: panel.frame.width,
            height: panel.frame.height,
            on: screen
        )
        let startFrame = NSRect(
            x: targetFrame.origin.x,
            y: screenFrame.minY + PanelAnimation.bottomMargin - PanelAnimation.slideOffset,
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
            self?.model?.hideNotionTask()
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
            guard let self, let panel = self.panel, panel.isKeyWindow else {
                return event
            }

            if event.keyCode == HistoryKeyCodes.escape {
                self.model?.hideNotionTask()
                return nil
            }
            return event
        }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else {
                return event
            }

            let locationInWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
            if panel.contentView?.hitTest(locationInWindow) != nil {
                panel.makeKey()
            }
            return event
        }
    }
}

extension Notification.Name {
    static let focusNotionTaskField = Notification.Name("focusNotionTaskField")
}
