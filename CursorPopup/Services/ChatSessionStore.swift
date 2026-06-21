import Foundation

struct SavedChatSession: Identifiable, Equatable {
    let id: String
    let title: String
    let updatedAt: Date
    let messages: [ChatMessage]
}

enum ChatSessionStore {
    private static let maxSessions = 40

    static func loadSessions(for workspacePath: String) -> [SavedChatSession] {
        guard let transcriptsRoot = transcriptsDirectory(for: workspacePath) else { return [] }

        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: transcriptsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var sessions: [SavedChatSession] = []

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let sessionID = entry.lastPathComponent
            let transcriptURL = entry.appendingPathComponent("\(sessionID).jsonl")
            guard fileManager.fileExists(atPath: transcriptURL.path) else { continue }

            let values = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey])
            let updatedAt = values?.contentModificationDate ?? Date.distantPast
            let messages = parseTranscript(at: transcriptURL)
            guard !messages.isEmpty else { continue }

            let title = title(for: messages)
            sessions.append(
                SavedChatSession(
                    id: sessionID,
                    title: title,
                    updatedAt: updatedAt,
                    messages: messages
                )
            )
        }

        return sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxSessions)
            .map { $0 }
    }

    static func transcriptsDirectory(for workspacePath: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let slug = projectSlug(for: workspacePath)
        let directory = home
            .appendingPathComponent(".cursor/projects")
            .appendingPathComponent(slug)
            .appendingPathComponent("agent-transcripts")

        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }

        return directory
    }

    static func projectSlug(for workspacePath: String) -> String {
        var path = workspacePath
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func parseTranscript(at url: URL) -> [ChatMessage] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var messages: [ChatMessage] = []

        for line in data.split(whereSeparator: \.isNewline) {
            guard
                let lineData = String(line).data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let roleString = json["role"] as? String,
                let messageObject = json["message"] as? [String: Any],
                let contentItems = messageObject["content"] as? [[String: Any]]
            else {
                continue
            }

            let text = contentItems.compactMap { item -> String? in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }.joined()

            let cleaned = cleanText(text, role: roleString)
            guard !cleaned.isEmpty else { continue }

            let role: ChatMessage.Role = roleString == "user" ? .user : .assistant
            messages.append(ChatMessage(role: role, text: cleaned))
        }

        return messages
    }

    private static func cleanText(_ text: String, role: String) -> String {
        var cleaned = text
        if role == "user" {
            cleaned = cleaned.replacingOccurrences(of: "<user_query>", with: "")
            cleaned = cleaned.replacingOccurrences(of: "</user_query>", with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "[Image]", with: "")
        cleaned = cleaned.replacingOccurrences(of: "[REDACTED]", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func title(for messages: [ChatMessage]) -> String {
        let source = messages.first(where: { $0.role == .user })?.text
            ?? messages.first?.text
            ?? "Previous chat"

        let singleLine = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= 42 {
            return singleLine
        }

        return String(singleLine.prefix(39)) + "..."
    }
}
