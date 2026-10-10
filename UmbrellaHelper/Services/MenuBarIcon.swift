import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let side = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            IconArtwork.drawTemplate(into: context, size: min(rect.width, rect.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
