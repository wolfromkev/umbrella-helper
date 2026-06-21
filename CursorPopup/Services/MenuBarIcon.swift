import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            GeometricPencil.fill(
                in: GeometricPencil.insetRect(in: rect, padding: 1.5),
                color: .black
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
