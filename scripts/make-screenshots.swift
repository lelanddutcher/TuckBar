import AppKit

// Renders the App Store screenshot set (2560×1600, 16:10) in the TuckBar design language.
// Usage: swift scripts/make-screenshots.swift <output-dir>

func color(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let W: CGFloat = 2560, H: CGFloat = 1600
let amber = color(0xff9f0a)

func text(_ s: String, _ r: NSRect, size: CGFloat, _ c: NSColor, weight: NSFont.Weight = .regular, center: Bool = false) {
    let p = NSMutableParagraphStyle(); p.lineSpacing = size * 0.18; p.alignment = center ? .center : .left
    (s as NSString).draw(in: r, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                 .foregroundColor: c, .paragraphStyle: p])
}
func centered(_ s: String, cx: CGFloat, y: CGFloat, size: CGFloat, _ c: NSColor, weight: NSFont.Weight = .semibold) {
    let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c]
    let w = (s as NSString).size(withAttributes: attr).width
    (s as NSString).draw(at: NSPoint(x: cx - w / 2, y: y), withAttributes: attr)
}

func drawGlyphTile(in r: NSRect) {
    let s = r.width / 140.0
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: r.minX + x * s, y: r.minY + y * s, width: w * s, height: h * s)
    }
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s).fill()
    color(0xf0f0f4).setFill()
    NSBezierPath(roundedRect: R(58, 44, 24, 62), xRadius: 8 * s, yRadius: 8 * s).fill()
    NSBezierPath(roundedRect: R(18, 38, 104, 16), xRadius: 8 * s, yRadius: 8 * s).fill()
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(56, 38, 28, 11), xRadius: 4 * s, yRadius: 4 * s).fill()
    color(0xffffff, 0.09).setStroke()
    let b = NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s); b.lineWidth = 1.4; b.stroke()
}

func wordmark(x: CGFloat, y: CGFloat, glyph: CGFloat) {
    drawGlyphTile(in: NSRect(x: x, y: y, width: glyph, height: glyph))
    var tx = x + glyph + glyph * 0.28
    let f = NSFont.systemFont(ofSize: glyph * 0.92, weight: .bold)
    for (s, c) in [("Tuck", NSColor.white), ("Bar", amber)] {
        let attr: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
        (s as NSString).draw(at: NSPoint(x: tx, y: y + glyph * 0.03), withAttributes: attr)
        tx += (s as NSString).size(withAttributes: attr).width
    }
}

// top: "clean" | "bar" | "dim" | "black"
func drawMonitor(_ r: NSRect, top: String, accent: Bool) {
    color(0x2a2740).setFill()
    let neckW = r.width * 0.15
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: r.midX - neckW / 2, y: r.maxY))
    neck.line(to: NSPoint(x: r.midX + neckW / 2, y: r.maxY))
    neck.line(to: NSPoint(x: r.midX + neckW * 0.9, y: r.maxY + r.height * 0.13))
    neck.line(to: NSPoint(x: r.midX - neckW * 0.9, y: r.maxY + r.height * 0.13))
    neck.close(); neck.fill()
    NSBezierPath(roundedRect: NSRect(x: r.midX - r.width * 0.2, y: r.maxY + r.height * 0.13, width: r.width * 0.4, height: r.height * 0.045),
                 xRadius: 6, yRadius: 6).fill()

    color(0x050507).setFill()
    let bezelR = r.width * 0.055
    NSBezierPath(roundedRect: r, xRadius: bezelR, yRadius: bezelR).fill()
    let screen = r.insetBy(dx: r.width * 0.03, dy: r.width * 0.03)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: bezelR * 0.7, yRadius: bezelR * 0.7)
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    let ctx = NSGraphicsContext.current!.cgContext
    let wp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0x4a6cd4).cgColor, color(0x7a4fae).cgColor, color(0xc4607e).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wp, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
    let strip = NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height * 0.085)
    if top == "bar" {
        color(0xffffff, 0.92).setFill(); NSBezierPath(rect: strip).fill()
        color(0x222230).setFill()
        for i in 0..<3 { NSBezierPath(roundedRect: NSRect(x: strip.minX + strip.height * 0.7 + CGFloat(i) * strip.height * 1.2, y: strip.midY - strip.height * 0.13, width: strip.height * 0.8, height: strip.height * 0.26), xRadius: strip.height * 0.1, yRadius: strip.height * 0.1).fill() }
        for i in 0..<3 { let d = strip.height * 0.3; NSBezierPath(ovalIn: NSRect(x: strip.maxX - strip.height * 0.9 - CGFloat(i) * strip.height * 0.8, y: strip.midY - d / 2, width: d, height: d)).fill() }
    } else if top == "dim" {
        color(0x000000, 0.55).setFill(); NSBezierPath(rect: strip).fill()
    } else if top == "black" {
        color(0x000000, 1).setFill(); NSBezierPath(rect: strip).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    if accent {
        amber.setStroke()
        let bp = NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: -3), xRadius: bezelR + 3, yRadius: bezelR + 3); bp.lineWidth = 5; bp.stroke()
        let bw = r.width * 0.085
        let bx = r.maxX - bw - 14, by = r.minY + 14
        amber.setFill()
        NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bw), xRadius: bw * 0.3, yRadius: bw * 0.3).fill()
        color(0x1a1205).setFill()
        NSBezierPath(roundedRect: NSRect(x: bx + bw * 0.22, y: by + bw * 0.3, width: bw * 0.56, height: bw * 0.13), xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: bx + bw * 0.5 - bw * 0.065, y: by + bw * 0.3, width: bw * 0.13, height: bw * 0.5), xRadius: 2, yRadius: 2).fill()
    }
}

func bg(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(0x2c2742).cgColor, color(0x16131f).cgColor, color(0x0a0a10).cgColor] as CFArray,
                       locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
}

func render(_ index: Int, _ draw: @escaping () -> Void) -> NSImage {
    NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in draw(); return true }
}

func screenshot1() {
    bg(NSGraphicsContext.current!.cgContext)
    wordmark(x: 160, y: 150, glyph: 96)
    text("A menu bar for the\nmonitors you want it on.", NSRect(x: 158, y: 360, width: 2240, height: 360), size: 116, .white, weight: .bold)
    text("Tuck it on the displays you choose — your OLED, say — and keep it on the ones you don't.", NSRect(x: 162, y: 660, width: 1900, height: 120), size: 44, color(0x9a9aac), weight: .medium)
    drawMonitor(NSRect(x: 470, y: 900, width: 740, height: 470), top: "clean", accent: true)
    drawMonitor(NSRect(x: 1360, y: 980, width: 740, height: 470), top: "bar", accent: false)
    centered("tagged · tucked", cx: 840, y: 1500, size: 40, amber)
    centered("untagged · bar stays", cx: 1730, y: 1500, size: 40, color(0x9a9aac))
}

func screenshot2() {
    bg(NSGraphicsContext.current!.cgContext)
    wordmark(x: 160, y: 150, glyph: 96)
    text("Seamless.\nThe bar just disappears.", NSRect(x: 158, y: 360, width: 2240, height: 360), size: 116, .white, weight: .bold)
    text("Not a black band — TuckBar fills the strip with your actual wallpaper, captured live, so it runs clean to the top edge.", NSRect(x: 162, y: 660, width: 2050, height: 180), size: 44, color(0x9a9aac), weight: .medium)
    drawMonitor(NSRect(x: 760, y: 900, width: 1040, height: 600), top: "clean", accent: true)
    drawMonitor(NSRect(x: 1980, y: 940, width: 360, height: 226), top: "bar", accent: false)
    centered("before", cx: 2160, y: 1230, size: 34, color(0x9a9aac))
    centered("after", cx: 1280, y: 1560, size: 38, amber)
}

func screenshot3() {
    bg(NSGraphicsContext.current!.cgContext)
    wordmark(x: 160, y: 150, glyph: 96)
    text("Seamless, dimmed, or black.\nAnd untuck anytime.", NSRect(x: 158, y: 360, width: 2240, height: 360), size: 110, .white, weight: .bold)
    text("Solid black for maximum burn-in protection, a dim slider, or invisible. Need the bar back? Untuck for 5–60 minutes — it re-tucks itself.", NSRect(x: 162, y: 660, width: 2150, height: 180), size: 44, color(0x9a9aac), weight: .medium)
    let y: CGFloat = 980, w: CGFloat = 620, h: CGFloat = 400, gap: CGFloat = 80
    let startX = (W - (w * 3 + gap * 2)) / 2
    drawMonitor(NSRect(x: startX, y: y, width: w, height: h), top: "clean", accent: false)
    drawMonitor(NSRect(x: startX + (w + gap), y: y, width: w, height: h), top: "dim", accent: false)
    drawMonitor(NSRect(x: startX + (w + gap) * 2, y: y, width: w, height: h), top: "black", accent: false)
    centered("seamless", cx: startX + w / 2, y: 1470, size: 40, color(0xe9e9ee))
    centered("dimmed", cx: startX + (w + gap) + w / 2, y: 1470, size: 40, color(0xe9e9ee))
    centered("black · pixels off", cx: startX + (w + gap) * 2 + w / 2, y: 1470, size: 40, color(0xe9e9ee))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let shots: [(Int, () -> Void)] = [(1, screenshot1), (2, screenshot2), (3, screenshot3)]
for (n, fn) in shots {
    let img = render(n, fn)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    img.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/screenshot-\(n).png"))
    print("wrote \(dir)/screenshot-\(n).png")
}
