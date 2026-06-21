import AppKit

extension Notification.Name {
    static let menuBarIconVisibilityChanged = Notification.Name("menuBarIconVisibilityChanged")
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    private var visibilityObserver: NSObjectProtocol?

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
            statusItem?.isVisible = false
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "CursorPopupStatusItem"
        if let button = item.button {
            button.image = MenuBarIcon.image()
            button.toolTip = "Cursor Popup"
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Show Popup", action: #selector(showPopup)))
        menu.addItem(menuItem("Toggle Chat", action: #selector(toggleChat)))
        menu.addItem(menuItem("New Notion Task", action: #selector(showNotionTask)))
        menu.addItem(menuItem("Settings…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Hide Menu Bar Icon", action: #selector(hideMenuBarIcon)))
        menu.addItem(.separator())

        menu.addItem(menuItem("Restart", action: #selector(restartApp)))

        let quitItem = menuItem("Quit Cursor Popup", action: #selector(quitApp))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showPopup() {
        appModel?.showPopup()
    }

    @objc private func toggleChat() {
        appModel?.toggleChatBox()
    }

    @objc private func showNotionTask() {
        appModel?.showNotionTask()
    }

    @objc private func openSettings() {
        appModel?.showSettings()
    }

    @objc private func hideMenuBarIcon() {
        setVisible(false)
    }

    @objc private func restartApp() {
        AppRelauncher.restart()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
