import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum PanelMetrics {
    static let popupWidth: CGFloat = 720
    static let minHeight: CGFloat = 120
    static let maxHeight: CGFloat = 560
}

enum PanelAnimation {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.18
    static let resizeDuration: TimeInterval = 0.20
    static let bottomMargin: CGFloat = 24
    static let slideOffset: CGFloat = 18

    static let showTiming = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    static let hideTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    static let resizeTiming = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private weak var model: AppModel?
    private var keyMonitor: Any?
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
            let contentView = PopupContentView()
                .environmentObject(model!)

            let hosting = NSHostingController(rootView: contentView)
            if #available(macOS 13.0, *) {
                hosting.sizingOptions = [.intrinsicContentSize]
            }

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.popupWidth, height: 160)
            )
            panel.delegate = self
            panel.contentViewController = hosting
            self.panel = panel
            installKeyMonitor()
        }

        resizeToFitContent(animated: false)
        presentFromBottom()
        installClickOutsideDismissal()
        focusPrompt()
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
            self.model?.isVisible = false
        }
    }

    func focusPrompt() {
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }

    func resizeToFitContent(animated: Bool = true) {
        guard let panel, let contentView = panel.contentView else { return }

        let screen = activeScreen ?? ActiveScreenTracker.presentationScreen(excluding: panel)
        activeScreen = screen

        contentView.layoutSubtreeIfNeeded()
        let fittingHeight = contentView.fittingSize.height
        let width = PanelMetrics.popupWidth
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
            model?.isVisible == true,
            model?.preventsAutoDismiss != true,
            !isClosing
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let panel = self.panel,
                self.model?.isVisible == true,
                self.model?.preventsAutoDismiss != true,
                !panel.isKeyWindow,
                !self.isClosing
            else {
                return
            }
            self.model?.hidePopup()
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
            guard self?.model?.preventsAutoDismiss != true else { return }
            self?.model?.hidePopup()
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
                self.model?.hidePopup()
                return nil
            }

            if HistoryKeyHandler.handle(event: event, model: self.model) == nil {
                self.focusPrompt()
                return nil
            }

            return event
        }
    }
}

extension Notification.Name {
    static let focusPromptField = Notification.Name("focusPromptField")
}
