import AppKit

/// Orange-pink app icon: a white lightbulb whose filament is a pair of scissors.
/// Coordinates are top-left origin, y grows downward.
enum IconArtwork {
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

    /// Menu-bar mark: the same line-art bulb as the app icon, without the rays.
    static func drawTemplate(into context: CGContext, size: CGFloat) {
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let line = max(1.15, size * 0.046)
        context.setLineWidth(line)

        let baseHeight = size * 0.28
        let radius = min((size - line) * 0.30, (size - baseHeight - line * 0.5) / 2)
        let center = CGPoint(x: size * 0.5, y: line * 0.55 + radius)
        let glass = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.strokeEllipse(in: glass.insetBy(dx: line / 2, dy: line / 2))

        drawMenuBarScissors(into: context, center: center, radius: radius, line: line)
        drawMenuBarBase(into: context, center: center, radius: radius, line: line, canvasHeight: size)
    }

    private static func drawMenuBarScissors(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat) {
        let scissors = max(1.0, line * 0.82)
        context.setLineWidth(scissors)

        let pivot = CGPoint(x: center.x, y: center.y + radius * 0.02)
        let angle = CGFloat(26) * .pi / 180
        let blade = radius * 0.52
        let handle = radius * 0.46
        let ringRadius = scissors + radius * 0.07

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
            context.strokeEllipse(in: ring.insetBy(dx: scissors / 2, dy: scissors / 2))
        }
    }

    private static func drawMenuBarBase(
        into context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        line: CGFloat,
        canvasHeight: CGFloat
    ) {
        context.setLineWidth(line)
        let top = center.y + radius - line * 0.85
        let shoulder = radius * 0.34
        let hip = radius * 0.46
        let sideBottom = min(top + radius * 0.62, canvasHeight - line * 0.8)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - shoulder, y: top))
        path.addLine(to: CGPoint(x: center.x - hip, y: sideBottom))
        path.addQuadCurve(
            to: CGPoint(x: center.x + hip, y: sideBottom),
            control: CGPoint(x: center.x, y: sideBottom + radius * 0.22)
        )
        path.addLine(to: CGPoint(x: center.x + shoulder, y: top))
        context.addPath(path)
        context.strokePath()

        let y = top + (sideBottom - top) * 0.48
        let half = shoulder + (hip - shoulder) * 0.48
        let inset = line * 0.9
        context.move(to: CGPoint(x: center.x - half + inset, y: y))
        context.addLine(to: CGPoint(x: center.x + half - inset, y: y))
        context.strokePath()
    }

    private static func drawSunsetBackground(into context: CGContext, size: CGFloat) {
        let colors = [
            CGColor(srgbRed: 1, green: 0.447, blue: 0, alpha: 1),
            CGColor(srgbRed: 1, green: 0.333, blue: 0.545, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size, y: size),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawLineBulb(into context: CGContext, size: CGFloat) {
        let line = max(size * 0.03, size < 20 ? 1 : 0)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setFillColor(gray: 1, alpha: 1)
        context.setLineWidth(line)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let center = CGPoint(x: size * 0.50, y: size * 0.43)
        let radius = size * 0.20
        let glass = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.strokeEllipse(in: glass.insetBy(dx: line / 2, dy: line / 2))

        drawRays(into: context, center: center, radius: radius, line: line)
        drawLineScissors(into: context, center: center, radius: radius, line: line)
        drawScrewBase(into: context, center: center, radius: radius, line: line)
    }

    private static func drawRays(into context: CGContext, center: CGPoint, radius: CGFloat, line: CGFloat) {
        let gap = line * 0.95
        let length = radius * 0.34
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
