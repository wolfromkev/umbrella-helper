import AppKit
import SwiftUI

enum GeometricPencil {
    // Unit coordinates in a 0...1 square, origin at bottom-left (y increases upward).
    static let tip: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.12),
        CGPoint(x: 0.34, y: 0.36),
        CGPoint(x: 0.22, y: 0.22),
    ]

    static let body: [CGPoint] = [
        CGPoint(x: 0.34, y: 0.36),
        CGPoint(x: 0.68, y: 0.70),
        CGPoint(x: 0.60, y: 0.78),
        CGPoint(x: 0.26, y: 0.44),
    ]

    static let eraser: [CGPoint] = [
        CGPoint(x: 0.68, y: 0.70),
        CGPoint(x: 0.86, y: 0.88),
        CGPoint(x: 0.78, y: 0.96),
        CGPoint(x: 0.60, y: 0.78),
    ]

    static let polygons = [tip, body, eraser]

    static func insetRect(in rect: NSRect, padding: CGFloat) -> NSRect {
        NSRect(
            x: rect.minX + padding,
            y: rect.minY + padding,
            width: rect.width - padding * 2,
            height: rect.height - padding * 2
        )
    }

    static func fill(in rect: NSRect, color: NSColor) {
        color.setFill()
        for polygon in polygons {
            let path = NSBezierPath()
            for (index, point) in polygon.enumerated() {
                let mapped = NSPoint(
                    x: rect.minX + point.x * rect.width,
                    y: rect.minY + point.y * rect.height
                )
                if index == 0 {
                    path.move(to: mapped)
                } else {
                    path.line(to: mapped)
                }
            }
            path.close()
            path.fill()
        }
    }
}

struct GeometricPencilShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for polygon in GeometricPencil.polygons {
            guard let first = polygon.first else { continue }
            path.move(to: mappedPoint(first, in: rect))
            for point in polygon.dropFirst() {
                path.addLine(to: mappedPoint(point, in: rect))
            }
            path.closeSubpath()
        }
        return path
    }

    private func mappedPoint(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + unit.x * rect.width,
            y: rect.maxY - unit.y * rect.height
        )
    }
}
