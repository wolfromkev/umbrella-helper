import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let side = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            IconArtwork.drawTemplate(into: context, size: min(rect.width, rect.height))
            return true
        }
        // The status item lays out the alignment rect, then draws the full image.
        // A smaller alignment rect makes the icon fill the menu bar instead of sitting in the padding.
        let bleed = side * 0.18
        image.alignmentRect = NSRect(x: bleed, y: bleed, width: side - bleed * 2, height: side - bleed * 2)
        image.isTemplate = true
        return image
    }
}
