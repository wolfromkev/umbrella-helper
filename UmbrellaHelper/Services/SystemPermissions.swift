import AppKit
import ApplicationServices

enum SystemPermissions {
    private static var lastMonitorProbe: Date?
    private static var lastMonitorProbeResult = false
    private static let monitorProbeInterval: TimeInterval = 3

    /// True when macOS allows global event monitoring (click-outside + active screen).
    /// Uses a functional probe because `AXIsProcessTrusted()` can stay false after
    /// ad-hoc rebuilds even when the app is enabled in System Settings.
    static var isAccessibilityGranted: Bool {
        if AXIsProcessTrusted() { return true }
        return canInstallGlobalEventMonitor()
    }

    static var runningAppPath: String {
        Bundle.main.bundlePath
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

    static func openLoginItemsSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }

    private static func canInstallGlobalEventMonitor() -> Bool {
        if let lastMonitorProbe,
           Date().timeIntervalSince(lastMonitorProbe) < monitorProbeInterval {
            return lastMonitorProbeResult
        }

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { _ in }
        let granted = monitor != nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        lastMonitorProbe = Date()
        lastMonitorProbeResult = granted
        return granted
    }

    private static func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
