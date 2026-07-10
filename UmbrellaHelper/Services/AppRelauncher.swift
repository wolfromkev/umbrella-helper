import AppKit
import Foundation

enum AppRelauncher {
    private static let pendingRelaunchTimestampKey = "pendingRelaunchTimestamp"
    private static let relaunchGraceInterval: TimeInterval = 30

    static var isPendingRelaunch: Bool {
        if CommandLine.arguments.contains("--relaunch") {
            return true
        }
        guard let timestamp = UserDefaults.standard.object(forKey: pendingRelaunchTimestampKey) as? TimeInterval else {
            return false
        }
        let isRecent = Date().timeIntervalSince1970 - timestamp < relaunchGraceInterval
        if isRecent {
            UserDefaults.standard.removeObject(forKey: pendingRelaunchTimestampKey)
        }
        return isRecent
    }

    static func restart(onFailure: ((String) -> Void)? = nil) {
        let appPath = Bundle.main.bundlePath
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingRelaunchTimestampKey)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appPath, "--args", "--relaunch"]

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                UserDefaults.standard.removeObject(forKey: pendingRelaunchTimestampKey)
                onFailure?("open exit \(task.terminationStatus)")
                return
            }
            NSApp.terminate(nil)
        } catch {
            UserDefaults.standard.removeObject(forKey: pendingRelaunchTimestampKey)
            onFailure?(error.localizedDescription)
        }
    }
}
