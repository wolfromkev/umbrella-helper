import AppKit

enum AppRelauncher {
    static func restart() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do
          /bin/sleep 0.1
        done
        /usr/bin/open "\(bundlePath)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // Fall back to a delayed open if the helper process fails to start.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSWorkspace.shared.open(URL(fileURLWithPath: bundlePath))
            }
        }

        NSApp.terminate(nil)
    }
}
