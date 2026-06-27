import AppKit
import Foundation

enum CursorLauncher {
    private static let cursorAppPath = "/Applications/Cursor.app"
    private static let maxDeeplinkLength = 8_000
    private static let workspaceOpenDelay: TimeInterval = 1.0
    private static let agentsWindowOpenDelay: TimeInterval = 0.9

    /// Opens Cursor's Glass chat window, optionally focusing the configured workspace first.
    static func openCursorChat(workspace: String) {
        let workspacePath = (workspace as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let openedWorkspace = !workspacePath.isEmpty && openCursorWorkspace(workspacePath, reuseWindow: true)

        guard let glassURL = deeplinkURL(path: "/glass") else { return }

        let delay = openedWorkspace ? workspaceOpenDelay : 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSWorkspace.shared.open(glassURL)
        }
    }

    static func openInCursorAgent(
        workspace: String,
        messages: [ChatMessage],
        sessionID: String? = nil,
        handoffMode: CursorHandoffMode = .formattedHistory,
        handoffTarget: CursorHandoffTarget = .agentsWindow
    ) {
        let prompt = buildHandoffPrompt(
            from: messages,
            sessionID: sessionID,
            handoffMode: handoffMode
        )

        guard !prompt.isEmpty else { return }

        let workspacePath = (workspace as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let openedWorkspace = !workspacePath.isEmpty && openCursorWorkspace(workspacePath, reuseWindow: false)

        let initialDelay = openedWorkspace ? workspaceOpenDelay : 0.15
        switch handoffTarget {
        case .agentsWindow:
            handoffToAgentsWindow(prompt, delay: initialDelay)
        case .ideChat:
            handoffPrompt(prompt, mode: "agent", delay: initialDelay)
        }
    }

    private static func openCursorWorkspace(_ path: String, reuseWindow: Bool) -> Bool {
        let windowFlag = reuseWindow ? "-r" : "-n"
        if runCursorCLI(arguments: [windowFlag, path]) {
            return true
        }
        return openWorkspaceWithCursorApp(path)
    }

    private static func handoffPrompt(_ prompt: String, mode: String? = nil, delay: TimeInterval) {
        guard let url = promptDeeplinkURL(for: prompt, mode: mode) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the Agents window first, then sends the prompt deeplink so Glass can create a new agent.
    private static func handoffToAgentsWindow(_ prompt: String, delay: TimeInterval) {
        guard
            let glassURL = deeplinkURL(path: "/glass"),
            let promptURL = promptDeeplinkURL(for: prompt)
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSWorkspace.shared.open(glassURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + agentsWindowOpenDelay) {
                NSWorkspace.shared.open(promptURL)
            }
        }
    }

    private static func deeplinkURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "cursor"
        components.host = "anysphere.cursor-deeplink"
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private static func promptDeeplinkURL(for prompt: String, mode: String? = nil) -> URL? {
        var queryItems = [URLQueryItem(name: "text", value: prompt)]
        if let mode {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        return deeplinkURL(path: "/prompt", queryItems: queryItems)
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

    static func buildHandoffPrompt(
        from messages: [ChatMessage],
        sessionID: String? = nil,
        handoffMode: CursorHandoffMode = .formattedHistory
    ) -> String {
        let trimmedMessages = messages.compactMap { message -> ChatMessage? in
            let text = handoffText(for: message)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var copy = message
            copy.text = text
            return copy
        }

        guard !trimmedMessages.isEmpty else { return "" }

        if trimmedMessages.count == 1, let only = trimmedMessages.first, only.role == .user {
            return only.text
        }

        let prompt: String
        switch handoffMode {
        case .lastQuestion:
            prompt = buildLastQuestionHandoff(from: trimmedMessages, sessionID: sessionID)
        case .fullTranscript:
            prompt = buildLegacyTranscriptHandoff(from: trimmedMessages)
        case .formattedHistory:
            prompt = buildFormattedHistoryHandoff(from: trimmedMessages, sessionID: sessionID)
        }

        return trimForDeeplink(prompt)
    }

    private static func buildLastQuestionHandoff(
        from messages: [ChatMessage],
        sessionID: String?
    ) -> String {
        guard let lastUser = messages.last(where: { $0.role == .user }) else {
            return buildFormattedHistoryHandoff(from: messages, sessionID: sessionID)
        }

        var lines = [
            "Continuing from Umbrella Helper.",
            "",
            lastUser.text,
        ]

        if let sessionID {
            lines.append("")
            lines.append("_Popup session: \(sessionID)_")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildFormattedHistoryHandoff(
        from messages: [ChatMessage],
        sessionID: String?
    ) -> String {
        var lines = [
            "Please continue this conversation from Umbrella Helper.",
            "",
        ]

        for message in messages {
            let heading = message.role == .user ? "### You" : "### Assistant"
            lines.append(heading)
            lines.append("")
            lines.append(message.text)
            lines.append("")
        }

        if let sessionID {
            lines.append("_Popup session: \(sessionID)_")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildLegacyTranscriptHandoff(from messages: [ChatMessage]) -> String {
        let transcript = messages.map { message in
            let speaker = message.role == .user ? "Me" : "Assistant"
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n\n")

        return "Continue this conversation from Umbrella Helper:\n\n\(transcript)"
    }

    private static func trimForDeeplink(_ prompt: String) -> String {
        guard prompt.count > maxDeeplinkLength else { return prompt }

        let suffix = "\n\n[Truncated for Cursor deeplink length limit.]"
        let maxBodyLength = max(0, maxDeeplinkLength - suffix.count)
        let end = prompt.index(prompt.startIndex, offsetBy: maxBodyLength)
        return String(prompt[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }

    private static func handoffText(for message: ChatMessage) -> String {
        switch message.role {
        case .user:
            return message.text
        case .assistant:
            return AssistantMessageFormatter.displayText(from: message.text)
        }
    }

    private static func locateCursorCLI() -> String? {
        let candidates = [
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
            "/usr/local/bin/cursor",
            "/opt/homebrew/bin/cursor",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
