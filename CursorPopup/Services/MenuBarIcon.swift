import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setFill()

            let pill = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 6.5, width: 11.5, height: 5),
                xRadius: 2.5,
                yRadius: 2.5
            )
            pill.fill()

            let button = NSBezierPath(
                roundedRect: NSRect(x: 13, y: 6.5, width: 4, height: 5),
                xRadius: 1.2,
                yRadius: 1.2
            )
            button.fill()

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.1
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 15, y: 8.7))
            arrow.line(to: NSPoint(x: 15, y: 10.1))
            arrow.move(to: NSPoint(x: 14.1, y: 9.35))
            arrow.line(to: NSPoint(x: 15, y: 10.1))
            arrow.line(to: NSPoint(x: 15.9, y: 9.35))
            NSColor.black.setStroke()
            arrow.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
