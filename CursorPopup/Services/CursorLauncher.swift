import AppKit
import Foundation

enum CursorLauncher {
    private static let cursorAppPath = "/Applications/Cursor.app"

    static func openInCursorAgent(workspace: String, messages: [ChatMessage]) {
        let prompt = buildHandoffPrompt(from: messages)

        if runCursorCLI(arguments: ["--glass", "-n", workspace]) {
            handoffPrompt(prompt, delay: 0.45)
            return
        }

        openWorkspaceWithCursorApp(workspace)
        handoffPrompt(prompt, delay: 0.5)
    }

    private static func handoffPrompt(_ prompt: String, delay: TimeInterval) {
        guard !prompt.isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard
                let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let url = URL(string: "cursor://anysphere.cursor-deeplink/prompt?text=\(encoded)")
            else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private static func openWorkspaceWithCursorApp(_ path: String) -> Bool {
        let workspaceURL = URL(fileURLWithPath: path)
        let cursorURL = URL(fileURLWithPath: cursorAppPath)

        guard FileManager.default.fileExists(atPath: cursorAppPath) else {
            NSWorkspace.shared.open(workspaceURL)
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(
            [workspaceURL],
            withApplicationAt: cursorURL,
            configuration: configuration
        ) { _, error in
            if error != nil {
                NSWorkspace.shared.open(workspaceURL)
            }
        }

        return true
    }

    @discardableResult
    private static func runCursorCLI(arguments: [String]) -> Bool {
        guard let cursorCLI = locateCursorCLI() else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cursorCLI)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func buildHandoffPrompt(from messages: [ChatMessage]) -> String {
        let trimmedMessages = messages.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !trimmedMessages.isEmpty else { return "" }

        if trimmedMessages.count == 1, let only = trimmedMessages.first, only.role == .user {
            return only.text
        }

        let transcript = trimmedMessages.map { message in
            let speaker = message.role == .user ? "Me" : "Assistant"
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n\n")

        return "Continue this conversation from Cursor Popup:\n\n\(transcript)"
    }

    private static func locateCursorCLI() -> String? {
        let candidates = ["/usr/local/bin/cursor", "/opt/homebrew/bin/cursor"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
