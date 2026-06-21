#!/usr/bin/env swift
import AppKit

enum RenderPencil {
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

    static func drawLogo(into context: CGContext, size: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.22
        let background = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(background)
        context.clip()

        let colors = [
            CGColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            CGColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: size, y: 0),
            options: []
        )

        let inset = size * 0.10
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            context.beginPath()
            context.move(to: mapped(first, in: drawRect))
            for point in polygon.dropFirst() {
                context.addLine(to: mapped(point, in: drawRect))
            }
            context.closePath()
            context.fillPath()
        }
    }

    private static func mapped(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + unit.x * rect.width,
            y: rect.maxY - unit.y * rect.height
        )
    }

    static func writePNG(at path: String, size: Int) {
        let pixels = size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create context for \(path)")
        }

        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)
        drawLogo(into: context, size: CGFloat(pixels))

        guard let image = context.makeImage() else {
            fatalError("Failed to render \(path)")
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to encode \(path)")
        }
        try! data.write(to: URL(fileURLWithPath: path))
    }
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let brandingDir = repoRoot.appendingPathComponent("branding")
let logoMarkDir = repoRoot.appendingPathComponent("CursorPopup/Resources/Assets.xcassets/LogoMark.imageset")
let appIconDir = repoRoot.appendingPathComponent("CursorPopup/Resources/Assets.xcassets/AppIcon.appiconset")

RenderPencil.writePNG(at: brandingDir.appendingPathComponent("icon-1024.png").path, size: 1024)

let logoMarkSizes: [(String, Int)] = [
    ("logomark-128.png", 128),
    ("logomark-256.png", 256),
    ("logomark-512.png", 512),
]
for (name, size) in logoMarkSizes {
    RenderPencil.writePNG(at: logoMarkDir.appendingPathComponent(name).path, size: size)
}

let appIconSizes: [(String, Int)] = [
    ("icon-16.png", 16),
    ("icon-16@2x.png", 32),
    ("icon-32.png", 32),
    ("icon-32@2x.png", 64),
    ("icon-128.png", 128),
    ("icon-128@2x.png", 256),
    ("icon-256.png", 256),
    ("icon-256@2x.png", 512),
    ("icon-512.png", 512),
    ("icon-512@2x.png", 1024),
]
for (name, size) in appIconSizes {
    RenderPencil.writePNG(at: appIconDir.appendingPathComponent(name).path, size: size)
}

print("Rendered pencil branding assets.")
