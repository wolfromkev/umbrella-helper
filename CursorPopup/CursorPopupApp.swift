import SwiftUI

@main
struct UmbrellaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Empty scene only — real settings UI lives in SettingsPanelController.
        // A populated Settings scene auto-opens on launch for accessory apps.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.appModel.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appModel.start()
        menuBarController.start(appModel: appModel)
        dismissAutoOpenedSettingsWindows()
    }

    private func dismissAutoOpenedSettingsWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeKey {
                window.orderOut(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appModel.showSettings()
        return true
    }
}
