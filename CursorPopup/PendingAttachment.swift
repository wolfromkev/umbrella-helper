import AppKit
import Foundation

struct PendingAttachment: Identifiable, Equatable {
    let id: UUID
    let filePath: String
    let thumbnail: NSImage

    init(id: UUID = UUID(), filePath: String, thumbnail: NSImage) {
        self.id = id
        self.filePath = filePath
        self.thumbnail = thumbnail
    }
}
