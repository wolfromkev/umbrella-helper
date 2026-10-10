import AppKit
import Foundation

enum AppRelauncher {
    static func restart(onFailure: ((String) -> Void)? = nil) {
        #if APP_STORE
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    onFailure?(error.localizedDescription)
                    return
                }
                NSApp.terminate(nil)
            }
        }
        #else
        let appPath = Bundle.main.bundlePath

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appPath]

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                onFailure?("open exit \(task.terminationStatus)")
                return
            }
            NSApp.terminate(nil)
        } catch {
            onFailure?(error.localizedDescription)
        }
        #endif
    }
}
