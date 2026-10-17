import AppKit

enum SnipPermission: Hashable {
    case screenCapture
    case microphone
}

/// On-screen warning shown when a screenshot or recording is started without
/// the privacy permissions macOS requires for capture.
@MainActor
final class SnipPermissionPromptController: NSObject, NSWindowDelegate {
    static let shared = SnipPermissionPromptController()

    private var panel: NSPanel?
    private var onOpenSettings: (() -> Void)?
    private var onRecordWithoutMicrophone: (() -> Void)?
    private var onDismiss: (() -> Void)?
    private var didFinish = false

    var isVisible: Bool { panel?.isVisible == true }

    func present(
        missing: Set<SnipPermission>,
        onOpenSettings: @escaping () -> Void,
        onRecordWithoutMicrophone: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        guard !missing.isEmpty else { return }

        if let panel {
            panel.delegate = nil
            panel.orderOut(nil)
            self.panel = nil
        }

        didFinish = false
        self.onOpenSettings = onOpenSettings
        self.onRecordWithoutMicrophone = onRecordWithoutMicrophone
        self.onDismiss = onDismiss

        let panel = makePanel(missing: missing)
        self.panel = panel
        positionOnActiveScreen(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async {
            guard panel === self.panel else { return }
            panel.orderFrontRegardless()
        }
    }

    func orderFront() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        finish()
    }

    private func makePanel(missing: Set<SnipPermission>) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Umbrella Helper"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = panel.contentView ?? NSView()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)

        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.cautionName)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: title(for: missing))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: message(for: missing))
        body.font = .systemFont(ofSize: 13)
        body.textColor = .labelColor
        body.preferredMaxLayoutWidth = 432
        body.translatesAutoresizingMaskIntoConstraints = false

        let openSettings = pushButton("Open Settings", action: #selector(openSettingsClicked))
        openSettings.keyEquivalent = "\r"

        let notNow = pushButton("Not Now", action: #selector(notNowClicked))
        notNow.keyEquivalent = "\u{1b}"

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(body)
        container.addSubview(openSettings)
        container.addSubview(notNow)

        var constraints = [
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),

            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            openSettings.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            openSettings.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            openSettings.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ]

        if missing == [.microphone], onRecordWithoutMicrophone != nil {
            let skip = pushButton("Record Without Microphone", action: #selector(skipMicrophoneClicked))
            container.addSubview(skip)
            constraints.append(contentsOf: [
                skip.centerYAnchor.constraint(equalTo: openSettings.centerYAnchor),
                skip.trailingAnchor.constraint(equalTo: openSettings.leadingAnchor, constant: -8),
                notNow.centerYAnchor.constraint(equalTo: openSettings.centerYAnchor),
                notNow.trailingAnchor.constraint(equalTo: skip.leadingAnchor, constant: -8),
            ])
        } else {
            constraints.append(contentsOf: [
                notNow.centerYAnchor.constraint(equalTo: openSettings.centerYAnchor),
                notNow.trailingAnchor.constraint(equalTo: openSettings.leadingAnchor, constant: -8),
            ])
        }

        NSLayoutConstraint.activate(constraints)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.topAnchor.constraint(equalTo: content.topAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            notNow.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
        ])

        let textBounds = NSRect(x: 0, y: 0, width: 432, height: CGFloat.greatestFiniteMagnitude)
        let titleHeight = title.cell?.cellSize(forBounds: textBounds).height ?? 20
        let bodyHeight = body.cell?.cellSize(forBounds: textBounds).height ?? 48
        let height = 16 + titleHeight + 6 + bodyHeight + 18 + 32 + 20
        panel.setContentSize(NSSize(width: 520, height: ceil(height)))
        return panel
    }

    private func pushButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func title(for missing: Set<SnipPermission>) -> String {
        switch (missing.contains(.screenCapture), missing.contains(.microphone)) {
        case (true, false):
            return "Screen Recording is off"
        case (false, true):
            return "Microphone access is off"
        default:
            return "Permissions needed"
        }
    }

    private func message(for missing: Set<SnipPermission>) -> String {
        switch (missing.contains(.screenCapture), missing.contains(.microphone)) {
        case (true, false):
            return "Umbrella Helper can’t take screenshots or record video until Screen Recording is allowed. Turn on Umbrella Helper in System Settings → Privacy & Security → Screen & System Audio Recording. If you just turned it on, quit and reopen the app."
        case (false, true):
            return "Record microphone is on, so this recording needs microphone access. Turn on Umbrella Helper in System Settings → Privacy & Security → Microphone."
        default:
            return "Umbrella Helper needs two permissions before this can work:\n\n• Screen & System Audio Recording — for screenshots and video\n• Microphone — because Record microphone is on\n\nTurn both on for Umbrella Helper in System Settings → Privacy & Security. If you just turned on Screen Recording, quit and reopen the app."
        }
    }

    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    private func finish(followedBy action: (() -> Void)? = nil) {
        guard !didFinish else { return }
        didFinish = true
        let dismiss = onDismiss
        let followUp = action
        onOpenSettings = nil
        onRecordWithoutMicrophone = nil
        onDismiss = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        dismiss?()
        followUp?()
    }

    @objc private func openSettingsClicked() {
        finish(followedBy: onOpenSettings)
    }

    @objc private func skipMicrophoneClicked() {
        finish(followedBy: onRecordWithoutMicrophone)
    }

    @objc private func notNowClicked() {
        finish()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
