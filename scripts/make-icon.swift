import Foundation
import CoreGraphics

// Draws the TuckBar "tight-stem dashed-T" app icon at any size and writes a PNG.
// Geometry is authored in the same 140-unit space as design/tuckbar-icon-dashed-T.html
// (tile occupies 6…134), then mapped into the macOS icon grid (~100/1024 margin).

func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

func draw(size: Int, to url: URL) {
    let dim = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

    // Top-left origin, y-down, then map the 128-unit tile into the icon grid.
    ctx.translateBy(x: 0, y: dim); ctx.scaleBy(x: 1, y: -1)
    let margin = dim * (100.0 / 1024.0)
    let s = (dim - 2 * margin) / 128.0
    ctx.translateBy(x: margin - 6 * s, y: margin - 6 * s)
    ctx.scaleBy(x: s, y: s)

    let tile = CGPath(roundedRect: CGRect(x: 6, y: 6, width: 128, height: 128),
                      cornerWidth: 30, cornerHeight: 30, transform: nil)

    // Screen: subtle top-to-bottom dark gradient, clipped to the tile.
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let grad = CGGradient(colorsSpace: space,
                          colors: [color(43, 43, 51), color(20, 20, 23), color(8, 8, 10)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 70, y: 6), end: CGPoint(x: 70, y: 134), options: [])
    ctx.restoreGState()

    // Dashed stem (drawn first so the crossbar covers where it merges up).
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 58, y: 44, width: 24, height: 62),
                       cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.setStrokeColor(color(244, 244, 246))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [3, 9])
    ctx.strokePath()
    ctx.restoreGState()

    // Solid crossbar (the menu bar).
    ctx.addPath(CGPath(roundedRect: CGRect(x: 18, y: 38, width: 104, height: 16),
                       cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.setFillColor(color(244, 244, 246)); ctx.fillPath()

    // Overlaid notch.
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: 55, y: 38))
    notch.addLine(to: CGPoint(x: 85, y: 38))
    notch.addLine(to: CGPoint(x: 85, y: 44))
    notch.addQuadCurve(to: CGPoint(x: 79, y: 50), control: CGPoint(x: 85, y: 50))
    notch.addLine(to: CGPoint(x: 61, y: 50))
    notch.addQuadCurve(to: CGPoint(x: 55, y: 44), control: CGPoint(x: 55, y: 50))
    notch.closeSubpath()
    ctx.addPath(notch); ctx.setFillColor(color(0, 0, 0)); ctx.fillPath()

    // Hairline edge.
    ctx.addPath(tile); ctx.setStrokeColor(color(255, 255, 255, 0.08)); ctx.setLineWidth(1); ctx.strokePath()

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    draw(size: px, to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
draw(size: 1024, to: URL(fileURLWithPath: "\(outDir)/../AppIcon-1024.png"))
print("✓ rendered iconset to \(outDir)")
