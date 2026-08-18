import AppKit
import Foundation

enum AppRelauncher {
    static func restart(onFailure: ((String) -> Void)? = nil) {
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
    }
}
