import AppKit
import Foundation

enum OpenWebUILauncher {
    private static let bundleIdentifier = "com.openwebui.desktop"
    private static let defaultAppPath = "/Applications/Open WebUI.app"

    static func openApp(chatID: String? = nil) {
        if let chatID, !chatID.isEmpty, AppSettings.shared.openWebUISyncChats {
            openSyncedChat(chatID)
            return
        }

        activateOrLaunchApp()
    }

    private static func openSyncedChat(_ chatID: String) {
        activateOrLaunchApp()

        let chatURLString = "\(AppSettings.shared.normalizedOpenWebUIBaseURL)/c/\(chatID)"
        guard let chatURL = URL(string: chatURLString) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.open(chatURL)
        }
    }

    private static func activateOrLaunchApp() {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            launchApp(at: appURL)
            return
        }

        let fallbackURL = URL(fileURLWithPath: defaultAppPath)
        guard FileManager.default.fileExists(atPath: fallbackURL.path) else { return }
        launchApp(at: fallbackURL)
    }

    private static func launchApp(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, _ in
            app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}
