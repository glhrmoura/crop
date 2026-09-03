import AppKit

let side: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func makeContext() -> CGContext {
    let context = CGContext(
        data: nil,
        width: Int(side),
        height: Int(side),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    return context
}

func bracketsPath(in rect: CGRect, arm: CGFloat, thickness: CGFloat, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
        (CGPoint(x: rect.maxX, y: rect.minY), -1, 1)
    ]
    for (corner, dx, dy) in corners {
        let bracket = CGMutablePath()
        bracket.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        bracket.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x, y: corner.y + dy * arm), radius: radius)
        bracket.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        path.addPath(bracket.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }
    return path
}

func render() -> CGImage {
    let context = makeContext()

    context.drawLinearGradient(
        gradient([color(40, 40, 44), color(4, 5, 9)], [0, 1]),
        start: CGPoint(x: 0, y: side),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    let frame = CGRect(x: 232, y: 232, width: 560, height: 560)
    let brackets = bracketsPath(in: frame, arm: 196, thickness: 74, radius: 58)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: color(0, 0, 0, 0.75))
    context.addPath(brackets)
    context.setFillColor(color(200, 202, 210))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(brackets)
    context.clip()
    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: side / 2, height: side))
    context.drawLinearGradient(
        gradient([color(255, 255, 255), color(226, 228, 235)], [0, 1]),
        start: CGPoint(x: 0, y: frame.maxY + 40),
        end: CGPoint(x: 0, y: frame.minY - 40),
        options: []
    )
    context.restoreGState()
    context.saveGState()
    context.clip(to: CGRect(x: side / 2, y: 0, width: side / 2, height: side))
    context.drawLinearGradient(
        gradient([color(214, 217, 226), color(170, 174, 186)], [0, 1]),
        start: CGPoint(x: 0, y: frame.maxY + 40),
        end: CGPoint(x: 0, y: frame.minY - 40),
        options: []
    )
    context.restoreGState()
    context.restoreGState()

    context.saveGState()
    context.addPath(brackets)
    context.setStrokeColor(color(255, 255, 255, 0.55))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    let center = CGPoint(x: side / 2, y: side / 2)
    let dotRadius: CGFloat = 112
    let dot = CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)

    context.saveGState()
    context.setShadow(offset: .zero, blur: 120, color: color(255, 60, 40, 0.95))
    context.setFillColor(color(255, 60, 40))
    context.fillEllipse(in: dot)
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: .zero, blur: 40, color: color(255, 120, 90, 0.9))
    context.addEllipse(in: dot)
    context.clip()
    context.drawRadialGradient(
        gradient([color(255, 170, 140), color(255, 72, 50), color(214, 28, 18)], [0, 0.55, 1]),
        startCenter: CGPoint(x: center.x - 30, y: center.y + 34), startRadius: 0,
        endCenter: center, endRadius: dotRadius,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()

    context.saveGState()
    let shine = CGRect(x: center.x - 62, y: center.y + 22, width: 124, height: 70)
    context.addEllipse(in: shine)
    context.clip()
    context.drawLinearGradient(
        gradient([color(255, 255, 255, 0.55), color(255, 255, 255, 0)], [0, 1]),
        start: CGPoint(x: 0, y: shine.maxY),
        end: CGPoint(x: 0, y: shine.minY),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: dot.insetBy(dx: -1, dy: -1))
    context.setStrokeColor(color(255, 200, 180, 0.6))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()!
}

func roundedLogo(from art: CGImage) -> CGImage {
    let context = makeContext()
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    let radius = side * 0.2237
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(art, in: rect)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let art = render()
try writePNG(art, to: CommandLine.arguments[1])
if CommandLine.arguments.count > 2 {
    try writePNG(roundedLogo(from: art), to: CommandLine.arguments[2])
}
