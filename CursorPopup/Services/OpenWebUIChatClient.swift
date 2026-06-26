import Foundation

struct OpenWebUIChatTurn {
    let userMessageID: UUID
    let assistantMessageID: UUID
    let userText: String
    let imagePaths: [String]
}

struct OpenWebUIProject: Identifiable, Equatable, Codable {
    let id: String
    let name: String
}

enum OpenWebUIChatClient {
    private static func authHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ]
    }

    static func credentials() throws -> (baseURL: String, apiKey: String, model: String) {
        let settings = AppSettings.shared
        let baseURL = settings.normalizedOpenWebUIBaseURL
        let model = settings.openWebUIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            throw OpenWebUIError.apiError("Set your Open WebUI server URL in Settings.")
        }
        guard !model.isEmpty else {
            throw OpenWebUIError.apiError("Set the model name in Settings.")
        }
        guard let apiKey = KeychainStorage.openWebUIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw OpenWebUIError.apiError("Add your Open WebUI API key in Settings.")
        }
        return (baseURL, apiKey, model)
    }

    static func createChat(
        turn: OpenWebUIChatTurn,
        model: String,
        title: String? = nil,
        folderID: String? = AppSettings.shared.openWebUIActiveFolderID
    ) async throws -> String {
        let (baseURL, apiKey, _) = try credentials()
        guard let url = URL(string: "\(baseURL)/api/v1/chats/new") else {
            throw OpenWebUIError.invalidURL
        }

        var payload = buildNewChatPayload(
            turn: turn,
            model: model,
            chatTitle: title
        )
        payload["folder_id"] = folderID ?? NSNull()

        let data = try await postJSON(to: url, payload: payload, headers: authHeaders(apiKey: apiKey))
        return try parseChatID(from: data)
    }

    static func fetchProjects() async throws -> [OpenWebUIProject] {
        let (baseURL, apiKey, _) = try credentials()
        guard let url = URL(string: "\(baseURL)/api/v1/folders/") else {
            throw OpenWebUIError.invalidURL
        }

        let data = try await getJSON(from: url, headers: authHeaders(apiKey: apiKey))
        guard let folders = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let projects = folders.compactMap { folder -> OpenWebUIProject? in
            guard
                let id = folder["id"] as? String,
                let name = folder["name"] as? String,
                !id.isEmpty,
                !name.isEmpty
            else {
                return nil
            }
            return OpenWebUIProject(id: id, name: name)
        }

        return projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func appendTurn(
        chatID: String,
        turn: OpenWebUIChatTurn,
        model: String
    ) async throws {
        let (baseURL, apiKey, _) = try credentials()
        guard let getURL = URL(string: "\(baseURL)/api/v1/chats/\(chatID)") else {
            throw OpenWebUIError.invalidURL
        }

        let existingData = try await getJSON(from: getURL, headers: authHeaders(apiKey: apiKey))
        let updatedPayload = try buildUpdatedChatPayload(
            existingData: existingData,
            chatID: chatID,
            turn: turn,
            model: model
        )

        guard let updateURL = URL(string: "\(baseURL)/api/v1/chats/\(chatID)") else {
            throw OpenWebUIError.invalidURL
        }
        _ = try await postJSON(to: updateURL, payload: updatedPayload, headers: authHeaders(apiKey: apiKey))
    }

    static func syncConversation(
        messages: [ChatMessage],
        model: String,
        existingChatID: String?
    ) async throws -> (chatID: String, assistantMessageID: UUID, streamSessionID: String) {
        let completed = messages.filter {
            !$0.isStreaming && !($0.role == .assistant && $0.text.isEmpty)
        }
        guard let lastUser = completed.last(where: { $0.role == .user }) else {
            throw OpenWebUIError.apiError("Nothing to sync.")
        }

        let turn = OpenWebUIChatTurn(
            userMessageID: lastUser.id,
            assistantMessageID: UUID(),
            userText: lastUser.text,
            imagePaths: lastUser.imagePaths
        )
        let streamSessionID = UUID().uuidString

        if let existingChatID, !existingChatID.isEmpty {
            try await appendTurn(chatID: existingChatID, turn: turn, model: model)
            return (existingChatID, turn.assistantMessageID, streamSessionID)
        }

        let title = title(for: completed)
        let chatID = try await createChat(turn: turn, model: model, title: title)
        return (chatID, turn.assistantMessageID, streamSessionID)
    }

    static func pushFullConversation(
        messages: [ChatMessage],
        model: String
    ) async throws -> String {
        let completed = messages.filter {
            !$0.isStreaming && !($0.role == .assistant && $0.text.isEmpty)
        }
        guard !completed.isEmpty else {
            throw OpenWebUIError.apiError("Nothing to sync.")
        }

        let (baseURL, apiKey, _) = try credentials()
        guard let url = URL(string: "\(baseURL)/api/v1/chats/new") else {
            throw OpenWebUIError.invalidURL
        }

        var payload = buildFullConversationPayload(messages: completed, model: model)
        payload["folder_id"] = AppSettings.shared.openWebUIActiveFolderID ?? NSNull()

        let data = try await postJSON(to: url, payload: payload, headers: authHeaders(apiKey: apiKey))
        return try parseChatID(from: data)
    }

    static func loadSessions(limit: Int = 40) async throws -> [SavedChatSession] {
        let (baseURL, apiKey, _) = try credentials()
        guard let url = URL(string: "\(baseURL)/api/v1/chats/?page=1") else {
            throw OpenWebUIError.invalidURL
        }

        let data = try await getJSON(from: url, headers: authHeaders(apiKey: apiKey))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var sessions: [SavedChatSession] = []
        for item in json.prefix(limit) {
            guard
                let chatID = item["id"] as? String,
                let detailURL = URL(string: "\(baseURL)/api/v1/chats/\(chatID)")
            else { continue }

            do {
                let detailData = try await getJSON(from: detailURL, headers: authHeaders(apiKey: apiKey))
                if let session = parseSavedSession(chatID: chatID, listItem: item, detailData: detailData) {
                    sessions.append(session)
                }
            } catch {
                continue
            }
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func buildNewChatPayload(
        turn: OpenWebUIChatTurn,
        model: String,
        chatTitle: String?
    ) -> [String: Any] {
        let userID = turn.userMessageID.uuidString
        let assistantID = turn.assistantMessageID.uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        let userMessage: [String: Any] = [
            "id": userID,
            "role": "user",
            "content": turn.userText,
            "timestamp": timestamp,
            "models": [model],
            "childrenIds": [assistantID],
        ]

        let assistantMessage: [String: Any] = [
            "id": assistantID,
            "role": "assistant",
            "content": "",
            "parentId": userID,
            "childrenIds": [] as [String],
            "model": model,
            "modelName": model,
            "modelIdx": 0,
            "done": false,
            "timestamp": timestamp + 1,
        ]

        return [
            "chat": [
                "title": chatTitle ?? title(for: turn.userText),
                "models": [model],
                "messages": [userMessage, assistantMessage],
                "history": [
                    "currentId": assistantID,
                    "messages": [
                        userID: userMessage,
                        assistantID: assistantMessage,
                    ],
                ],
            ] as [String: Any],
        ]
    }

    private static func buildFullConversationPayload(
        messages: [ChatMessage],
        model: String
    ) -> [String: Any] {
        var historyMessages: [String: [String: Any]] = [:]
        var flatMessages: [[String: Any]] = []
        var previousID: String?
        var currentID: String?
        let baseTimestamp = Int(Date().timeIntervalSince1970)

        for (index, message) in messages.enumerated() {
            let messageID = message.id.uuidString
            let timestamp = baseTimestamp + index
            var entry: [String: Any] = [
                "id": messageID,
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text,
                "timestamp": timestamp,
                "childrenIds": [] as [String],
            ]

            if message.role == .user {
                entry["models"] = [model]
            } else {
                entry["model"] = model
                entry["modelName"] = model
                entry["modelIdx"] = 0
                entry["done"] = true
            }

            if let previousID {
                entry["parentId"] = previousID
                var parent = historyMessages[previousID] ?? [:]
                var children = parent["childrenIds"] as? [String] ?? []
                children.append(messageID)
                parent["childrenIds"] = children
                historyMessages[previousID] = parent
            }

            historyMessages[messageID] = entry
            flatMessages.append(entry)
            previousID = messageID
            currentID = messageID
        }

        return [
            "chat": [
                "title": title(for: messages),
                "models": [model],
                "messages": flatMessages,
                "history": [
                    "currentId": currentID ?? "",
                    "messages": historyMessages,
                ],
            ] as [String: Any],
        ]
    }

    private static func buildUpdatedChatPayload(
        existingData: Data,
        chatID: String,
        turn: OpenWebUIChatTurn,
        model: String
    ) throws -> [String: Any] {
        guard
            let root = try JSONSerialization.jsonObject(with: existingData) as? [String: Any],
            var chat = root["chat"] as? [String: Any],
            var history = chat["history"] as? [String: Any],
            var historyMessages = history["messages"] as? [String: [String: Any]],
            var flatMessages = chat["messages"] as? [[String: Any]]
        else {
            throw OpenWebUIError.invalidResponse
        }

        let previousID = history["currentId"] as? String ?? flatMessages.last?["id"] as? String
        let userID = turn.userMessageID.uuidString
        let assistantID = turn.assistantMessageID.uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        if let previousID, var previous = historyMessages[previousID] {
            var children = previous["childrenIds"] as? [String] ?? []
            if !children.contains(userID) {
                children.append(userID)
            }
            previous["childrenIds"] = children
            historyMessages[previousID] = previous
        }

        let userMessage: [String: Any] = [
            "id": userID,
            "role": "user",
            "content": turn.userText,
            "timestamp": timestamp,
            "models": [model],
            "parentId": previousID as Any,
            "childrenIds": [assistantID],
        ]

        let assistantMessage: [String: Any] = [
            "id": assistantID,
            "role": "assistant",
            "content": "",
            "parentId": userID,
            "childrenIds": [] as [String],
            "model": model,
            "modelName": model,
            "modelIdx": 0,
            "done": false,
            "timestamp": timestamp + 1,
        ]

        historyMessages[userID] = userMessage
        historyMessages[assistantID] = assistantMessage
        flatMessages.append(userMessage)
        flatMessages.append(assistantMessage)

        history["currentId"] = assistantID
        history["messages"] = historyMessages
        chat["id"] = chatID
        chat["history"] = history
        chat["messages"] = flatMessages
        chat["models"] = [model]

        return ["chat": chat]
    }

    private static func parseChatID(from data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chatID = json["id"] as? String ?? (json["chat"] as? [String: Any])?["id"] as? String,
            !chatID.isEmpty
        else {
            throw OpenWebUIError.invalidResponse
        }
        return chatID
    }

    private static func parseSavedSession(
        chatID: String,
        listItem: [String: Any],
        detailData: Data
    ) -> SavedChatSession? {
        guard
            let root = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
            let chat = root["chat"] as? [String: Any],
            let history = chat["history"] as? [String: Any],
            let historyMessages = history["messages"] as? [String: [String: Any]]
        else {
            return nil
        }

        let ordered = orderedMessages(from: historyMessages, currentID: history["currentId"] as? String)
        let messages = ordered.compactMap { entry -> ChatMessage? in
            guard let role = entry["role"] as? String else { return nil }
            let text = entry["content"] as? String ?? ""
            guard !text.isEmpty else { return nil }
            let messageRole: ChatMessage.Role = role == "user" ? .user : .assistant
            let idString = entry["id"] as? String
            let id = idString.flatMap(UUID.init(uuidString:)) ?? UUID()
            return ChatMessage(id: id, role: messageRole, text: text)
        }

        guard !messages.isEmpty else { return nil }

        let title = (chat["title"] as? String)
            ?? (listItem["title"] as? String)
            ?? ChatSessionStoreTitleFallback.title(for: messages)

        let updatedAt: Date
        if let updated = listItem["updated_at"] as? TimeInterval {
            updatedAt = Date(timeIntervalSince1970: updated)
        } else if let timestamp = chat["timestamp"] as? TimeInterval {
            updatedAt = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            updatedAt = Date()
        }

        return SavedChatSession(id: chatID, title: title, updatedAt: updatedAt, messages: messages)
    }

    private static func orderedMessages(
        from historyMessages: [String: [String: Any]],
        currentID: String?
    ) -> [[String: Any]] {
        guard let currentID, var node = historyMessages[currentID] else {
            return historyMessages.values.sorted {
                ($0["timestamp"] as? Int ?? 0) < ($1["timestamp"] as? Int ?? 0)
            }
        }

        var chain: [[String: Any]] = [node]
        while let parentID = node["parentId"] as? String, let parent = historyMessages[parentID] {
            chain.insert(parent, at: 0)
            node = parent
        }
        return chain
    }

    private static func title(for messages: [ChatMessage]) -> String {
        ChatSessionStoreTitleFallback.title(for: messages)
    }

    private static func title(for text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count <= 42 { return singleLine.isEmpty ? "New Chat" : singleLine }
        return String(singleLine.prefix(39)) + "..."
    }

    private static func postJSON(
        to url: URL,
        payload: [String: Any],
        headers: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private static func getJSON(from url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenWebUIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenWebUIError.apiError(OpenWebUIRunner.errorMessage(from: body, statusCode: http.statusCode))
        }
    }
}

private enum ChatSessionStoreTitleFallback {
    static func title(for messages: [ChatMessage]) -> String {
        let source = messages.first(where: { $0.role == .user })?.text
            ?? messages.first?.text
            ?? "Previous chat"

        let singleLine = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= 42 { return singleLine }
        return String(singleLine.prefix(39)) + "..."
    }
}
