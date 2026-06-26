import Foundation

enum ChatBackend: String, CaseIterable, Identifiable {
    case cursor
    case openWebUI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cursor: return "Cursor agent"
        case .openWebUI: return "Open WebUI"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    var imagePaths: [String]
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        imagePaths: [String] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.imagePaths = imagePaths
        self.isStreaming = isStreaming
    }
}

enum ResponseDisplayMode: String, CaseIterable, Identifiable {
    case inline
    case floatingChat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inline: return "Expand below input bar"
        case .floatingChat: return "Floating chat window"
        }
    }
}

enum CursorHandoffMode: String, CaseIterable, Identifiable {
    case formattedHistory
    case lastQuestion
    case fullTranscript

    var id: String { rawValue }

    var label: String {
        switch self {
        case .formattedHistory: return "Formatted history"
        case .lastQuestion: return "Last question only"
        case .fullTranscript: return "Full transcript"
        }
    }
}

enum CursorHandoffTarget: String, CaseIterable, Identifiable {
    case agentsWindow
    case ideChat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agentsWindow: return "Agents window"
        case .ideChat: return "IDE chat sidebar"
        }
    }
}
