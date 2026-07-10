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
