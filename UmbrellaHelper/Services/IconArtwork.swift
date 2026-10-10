import AppKit

/// Tantalum-themed app icon: gold line art on a warm near-black ground.
/// Coordinates are top-left origin, y grows downward.
enum IconArtwork {
    /// #d4a574
    private static let tantalumGold = CGColor(srgbRed: 0.831, green: 0.647, blue: 0.455, alpha: 1)
    /// #ddba8d
    private static let tantalumSpoke = CGColor(srgbRed: 0.867, green: 0.729, blue: 0.553, alpha: 1)
    /// #e7cba6
    private static let tantalumHighlight = CGColor(srgbRed: 0.906, green: 0.796, blue: 0.651, alpha: 1)
    static func drawAppIcon(into context: CGContext, size: CGFloat, rounded: Bool) {
        context.saveGState()
        if rounded {
            let radius = size * 0.2237
            context.addPath(CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            ))
            context.clip()
        }

        drawSunsetBackground(into: context, size: size)
        drawLineBulb(into: context, size: size)
        context.restoreGState()
    }

    /// Menu-bar mark: a bulb with a pair of scissors. No brightness rays — they crowded the blades at this size.
    static func drawTemplate(into context: CGContext, size: CGFloat) {
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let line = max(1.05, size * 0.05)
        context.setLineWidth(line)

        let radius = size * 0.34
        let center = templateCenter(size: size, radius: radius, line: line)
        let glass = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.strokeEllipse(in: glass.insetBy(dx: line / 2, dy: line / 2))

        drawMenuBarScissors(into: context, center: center, radius: radius)
        drawMenuBarBase(into: context, center: center, radius: radius, line: line)
    }

    /// Equal space above the glass and below the screw, so the mark sits with the other status icons.
    private static func templateCenter(size: CGFloat, radius: CGFloat, line: CGFloat) -> CGPoint {
        let topReach = radius + line * 0.55
        let bottomReach = radius * 1.18 + line * 0.5
        return CGPoint(x: size * 0.5, y: (size + topReach - bottomReach) / 2)
    }

    /// Open blades above two finger holes, drawn thin enough that the holes stay open in the menu bar.
    private static func drawMenuBarScissors(
        into context: CGContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        let pivot = CGPoint(x: center.x, y: center.y - radius * 0.06)
        let open = CGFloat(42) * .pi / 180
        let blade = radius * 0.64
        let bladeWidth = max(1.0, radius * 0.15)

        for sign in [-1, 1] as [CGFloat] {
            context.setLineWidth(bladeWidth)
            let tip = CGPoint(
                x: pivot.x + sign * sin(open) * blade,
                y: pivot.y - cos(open) * blade
            )
            let tail = CGPoint(
                x: pivot.x - sign * sin(open) * radius * 0.18,
                y: pivot.y + cos(open) * radius * 0.18
            )
            context.move(to: tip)
            context.addLine(to: tail)
            context.strokePath()

            let ringRadius = radius * 0.34
            let ringStroke = max(0.85, radius * 0.12)
            let ringCenter = CGPoint(x: center.x - sign * radius * 0.46, y: center.y + radius * 0.38)
            context.setLineWidth(ringStroke)
            context.strokeEllipse(in: CGRect(
                x: ringCenter.x - ringRadius,
                y: ringCenter.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ).insetBy(dx: ringStroke / 2, dy: ringStroke / 2))
        }
    }

    /// Just the neck where the glass meets the screw, not the whole base.
    private static func drawMenuBarBase(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat) {
        context.setLineWidth(line)
        let top = center.y + radius - line * 0.2
        let drop = radius * 0.16
        let shoulder = radius * 0.28
        let hip = radius * 0.38
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - shoulder, y: top))
        path.addLine(to: CGPoint(x: center.x - hip, y: top + drop))
        path.addLine(to: CGPoint(x: center.x + hip, y: top + drop))
        path.addLine(to: CGPoint(x: center.x + shoulder, y: top))
        context.addPath(path)
        context.strokePath()
    }

    private static func drawSunsetBackground(into context: CGContext, size: CGFloat) {
        let colors = [
            CGColor(srgbRed: 0.165, green: 0.153, blue: 0.141, alpha: 1),
            CGColor(srgbRed: 0.071, green: 0.067, blue: 0.059, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 1]
        ) else { return }
        let center = CGPoint(x: size * 0.5, y: size * 0.42)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: size * 0.72,
            options: [.drawsAfterEndLocation]
        )
    }

    private static func drawLineBulb(into context: CGContext, size: CGFloat) {
        let line = max(size * 0.03, size < 20 ? 1 : 0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(line)
        context.setStrokeColor(tantalumGold)
        context.setFillColor(tantalumGold)

        let center = CGPoint(x: size * 0.50, y: size * 0.43)
        let radius = size * 0.20
        let glass = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.strokeEllipse(in: glass.insetBy(dx: line / 2, dy: line / 2))

        context.setStrokeColor(tantalumSpoke)
        drawRays(into: context, center: center, radius: radius, line: line, lengthFactor: 0.34)
        context.setStrokeColor(tantalumHighlight)
        drawLineScissors(into: context, center: center, radius: radius, line: line)
        context.setStrokeColor(tantalumGold)
        drawScrewBase(into: context, center: center, radius: radius, line: line)
    }

    private static func drawRays(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat, lengthFactor: CGFloat) {
        let gap = line * 0.95
        let length = radius * lengthFactor
        let degrees: [CGFloat] = [-125, -78, -38, 0, 38, 78, 125]
        for deg in degrees {
            let angle = deg * .pi / 180
            let dx = sin(angle)
            let dy = -cos(angle)
            let inner = radius + gap
            let outer = inner + length
            context.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            context.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
            context.strokePath()
        }
    }

    private static func drawLineScissors(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat) {
        let pivot = CGPoint(x: center.x, y: center.y + radius * 0.06)
        let angle = CGFloat(28) * .pi / 180
        let blade = radius * 0.58
        let handle = radius * 0.50
        let ringRadius = radius * 0.20

        for sign in [-1, 1] as [CGFloat] {
            let tip = CGPoint(
                x: pivot.x + sign * sin(angle) * blade,
                y: pivot.y - cos(angle) * blade
            )
            let handleCenter = CGPoint(
                x: pivot.x - sign * sin(angle) * handle,
                y: pivot.y + cos(angle) * handle
            )
            let armEnd = CGPoint(
                x: pivot.x - sign * sin(angle) * (handle - ringRadius),
                y: pivot.y + cos(angle) * (handle - ringRadius)
            )
            context.move(to: tip)
            context.addLine(to: armEnd)
            context.strokePath()

            let ring = CGRect(
                x: handleCenter.x - ringRadius,
                y: handleCenter.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            context.strokeEllipse(in: ring.insetBy(dx: line / 2, dy: line / 2))
        }
    }

    private static func drawScrewBase(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat) {
        let top = center.y + radius - line * 0.35
        let shoulder = radius * 0.22
        let hip = radius * 0.42
        let sideBottom = top + radius * 0.52
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - shoulder, y: top))
        path.addLine(to: CGPoint(x: center.x - hip, y: sideBottom))
        path.addQuadCurve(
            to: CGPoint(x: center.x + hip, y: sideBottom),
            control: CGPoint(x: center.x, y: sideBottom + radius * 0.20)
        )
        path.addLine(to: CGPoint(x: center.x + shoulder, y: top))
        context.addPath(path)
        context.strokePath()

        for fraction in [0.40, 0.68] as [CGFloat] {
            let y = top + (sideBottom - top) * fraction
            let half = shoulder + (hip - shoulder) * fraction
            let inset = line * 1.35
            context.move(to: CGPoint(x: center.x - half + inset, y: y))
            context.addLine(to: CGPoint(x: center.x + half - inset, y: y))
            context.strokePath()
        }
    }
}
