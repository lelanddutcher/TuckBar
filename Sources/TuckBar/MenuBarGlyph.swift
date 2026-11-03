import AppKit

/// Monochrome template glyphs for the menu bar and the popover header: a "T" whose
/// crossbar is the notched menu bar and whose stem is **solid when the bar is untucked**
/// or a **hollow outline when it's tucked away** — the menu-bar-size echo of the dashed-T
/// app icon (dashes don't resolve this small, so tucked reads as an outline). A slash
/// marks the disabled state.
///
/// `@MainActor`: the cached `NSImage`s are UI objects, only used from `AppModel` (itself
/// main-actor). Required for Swift 6 strict concurrency with SDKs where `NSImage`
/// isn't `Sendable` (e.g. Xcode 16 / macOS 15 SDK).
@MainActor
enum MenuBarGlyph {
    static let tucked = make(filled: false, slashed: false)
    static let untucked = make(filled: true, slashed: false)
    static let off = make(filled: false, slashed: true)

    /// The glyph for the current state.
    static func current(snoozing: Bool, enabled: Bool) -> NSImage {
        if !enabled { return off }
        return snoozing ? untucked : tucked
    }

    private static func make(filled: Bool, slashed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 15), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Stem first, extended up under the crossbar so the two read as one connected T
            // (no gap — matching the app icon). Solid when untucked, hollow outline when tucked.
            let stem = NSBezierPath(roundedRect: NSRect(x: 7.4, y: 4.0, width: 3.2, height: 9.4),
                                    xRadius: 1.4, yRadius: 1.4)
            if filled {
                stem.fill()
            } else {
                stem.lineWidth = 1.1
                stem.stroke()
            }

            // Crossbar with a notch cut from its top-center (even-odd → hole), drawn over the
            // stem's top so they merge cleanly.
            let bar = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.4, width: 16, height: 3.3),
                                   xRadius: 1.4, yRadius: 1.4)
            bar.append(NSBezierPath(roundedRect: NSRect(x: 6.8, y: 1.4, width: 4.4, height: 2.3),
                                    xRadius: 1.0, yRadius: 1.0))
            bar.windingRule = .evenOdd
            bar.fill()

            // Disabled: a slash across the mark.
            if slashed {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2.6, y: 2.6))
                slash.line(to: NSPoint(x: 15.4, y: 12.4))
                slash.lineWidth = 1.6
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
