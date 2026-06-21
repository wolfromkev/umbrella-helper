import Foundation

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
