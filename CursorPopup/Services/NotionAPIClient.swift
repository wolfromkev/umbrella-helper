import Foundation

enum NotionFieldSelection {
    static let none = "__none__"

    static func value(from selection: String) -> String? {
        selection == none ? nil : selection
    }
}

struct NotionDatabaseSchema: Equatable {
    let databaseTitle: String
    let titleProperty: String
    let statusProperty: String?
    let defaultStatus: String?
    let categoryProperty: String?
    let categoryOptions: [String]
    let priorityProperty: String?
    let priorityOptions: [String]
    let dueDateProperty: String?
}

enum NotionAPIError: LocalizedError {
    case missingToken
    case missingDatabaseID
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your Notion integration token in Settings."
        case .missingDatabaseID:
            return "Add your Notion tasks database ID in Settings."
        case .invalidResponse:
            return "Notion returned an unexpected response."
        case .apiError(let message):
            return message
        }
    }
}

struct NotionTaskInput {
    var title: String
    var category: String?
    var priority: String?
    var dueDate: Date?
}

final class NotionAPIClient {
    static let shared = NotionAPIClient()

    private let notionVersion = "2022-06-28"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDatabaseSchema() async throws -> NotionDatabaseSchema {
        let json = try await requestDatabaseJSON()
        return parseDatabaseSchema(json)
    }

    func createTask(_ input: NotionTaskInput, schema: NotionDatabaseSchema) async throws -> URL {
        var properties: [String: Any] = [
            schema.titleProperty: [
                "title": [
                    ["text": ["content": input.title]],
                ],
            ],
        ]

        if let statusProperty = schema.statusProperty,
           let defaultStatus = schema.defaultStatus {
            properties[statusProperty] = ["status": ["name": defaultStatus]]
        }

        if let category = input.category,
           !category.isEmpty,
           let categoryProperty = schema.categoryProperty {
            properties[categoryProperty] = ["select": ["name": category]]
        }

        if let priority = input.priority,
           !priority.isEmpty,
           let priorityProperty = schema.priorityProperty {
            properties[priorityProperty] = ["select": ["name": priority]]
        }

        if let dueDate = input.dueDate,
           let dueDateProperty = schema.dueDateProperty {
            properties[dueDateProperty] = [
                "date": ["start": Self.notionDateString(dueDate)],
            ]
        }

        let databaseID = AppSettings.shared.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "parent": ["database_id": normalizedNotionID(databaseID)],
            "properties": properties,
        ]

        let data = try await performRequest(
            url: URL(string: "https://api.notion.com/v1/pages")!,
            method: "POST",
            body: body
        )

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pageID = json["id"] as? String
        else {
            throw NotionAPIError.invalidResponse
        }

        return notionPageURL(for: pageID)
    }

    private func requestDatabaseJSON() async throws -> [String: Any] {
        let databaseID = AppSettings.shared.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !databaseID.isEmpty else {
            throw NotionAPIError.missingDatabaseID
        }

        let url = URL(string: "https://api.notion.com/v1/databases/\(normalizedNotionID(databaseID))")!
        let data = try await performRequest(url: url, method: "GET", body: nil)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionAPIError.invalidResponse
        }

        return json
    }

    private func parseDatabaseSchema(_ json: [String: Any]) -> NotionDatabaseSchema {
        let databaseTitle = plainText(from: json["title"]) ?? "Notion Tasks"
        let properties = json["properties"] as? [String: [String: Any]] ?? [:]

        var titleProperty = "Name"
        var statusProperty: String?
        var defaultStatus: String?
        var categoryProperty: String?
        var categoryOptions: [String] = []
        var priorityProperty: String?
        var priorityOptions: [String] = []
        var dueDateProperty: String?

        for (name, property) in properties {
            guard let type = property["type"] as? String else { continue }

            switch type {
            case "title":
                titleProperty = name
            case "status":
                if statusProperty == nil {
                    statusProperty = name
                    defaultStatus = statusOptions(from: property).first { $0 == "Not started" }
                        ?? statusOptions(from: property).first
                }
            case "select":
                let options = selectOptions(from: property)
                let lowered = name.lowercased()
                if lowered.contains("category") {
                    categoryProperty = name
                    categoryOptions = options
                } else if lowered.contains("prio") || lowered.contains("priority") {
                    priorityProperty = name
                    priorityOptions = options
                }
            case "date":
                let lowered = name.lowercased()
                if lowered.contains("due") {
                    dueDateProperty = name
                }
            default:
                break
            }
        }

        return NotionDatabaseSchema(
            databaseTitle: databaseTitle,
            titleProperty: titleProperty,
            statusProperty: statusProperty,
            defaultStatus: defaultStatus,
            categoryProperty: categoryProperty,
            categoryOptions: categoryOptions,
            priorityProperty: priorityProperty,
            priorityOptions: priorityOptions,
            dueDateProperty: dueDateProperty
        )
    }

    private func selectOptions(from property: [String: Any]) -> [String] {
        guard
            let select = property["select"] as? [String: Any],
            let options = select["options"] as? [[String: Any]]
        else {
            return []
        }

        return options.compactMap { $0["name"] as? String }
    }

    private func statusOptions(from property: [String: Any]) -> [String] {
        guard
            let status = property["status"] as? [String: Any],
            let options = status["options"] as? [[String: Any]]
        else {
            return []
        }

        return options.compactMap { $0["name"] as? String }
    }

    private func plainText(from value: Any?) -> String? {
        guard let items = value as? [[String: Any]] else { return nil }
        return items.compactMap { $0["plain_text"] as? String }.joined()
    }

    private func performRequest(url: URL, method: String, body: [String: Any]?) async throws -> Data {
        guard let token = KeychainStorage.notionToken, !token.isEmpty else {
            throw NotionAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let message = parseErrorMessage(from: data) ?? "Notion request failed (\(http.statusCode))."
            throw NotionAPIError.apiError(message)
        }

        return data
    }

    private static func notionDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func normalizedNotionID(_ id: String) -> String {
        let compact = id.replacingOccurrences(of: "-", with: "")
        guard compact.count == 32 else { return id }

        return [
            String(compact.prefix(8)),
            String(compact.dropFirst(8).prefix(4)),
            String(compact.dropFirst(12).prefix(4)),
            String(compact.dropFirst(16).prefix(4)),
            String(compact.dropFirst(20)),
        ].joined(separator: "-")
    }

    private func notionPageURL(for pageID: String) -> URL {
        let slug = pageID.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.notion.so/\(slug)")!
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return json["message"] as? String
    }
}
