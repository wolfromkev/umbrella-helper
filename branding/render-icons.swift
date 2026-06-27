#!/usr/bin/env swift
import AppKit

enum RenderUmbrella {
    static func drawLogo(into context: CGContext, size: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        context.clear(rect)

        // Keep a little breathing room so tiny icons remain crisp.
        let drawRect = rect.insetBy(dx: size * 0.10, dy: size * 0.08)
        let canopyTopY = drawRect.maxY - drawRect.height * 0.08
        let canopyBaseY = drawRect.midY + drawRect.height * 0.06
        let centerX = drawRect.midX
        let canopyHalfWidth = drawRect.width * 0.46
        let black = CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)

        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: centerX - canopyHalfWidth, y: canopyBaseY))
        canopy.addCurve(
            to: CGPoint(x: centerX + canopyHalfWidth, y: canopyBaseY),
            control1: CGPoint(x: centerX - canopyHalfWidth * 0.62, y: canopyTopY),
            control2: CGPoint(x: centerX + canopyHalfWidth * 0.62, y: canopyTopY)
        )
        canopy.addLine(to: CGPoint(x: centerX + canopyHalfWidth * 0.92, y: canopyBaseY - drawRect.height * 0.02))
        canopy.addCurve(
            to: CGPoint(x: centerX - canopyHalfWidth * 0.92, y: canopyBaseY - drawRect.height * 0.02),
            control1: CGPoint(x: centerX + canopyHalfWidth * 0.52, y: canopyBaseY - drawRect.height * 0.24),
            control2: CGPoint(x: centerX - canopyHalfWidth * 0.52, y: canopyBaseY - drawRect.height * 0.24)
        )
        canopy.closeSubpath()

        context.setFillColor(black)
        context.addPath(canopy)
        context.fillPath()

        context.setStrokeColor(black)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(1.0, size * 0.06))

        let shaftTop = CGPoint(x: centerX, y: canopyBaseY - drawRect.height * 0.03)
        let shaftBottom = CGPoint(x: centerX, y: drawRect.minY + drawRect.height * 0.22)
        context.beginPath()
        context.move(to: shaftTop)
        context.addLine(to: shaftBottom)
        context.strokePath()

        let hook = CGMutablePath()
        hook.move(to: shaftBottom)
        hook.addCurve(
            to: CGPoint(x: centerX + drawRect.width * 0.18, y: drawRect.minY + drawRect.height * 0.18),
            control1: CGPoint(x: centerX + drawRect.width * 0.01, y: drawRect.minY + drawRect.height * 0.06),
            control2: CGPoint(x: centerX + drawRect.width * 0.18, y: drawRect.minY + drawRect.height * 0.08)
        )
        context.addPath(hook)
        context.strokePath()
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

RenderUmbrella.writePNG(at: brandingDir.appendingPathComponent("icon-1024.png").path, size: 1024)

let logoMarkSizes: [(String, Int)] = [
    ("logomark-128.png", 128),
    ("logomark-256.png", 256),
    ("logomark-512.png", 512),
]
for (name, size) in logoMarkSizes {
    RenderUmbrella.writePNG(at: logoMarkDir.appendingPathComponent(name).path, size: size)
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
    RenderUmbrella.writePNG(at: appIconDir.appendingPathComponent(name).path, size: size)
}

print("Rendered umbrella branding assets.")
