import AppKit

// Renders the GitHub social-preview card (1280×640) in the TuckBar design language:
// wordmark + descriptive copy on the left, a "tagged display tucked / untagged keeps its
// bar" two-monitor illustration on the right.

func color(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let W: CGFloat = 1280, H: CGFloat = 640
let amber = color(0xff9f0a)

func drawGlyphTile(in r: NSRect) {
    let s = r.width / 140.0
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: r.minX + x * s, y: r.minY + y * s, width: w * s, height: h * s)
    }
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s).fill()
    color(0xf0f0f4).setFill()
    NSBezierPath(roundedRect: R(58, 44, 24, 62), xRadius: 8 * s, yRadius: 8 * s).fill()   // stem (connected)
    NSBezierPath(roundedRect: R(18, 38, 104, 16), xRadius: 8 * s, yRadius: 8 * s).fill()  // crossbar
    color(0x16161a).setFill()
    NSBezierPath(roundedRect: R(56, 38, 28, 11), xRadius: 4 * s, yRadius: 4 * s).fill()   // notch
    color(0xffffff, 0.09).setStroke()
    let b = NSBezierPath(roundedRect: R(6, 6, 128, 128), xRadius: 30 * s, yRadius: 30 * s)
    b.lineWidth = 1.2
    b.stroke()
}

func drawMonitor(_ r: NSRect, tagged: Bool) {
    let ctx = NSGraphicsContext.current!.cgContext
    // stand
    color(0x2a2740).setFill()
    let neckW = r.width * 0.16
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: r.midX - neckW / 2, y: r.maxY))
    neck.line(to: NSPoint(x: r.midX + neckW / 2, y: r.maxY))
    neck.line(to: NSPoint(x: r.midX + neckW * 0.85, y: r.maxY + 24))
    neck.line(to: NSPoint(x: r.midX - neckW * 0.85, y: r.maxY + 24))
    neck.close(); neck.fill()
    NSBezierPath(roundedRect: NSRect(x: r.midX - r.width * 0.23, y: r.maxY + 24, width: r.width * 0.46, height: 9),
                 xRadius: 4, yRadius: 4).fill()

    // bezel + screen
    color(0x050507).setFill()
    NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16).fill()
    let screen = r.insetBy(dx: 7, dy: 7)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    let wp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0x4a6cd4).cgColor, color(0x7a4fae).cgColor, color(0xc4607e).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wp, start: CGPoint(x: screen.minX, y: screen.minY),
                           end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
    if !tagged {
        // a real menu bar sits on the untagged display
        color(0xffffff, 0.92).setFill()
        NSBezierPath(rect: NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: 13)).fill()
        color(0x222230).setFill()
        for i in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: screen.minX + 9 + CGFloat(i) * 16, y: screen.minY + 4.5, width: 11, height: 4),
                         xRadius: 2, yRadius: 2).fill()
        }
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: screen.maxX - 13 - CGFloat(i) * 11, y: screen.minY + 4, width: 5, height: 5)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    if tagged {
        // amber "tagged" accent + a little tucked-T badge; the screen top stays clean.
        amber.setStroke()
        let bp = NSBezierPath(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), xRadius: 17, yRadius: 17)
        bp.lineWidth = 3; bp.stroke()
        amber.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.maxX - 32, y: r.minY + 11, width: 22, height: 22), xRadius: 7, yRadius: 7).fill()
        color(0x1a1205).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.maxX - 27, y: r.minY + 16, width: 12, height: 3), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: r.maxX - 22.5, y: r.minY + 16, width: 3, height: 11), xRadius: 1, yRadius: 1).fill()
    }
}

func label(_ s: String, centerX: CGFloat, y: CGFloat, _ c: NSColor, size: CGFloat = 19, weight: NSFont.Weight = .semibold) {
    let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c]
    let str = s as NSString
    let w = str.size(withAttributes: attr).width
    str.draw(at: NSPoint(x: centerX - w / 2, y: y), withAttributes: attr)
}

let image = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0x2c2742).cgColor, color(0x16131f).cgColor, color(0x0a0a10).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])

    // ---- left: wordmark + copy ----
    drawGlyphTile(in: NSRect(x: 90, y: 132, width: 66, height: 66))
    var x: CGFloat = 174
    let wmFont = NSFont.systemFont(ofSize: 62, weight: .bold)
    for (s, c) in [("Tuck", NSColor.white), ("Bar", amber)] {
        let attr: [NSAttributedString.Key: Any] = [.font: wmFont, .foregroundColor: c]
        (s as NSString).draw(at: NSPoint(x: x, y: 134), withAttributes: attr)
        x += (s as NSString).size(withAttributes: attr).width
    }
    ("Tuck your menu bar away — and pull it back the second you want it." as NSString).draw(
        in: NSRect(x: 92, y: 238, width: 560, height: 100),
        withAttributes: [.font: NSFont.systemFont(ofSize: 29, weight: .medium), .foregroundColor: color(0xe9e9ee)])
    let para = NSMutableParagraphStyle(); para.lineSpacing = 6
    ("Saves OLED burn-in and hands you a cleaner screen. Per-monitor: tuck the displays you choose, keep the menu bar on the ones you don't." as NSString).draw(
        in: NSRect(x: 92, y: 330, width: 545, height: 170),
        withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: color(0x9a9aac), .paragraphStyle: para])

    // ---- right: two monitors ----
    let a = NSRect(x: 712, y: 188, width: 236, height: 152)
    let b = NSRect(x: 974, y: 232, width: 236, height: 152)
    drawMonitor(b, tagged: false)
    drawMonitor(a, tagged: true)
    label("tagged · tucked", centerX: a.midX, y: a.maxY + 44, amber)
    label("untagged · bar stays", centerX: b.midX, y: b.maxY + 44, color(0x9a9aac))
    return true
}

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tuckbar-social.png"
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
