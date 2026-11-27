import AppKit

let side: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let r = min(radius, rect.width / 2, rect.height / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func bracketsPath(in frame: CGRect, arm: CGFloat, thickness: CGFloat, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
        (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
        (CGPoint(x: frame.maxX, y: frame.minY), -1, 1)
    ]
    for (corner, dx, dy) in corners {
        let horizontalX = dx > 0 ? corner.x : corner.x - arm
        let horizontalY = dy > 0 ? corner.y : corner.y - thickness
        let verticalX = dx > 0 ? corner.x : corner.x - thickness
        let verticalY = dy > 0 ? corner.y : corner.y - arm
        path.addPath(roundedRect(CGRect(x: horizontalX, y: horizontalY, width: arm, height: thickness), radius))
        path.addPath(roundedRect(CGRect(x: verticalX, y: verticalY, width: thickness, height: arm), radius))
    }
    return path
}

func render() -> CGImage {
    let context = makeContext()

    context.setFillColor(color(0x2CB4EC))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    let frame = CGRect(x: 214, y: 214, width: 596, height: 596)
    context.addPath(bracketsPath(in: frame, arm: 212, thickness: 114, radius: 57))
    context.setFillColor(color(0xF5F5F7, 0.5))
    context.fillPath()

    let dotRadius: CGFloat = 124
    context.setFillColor(color(0xF5F5F7))
    context.fillEllipse(in: CGRect(x: side / 2 - dotRadius, y: side / 2 - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

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
