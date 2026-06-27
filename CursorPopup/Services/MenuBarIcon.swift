import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawUmbrella(in: rect.insetBy(dx: 1.5, dy: 1.5), color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawUmbrella(in rect: NSRect, color: NSColor) {
        let canopyTopY = rect.maxY - 1.5
        let canopyBaseY = rect.midY + 1
        let centerX = rect.midX
        let canopyWidth = rect.width

        let canopy = NSBezierPath()
        canopy.move(to: NSPoint(x: centerX - canopyWidth / 2, y: canopyBaseY))
        canopy.curve(
            to: NSPoint(x: centerX + canopyWidth / 2, y: canopyBaseY),
            controlPoint1: NSPoint(x: centerX - canopyWidth * 0.35, y: canopyTopY),
            controlPoint2: NSPoint(x: centerX + canopyWidth * 0.35, y: canopyTopY)
        )
        canopy.line(to: NSPoint(x: centerX + canopyWidth / 2 - 1, y: canopyBaseY - 0.8))
        canopy.curve(
            to: NSPoint(x: centerX - canopyWidth / 2 + 1, y: canopyBaseY - 0.8),
            controlPoint1: NSPoint(x: centerX + canopyWidth * 0.25, y: canopyBaseY - 3.2),
            controlPoint2: NSPoint(x: centerX - canopyWidth * 0.25, y: canopyBaseY - 3.2)
        )
        canopy.close()

        color.setFill()
        canopy.fill()

        let shaft = NSBezierPath()
        shaft.lineWidth = 1.7
        shaft.move(to: NSPoint(x: centerX, y: canopyBaseY - 0.8))
        shaft.line(to: NSPoint(x: centerX, y: rect.minY + 4.2))
        color.setStroke()
        shaft.stroke()

        let hook = NSBezierPath()
        hook.lineWidth = 1.7
        hook.move(to: NSPoint(x: centerX, y: rect.minY + 4.2))
        hook.curve(
            to: NSPoint(x: centerX + 3.6, y: rect.minY + 3.6),
            controlPoint1: NSPoint(x: centerX + 0.2, y: rect.minY + 1.6),
            controlPoint2: NSPoint(x: centerX + 3.4, y: rect.minY + 1.9)
        )
        hook.stroke()
    }
}
