import Foundation

enum LocalChatSessionStore {
    private static let maxSessions = 40

    private struct PersistedSession: Codable {
        let id: String
        let title: String
        let updatedAt: Date
        let messages: [PersistedMessage]
    }

    private struct PersistedMessage: Codable {
        let id: UUID
        let role: String
        let text: String
        let imagePaths: [String]
    }

    static func loadSessions(for workspacePath: String) -> [SavedChatSession] {
        let directory = sessionsDirectory(for: workspacePath)
        let fileManager = FileManager.default

        guard
            fileManager.fileExists(atPath: directory.path),
            let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var sessions: [SavedChatSession] = []

        for entry in entries where entry.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: entry),
                let persisted = try? JSONDecoder().decode(PersistedSession.self, from: data),
                !persisted.messages.isEmpty
            else {
                continue
            }

            let messages = persisted.messages.compactMap { persistedMessage -> ChatMessage? in
                let role: ChatMessage.Role = persistedMessage.role == "user" ? .user : .assistant
                guard !persistedMessage.text.isEmpty || !persistedMessage.imagePaths.isEmpty else { return nil }
                return ChatMessage(
                    id: persistedMessage.id,
                    role: role,
                    text: persistedMessage.text,
                    imagePaths: persistedMessage.imagePaths
                )
            }

            guard !messages.isEmpty else { continue }

            sessions.append(
                SavedChatSession(
                    id: persisted.id,
                    title: persisted.title,
                    updatedAt: persisted.updatedAt,
                    messages: messages
                )
            )
        }

        return sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxSessions)
            .map { $0 }
    }

    static func saveSession(
        id: String,
        messages: [ChatMessage],
        workspacePath: String
    ) {
        let completedMessages = messages.filter { message in
            !message.isStreaming && !(message.role == .assistant && message.text.isEmpty)
        }
        guard !completedMessages.isEmpty else { return }

        let title = title(for: completedMessages)
        let persisted = PersistedSession(
            id: id,
            title: title,
            updatedAt: Date(),
            messages: completedMessages.map {
                PersistedMessage(
                    id: $0.id,
                    role: $0.role.rawValue,
                    text: $0.text,
                    imagePaths: $0.imagePaths
                )
            }
        )

        let directory = sessionsDirectory(for: workspacePath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("\(id).json")
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func sessionsDirectory(for workspacePath: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slug = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default"
            : ChatSessionStore.projectSlug(for: workspacePath)
        return appSupport
            .appendingPathComponent("Cursor Popup", isDirectory: true)
            .appendingPathComponent("open-webui-sessions", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
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
