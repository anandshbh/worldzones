// Renders AppIcon.iconset: a neon-rimmed globe clock on a dark graphite squircle.
// Usage: swift Scripts/make-icon.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Superellipse ("squircle") like the macOS icon shape, rather than a plain rounded rect.
func squircle(_ r: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5, steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = size / 1024 // design units on Apple's 1024 grid

    let cyan = rgb(0.35, 0.85, 1), violet = rgb(0.62, 0.42, 1)
    /// Strokes whatever path is current with a cyan→violet gradient instead of a flat color.
    func gradientStroke(width: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.setLineWidth(width); ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.setAlpha(alpha)
        ctx.drawLinearGradient(gradient([cyan, violet], [0, 1]),
                               start: CGPoint(x: 260 * u, y: 780 * u), end: CGPoint(x: 780 * u, y: 240 * u), options: [])
        ctx.restoreGState()
    }

    // Body: 824pt graphite squircle with a soft drop shadow.
    let body = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(0.08, 0.08, 0.1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0.2, 0.21, 0.25), rgb(0.1, 0.1, 0.13), rgb(0.04, 0.04, 0.06)], [0, 0.5, 1]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Faint violet glow behind the globe.
    ctx.drawRadialGradient(gradient([rgb(0.45, 0.35, 1, 0.32), rgb(0.45, 0.35, 1, 0)], [0, 1]),
                           startCenter: CGPoint(x: 512 * u, y: 512 * u), startRadius: 0,
                           endCenter: CGPoint(x: 512 * u, y: 512 * u), endRadius: 420 * u, options: [])
    ctx.restoreGState()

    // Globe: a dark sphere with a thin neon rim and grid.
    let center = CGPoint(x: 512 * u, y: 512 * u)
    let radius = 290 * u
    let globe = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: globe); ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0.16, 0.18, 0.26), rgb(0.06, 0.07, 0.11)], [0, 1]),
                           startCenter: CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.35), startRadius: 0,
                           endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    for k in [0.42, 0.8] as [CGFloat] {
        let w = radius * k
        ctx.addEllipse(in: CGRect(x: center.x - w, y: globe.minY, width: w * 2, height: radius * 2))
    }
    ctx.move(to: CGPoint(x: center.x, y: globe.minY)); ctx.addLine(to: CGPoint(x: center.x, y: globe.maxY))
    for dy in [-0.5, 0, 0.5] as [CGFloat] {
        let y = center.y + radius * dy
        let half = radius * sqrt(1 - dy * dy)
        ctx.move(to: CGPoint(x: center.x - half, y: y)); ctx.addLine(to: CGPoint(x: center.x + half, y: y))
    }
    gradientStroke(width: 7 * u, alpha: 0.45)
    ctx.restoreGState()

    // Neon rim with a soft outer glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30 * u, color: rgb(0.45, 0.6, 1, 0.8))
    ctx.addEllipse(in: globe)
    gradientStroke(width: 16 * u, alpha: 1)
    ctx.restoreGState()

    // Hour ticks just inside the rim.
    ctx.setFillColor(rgb(1, 1, 1, 0.55))
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        let r = radius - 38 * u, d = (i % 3 == 0 ? 16 : 10) * u
        let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        ctx.fillEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }

    // Clock hands (10:10), white with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * u), blur: 16 * u, color: rgb(0, 0, 0, 0.6))
    ctx.setStrokeColor(rgb(1, 1, 1)); ctx.setLineCap(.round)
    func hand(_ degreesFromNoon: CGFloat, _ length: CGFloat, _ width: CGFloat) {
        let a = (90 - degreesFromNoon) * .pi / 180
        ctx.setLineWidth(width * u)
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * length * u, y: center.y + sin(a) * length * u))
        ctx.strokePath()
    }
    hand(-55, 140, 36) // hour
    hand(60, 205, 24)  // minute
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: center.x - 30 * u, y: center.y - 30 * u, width: 60 * u, height: 60 * u))
    ctx.restoreGState()
    ctx.setFillColor(rgb(1, 0.55, 0.25))
    ctx.fillEllipse(in: CGRect(x: center.x - 13 * u, y: center.y - 13 * u, width: 26 * u, height: 26 * u))

    // Inner edge highlight on the tile.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.addPath(squircle(body.insetBy(dx: 2 * u, dy: 2 * u)))
    ctx.setStrokeColor(rgb(1, 1, 1, 0.14)); ctx.setLineWidth(4 * u); ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
