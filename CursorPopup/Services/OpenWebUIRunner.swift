import Foundation

final class OpenWebUIRunner {
    private var streamTask: Task<Void, Never>?
    private var activeRunID = UUID()

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        activeRunID = UUID()
    }

    func send(
        messages: [ChatMessage],
        sessionID: String?,
        onEvent: @escaping (AgentEvent) -> Void
    ) {
        cancel()

        let settings = AppSettings.shared
        guard settings.openWebUISyncChats else {
            sendStateless(messages: messages, sessionID: sessionID, onEvent: onEvent)
            return
        }

        let runID = UUID()
        activeRunID = runID

        streamTask = Task {
            do {
                let (_, apiKey, model) = try OpenWebUIChatClient.credentials()
                let baseURL = settings.normalizedOpenWebUIBaseURL

                let syncResult: (chatID: String, assistantMessageID: UUID, streamSessionID: String)
                if let sessionID, !sessionID.isEmpty {
                    syncResult = try await OpenWebUIChatClient.syncConversation(
                        messages: messages,
                        model: model,
                        existingChatID: sessionID
                    )
                } else {
                    syncResult = try await OpenWebUIChatClient.syncConversation(
                        messages: messages,
                        model: model,
                        existingChatID: nil
                    )
                    if Task.isCancelled || self.activeRunID != runID { return }
                    onEvent(.sessionStarted(syncResult.chatID))
                }

                if Task.isCancelled || self.activeRunID != runID { return }

                let finalText = try await streamCompletion(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    chatID: syncResult.chatID,
                    assistantMessageID: syncResult.assistantMessageID,
                    streamSessionID: syncResult.streamSessionID,
                    messages: messages,
                    runID: runID,
                    onEvent: onEvent
                )

                if Task.isCancelled || self.activeRunID != runID { return }

                try await finalizeCompletion(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    chatID: syncResult.chatID,
                    assistantMessageID: syncResult.assistantMessageID,
                    model: model,
                    content: finalText
                )
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || self.activeRunID != runID { return }
                onEvent(.failed(error.localizedDescription))
            }
        }
    }

    static func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/api/models") else {
            throw OpenWebUIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenWebUIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenWebUIError.apiError(Self.errorMessage(from: body, statusCode: http.statusCode))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]]
        else {
            throw OpenWebUIError.invalidResponse
        }

        return dataArray.compactMap { $0["id"] as? String }.sorted()
    }

    static func errorMessage(from body: String, statusCode: Int) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return "Open WebUI error (\(statusCode)): \(detail)"
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return "Open WebUI error (\(statusCode)): \(message)"
            }
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String, !message.isEmpty {
                return "Open WebUI error (\(statusCode)): \(message)"
            }
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Open WebUI returned HTTP \(statusCode)."
        }
        if trimmed.count > 240 {
            return "Open WebUI error (\(statusCode)): \(String(trimmed.prefix(237)))..."
        }
        return "Open WebUI error (\(statusCode)): \(trimmed)"
    }

    private func sendStateless(
        messages: [ChatMessage],
        sessionID: String?,
        onEvent: @escaping (AgentEvent) -> Void
    ) {
        let settings = AppSettings.shared
        let baseURL = settings.normalizedOpenWebUIBaseURL
        let model = settings.openWebUIModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty else {
            onEvent(.failed("Set your Open WebUI server URL in Settings."))
            return
        }

        guard !model.isEmpty else {
            onEvent(.failed("Set the model name in Settings (must match a model in Open WebUI)."))
            return
        }

        guard let apiKey = KeychainStorage.openWebUIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            onEvent(.failed("Add your Open WebUI API key in Settings (Account → Settings → Account → API keys)."))
            return
        }

        guard let url = URL(string: "\(baseURL)/api/chat/completions") else {
            onEvent(.failed("Open WebUI server URL is invalid."))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let payload: [String: Any] = [
            "model": model,
            "messages": Self.apiMessages(from: messages),
            "stream": true,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            onEvent(.failed("Could not encode the chat request."))
            return
        }
        request.httpBody = body

        let runID = UUID()
        activeRunID = runID

        if sessionID == nil {
            onEvent(.sessionStarted(UUID().uuidString))
        }

        streamTask = Task {
            do {
                _ = try await consumeStream(request: request, runID: runID, onEvent: onEvent)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || self.activeRunID != runID { return }
                onEvent(.failed("Open WebUI request failed: \(error.localizedDescription)"))
            }
        }
    }

    private func streamCompletion(
        baseURL: String,
        apiKey: String,
        model: String,
        chatID: String,
        assistantMessageID: UUID,
        streamSessionID: String,
        messages: [ChatMessage],
        runID: UUID,
        onEvent: @escaping (AgentEvent) -> Void
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat/completions") else {
            throw OpenWebUIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let payload: [String: Any] = [
            "chat_id": chatID,
            "id": assistantMessageID.uuidString,
            "model": model,
            "messages": Self.apiMessages(from: messages),
            "stream": true,
            "session_id": streamSessionID,
            "background_tasks": [
                "title_generation": true,
                "tags_generation": false,
                "follow_up_generation": false,
            ],
            "features": [
                "code_interpreter": false,
                "web_search": false,
                "image_generation": false,
                "memory": false,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await consumeStream(request: request, runID: runID, onEvent: onEvent)
    }

    private func consumeStream(
        request: URLRequest,
        runID: UUID,
        onEvent: @escaping (AgentEvent) -> Void
    ) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if Task.isCancelled || activeRunID != runID { return "" }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 4_000 { break }
            }
            onEvent(.failed(Self.errorMessage(from: errorBody, statusCode: http.statusCode)))
            return ""
        }

        var latestFullText = ""

        for try await line in bytes.lines {
            if Task.isCancelled || activeRunID != runID { return "" }
            guard let delta = Self.parseStreamLine(line) else { continue }
            if delta.isEmpty { continue }

            if delta.count > latestFullText.count, delta.hasPrefix(latestFullText) {
                let fragment = String(delta.dropFirst(latestFullText.count))
                latestFullText = delta
                if !fragment.isEmpty {
                    onEvent(.textDelta(fragment))
                }
            } else if !delta.isEmpty, delta != latestFullText {
                latestFullText = delta
                onEvent(.textDelta(delta))
            }
        }

        if Task.isCancelled || activeRunID != runID { return "" }

        if !latestFullText.isEmpty {
            onEvent(.textFinal(latestFullText))
        }
        onEvent(.completed)
        return latestFullText
    }

    private func finalizeCompletion(
        baseURL: String,
        apiKey: String,
        chatID: String,
        assistantMessageID: UUID,
        model: String,
        content: String
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/chat/completed") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload: [String: Any] = [
            "chat_id": chatID,
            "id": assistantMessageID.uuidString,
            "model": model,
            "messages": [
                [
                    "role": "assistant",
                    "content": content,
                ],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func apiMessages(from messages: [ChatMessage]) -> [[String: Any]] {
        messages.compactMap { message in
            let role = message.role == .user ? "user" : "assistant"
            guard !message.text.isEmpty || !message.imagePaths.isEmpty else { return nil }

            if message.role == .user, !message.imagePaths.isEmpty {
                var content: [[String: Any]] = []
                if !message.text.isEmpty {
                    content.append(["type": "text", "text": message.text])
                }
                for path in message.imagePaths {
                    guard let encoded = base64ImageDataURL(for: path) else { continue }
                    content.append([
                        "type": "image_url",
                        "image_url": ["url": encoded],
                    ])
                }
                guard !content.isEmpty else { return nil }
                return ["role": role, "content": content]
            }

            return ["role": role, "content": message.text]
        }
    }

    private static func base64ImageDataURL(for path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        default: mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func parseStreamLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return nil }

        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first
        else {
            return nil
        }

        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }

        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        return nil
    }
}

enum OpenWebUIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Open WebUI server URL is invalid."
        case .invalidResponse:
            return "Open WebUI returned an unexpected response."
        case .apiError(let message):
            return message
        }
    }
}
