import AppKit
import ApplicationServices

enum SystemPermissions {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        )
    }

    static func openAutomationSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
        )
    }

    static func openLoginItemsSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }

    private static func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
