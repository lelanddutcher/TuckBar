import AppKit

// Renders the GitHub / social card (1280×640) in the TuckBar design language:
// wordmark + copy on the left, a "tagged tucked / untagged keeps its bar" two-monitor
// illustration on the right, on a dark amber-splash background.

func color(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let W: CGFloat = 1280, H: CGFloat = 640
let amber = color(0xff9f0a)

// The actual app-icon mark: a notched menu-bar crossbar with a DASHED stem.
func drawGlyphTile(in r: NSRect) {
    let s = r.width / 140.0
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: r.minX + x * s, y: r.minY + y * s, width: w * s, height: h * s)
    }
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s).fill()
    let stem = NSBezierPath(roundedRect: R(58, 44, 24, 62), xRadius: 8 * s, yRadius: 8 * s)
    stem.lineWidth = 5 * s; stem.lineCapStyle = .round; stem.lineJoinStyle = .round
    stem.setLineDash([3 * s, 9 * s], count: 2, phase: 0)
    color(0xf0f0f4).setStroke(); stem.stroke()
    color(0xf0f0f4).setFill()
    NSBezierPath(roundedRect: R(18, 38, 104, 16), xRadius: 8 * s, yRadius: 8 * s).fill()
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(56, 38, 28, 11), xRadius: 4 * s, yRadius: 4 * s).fill()
    color(0xffffff, 0.09).setStroke()
    let b = NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s); b.lineWidth = 1.2; b.stroke()
}

func wordmark(x: CGFloat, y: CGFloat, glyph: CGFloat) {
    drawGlyphTile(in: NSRect(x: x, y: y, width: glyph, height: glyph))
    var tx = x + glyph + glyph * 0.28
    let f = NSFont.systemFont(ofSize: glyph * 0.92, weight: .bold)
    for (s, c) in [("Tuck", NSColor.white), ("Bar", amber)] {
        (s as NSString).draw(at: NSPoint(x: tx, y: y + glyph * 0.03), withAttributes: [.font: f, .foregroundColor: c])
        tx += (s as NSString).size(withAttributes: [.font: f]).width
    }
}

// Uniform 16:10 monitor. style: "clean" | "bar".
func drawMonitor(centerX: CGFloat, top: CGFloat, width: CGFloat, style: String, accent: Bool) {
    let height = width * 10 / 16
    let r = NSRect(x: centerX - width / 2, y: top, width: width, height: height)
    color(0x2a2740).setFill()
    let neckW = width * 0.14, neckH = height * 0.14
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: r.midX - neckW / 2, y: r.maxY)); neck.line(to: NSPoint(x: r.midX + neckW / 2, y: r.maxY))
    neck.line(to: NSPoint(x: r.midX + neckW * 0.9, y: r.maxY + neckH)); neck.line(to: NSPoint(x: r.midX - neckW * 0.9, y: r.maxY + neckH))
    neck.close(); neck.fill()
    NSBezierPath(roundedRect: NSRect(x: r.midX - width * 0.18, y: r.maxY + neckH, width: width * 0.36, height: height * 0.05), xRadius: width * 0.012, yRadius: width * 0.012).fill()

    color(0x050507).setFill()
    let bz = width * 0.045
    NSBezierPath(roundedRect: r, xRadius: bz, yRadius: bz).fill()
    let inset = width * 0.022
    let screen = r.insetBy(dx: inset, dy: inset)
    let sp = NSBezierPath(roundedRect: screen, xRadius: bz * 0.65, yRadius: bz * 0.65)
    NSGraphicsContext.saveGraphicsState(); sp.addClip()
    let ctx = NSGraphicsContext.current!.cgContext
    let wp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0x3f64d0).cgColor, color(0x7a4fae).cgColor, color(0xc4607e).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wp, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
    if style == "bar" {
        let sh = screen.height * 0.092
        let strip = NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: sh)
        color(0xffffff, 0.92).setFill(); NSBezierPath(rect: strip).fill()
        color(0x222230).setFill()
        for i in 0..<3 { NSBezierPath(roundedRect: NSRect(x: strip.minX + sh * 0.7 + CGFloat(i) * sh * 1.25, y: strip.midY - sh * 0.12, width: sh * 0.85, height: sh * 0.24), xRadius: sh * 0.1, yRadius: sh * 0.1).fill() }
        for i in 0..<3 { let d = sh * 0.3; NSBezierPath(ovalIn: NSRect(x: strip.maxX - sh - CGFloat(i) * sh * 0.85, y: strip.midY - d / 2, width: d, height: d)).fill() }
    }
    NSGraphicsContext.restoreGraphicsState()

    if accent {
        amber.setStroke()
        let bp = NSBezierPath(roundedRect: r.insetBy(dx: -2.5, dy: -2.5), xRadius: bz + 2.5, yRadius: bz + 2.5); bp.lineWidth = 4; bp.stroke()
        let bw = width * 0.085, bx = r.maxX - bw - width * 0.03, by = r.minY + width * 0.03
        amber.setFill()
        NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bw), xRadius: bw * 0.3, yRadius: bw * 0.3).fill()
        color(0x1a1205).setFill()
        NSBezierPath(roundedRect: NSRect(x: bx + bw * 0.22, y: by + bw * 0.3, width: bw * 0.56, height: bw * 0.13), xRadius: 1.5, yRadius: 1.5).fill()
        NSBezierPath(roundedRect: NSRect(x: bx + bw * 0.5 - bw * 0.065, y: by + bw * 0.3, width: bw * 0.13, height: bw * 0.5), xRadius: 1.5, yRadius: 1.5).fill()
    }
}

func label(_ s: String, cx: CGFloat, y: CGFloat, _ c: NSColor, size: CGFloat = 19) {
    let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: c]
    let w = (s as NSString).size(withAttributes: attr).width
    (s as NSString).draw(at: NSPoint(x: cx - w / 2, y: y), withAttributes: attr)
}

func draw() {
    let ctx = NSGraphicsContext.current!.cgContext
    color(0x100e16).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    func splash(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ a: CGFloat) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(0xff9f0a, a).cgColor, color(0xff7a1a, a * 0.45).cgColor, color(0xff9f0a, 0).cgColor] as CFArray,
                           locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: rad, options: [])
    }
    splash(1120, 120, 640, 0.42)
    splash(120, 580, 460, 0.2)

    wordmark(x: 88, y: 84, glyph: 54)
    (("Tuck your menu bar away, and pull it\nback the second you want it.") as NSString).draw(
        in: NSRect(x: 88, y: 204, width: 600, height: 120),
        withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white,
                         .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 4; return p }()])
    ("Saves OLED burn-in and hands you a cleaner screen. Per-monitor: tuck the displays you choose, keep the bar on the ones you don't." as NSString).draw(
        in: NSRect(x: 88, y: 332, width: 520, height: 160),
        withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: color(0xb9b9c6),
                         .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 4; return p }()])

    drawMonitor(centerX: 858, top: 262, width: 268, style: "clean", accent: true)
    drawMonitor(centerX: 1124, top: 304, width: 268, style: "bar", accent: false)
    label("tagged · tucked", cx: 858, y: 466, amber, size: 18)
    label("untagged · bar stays", cx: 1124, y: 502, color(0xb9b9c6), size: 18)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tuckbar-social.png"
let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in draw(); return true }
let bm = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bm.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bm)
img.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
try! bm.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
