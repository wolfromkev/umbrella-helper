import AppKit
import Foundation

enum AttachmentStore {
    static let maxAttachments = 5
    private static let thumbnailSide: CGFloat = 72

    static func save(_ image: NSImage) -> PendingAttachment? {
        guard let pngData = pngData(from: image) else { return nil }

        let directory = attachmentsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).png"
        let fileURL = directory.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL)
        } catch {
            return nil
        }

        let thumbnail = makeThumbnail(image, maxSide: thumbnailSide)
        return PendingAttachment(filePath: fileURL.path, thumbnail: thumbnail)
    }

    static func makeThumbnail(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let scale = min(maxSide / sourceSize.width, maxSide / sourceSize.height, 1)
        let targetSize = NSSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()
        return thumbnail
    }

    static func imageFromPasteboard() -> NSImage? {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in types {
            guard let data = pasteboard.data(forType: type), let image = NSImage(data: data) else { continue }
            return image
        }

        return nil
    }

    static func pasteboardHasImage() -> Bool {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        return types.contains(.png)
            || types.contains(.tiff)
            || types.contains(NSPasteboard.PasteboardType("public.image"))
    }

    private static func attachmentsDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorPopup", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
