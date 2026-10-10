import AppKit

@main
struct RenderIcons {
    static func main() {
        render()
    }
}

enum IconRenderer {
    static func writePNG(at path: String, size: Int, rounded: Bool, template: Bool, backdrop: CGColor?) {
        let pixels = size
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
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
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        if let backdrop {
            context.setFillColor(backdrop)
            context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }

        if template {
            IconArtwork.drawTemplate(into: context, size: CGFloat(pixels))
        } else {
            IconArtwork.drawAppIcon(into: context, size: CGFloat(pixels), rounded: rounded)
        }

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

func render() {
let repoRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

let brandingDir = repoRoot.appendingPathComponent("branding")
let logoMarkDir = repoRoot.appendingPathComponent("UmbrellaHelper/Resources/Assets.xcassets/LogoMark.imageset")
let appIconDir = repoRoot.appendingPathComponent("UmbrellaHelper/Resources/Assets.xcassets/AppIcon.appiconset")

IconRenderer.writePNG(at: brandingDir.appendingPathComponent("icon-1024.png").path, size: 1024, rounded: true, template: false, backdrop: nil)

for (name, size) in [("logomark-128.png", 128), ("logomark-256.png", 256)] {
    IconRenderer.writePNG(at: logoMarkDir.appendingPathComponent(name).path, size: size, rounded: true, template: false, backdrop: nil)
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
    IconRenderer.writePNG(at: appIconDir.appendingPathComponent(name).path, size: size, rounded: false, template: false, backdrop: nil)
}

print("Rendered scissors and lightbulb icons.")
}
