import AppKit
import SwiftUI

extension Notification.Name {
    static let menuBarIconVisibilityChanged = Notification.Name("menuBarIconVisibilityChanged")
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    private var visibilityObserver: NSObjectProtocol?
    private var popover: NSPopover?
    private lazy var statusMenu: NSMenu = makeStatusMenu()
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    func start(appModel: AppModel) {
        self.appModel = appModel

        visibilityObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let visible = notification.userInfo?["visible"] as? Bool ?? AppSettings.shared.showMenuBarIcon
            Task { @MainActor in
                self?.setVisible(visible)
            }
        }

        setVisible(AppSettings.shared.showMenuBarIcon)
    }

    func setVisible(_ visible: Bool) {
        AppSettings.shared.showMenuBarIcon = visible

        if visible {
            installIfNeeded()
            statusItem?.isVisible = true
        } else {
            hidePopover()
            statusItem?.isVisible = false
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "UmbrellaStatusItem"
        if let button = item.button {
            button.image = MenuBarIcon.image()
            button.title = ""
            button.toolTip = "Umbrella Helper — click for controls, right-click for menu"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Settings…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Restart", action: #selector(restartApp)))

        let quitItem = menuItem("Quit Umbrella Helper", action: #selector(quitApp))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            hidePopover()
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        statusMenu.popUp(positioning: nil, at: point, in: button)
    }

    private func togglePopover() {
        if popover?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let appModel, let button = statusItem?.button else { return }

        let popover = ensurePopover(appModel: appModel)
        if popover.isShown {
            return
        }

        // Pull the live light level before showing so sliders match reality
        // (NeewerLite reports numbers as strings; stale disk values can be wrong).
        Task { @MainActor in
            _ = await appModel.neewerLightFeature.refreshFromAPI()
            guard let button = self.statusItem?.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.isHighlighted = true
            NSApp.activate(ignoringOtherApps: true)
            self.startOutsideClickMonitoring()
        }
    }

    private func hidePopover() {
        stopOutsideClickMonitoring()
        popover?.performClose(nil)
        statusItem?.button?.isHighlighted = false
    }

    private func ensurePopover(appModel: AppModel) -> NSPopover {
        if let popover {
            return popover
        }

        let content = MenuBarControlsView(
            brightnessFeature: appModel.brightnessFeature,
            neewerFeature: appModel.neewerLightFeature,
            onOpenSettings: { [weak self] in
                self?.hidePopover()
                self?.openSettings()
            }
        )

        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]

        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover
        return popover
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.dismissIfClickOutside()
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfClickOutside()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func dismissIfClickOutside() {
        guard popover?.isShown == true else { return }

        let location = NSEvent.mouseLocation

        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let buttonScreenRect = buttonWindow.convertToScreen(buttonRect).insetBy(dx: -2, dy: -2)
            if buttonScreenRect.contains(location) {
                return
            }
        }

        if let popoverWindow = popover?.contentViewController?.view.window {
            if popoverWindow.frame.contains(location) {
                return
            }
        }

        hidePopover()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        statusItem?.button?.isHighlighted = false
    }

    @objc private func openSettings() {
        appModel?.showSettings()
    }

    @objc private func restartApp() {
        AppRelauncher.restart()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
