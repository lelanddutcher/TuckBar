import CoreGraphics
import Foundation

/// Is the real menu bar on screen on a given display?
///
/// The cover has to step aside when a full-screen app owns its display. v0.1 inferred that
/// from `NSScreen.visibleFrame` losing its top inset, which fails on a notched (and now
/// Dynamic Island) built-in display: macOS keeps the strip reserved in full screen, so the
/// inset never goes to zero and the cover stayed on top of the app (#3).
///
/// This reads the bar itself. Each display's bar is one `Window Server` window at
/// `kCGMainMenuWindowLevel` along its top edge. When macOS hides it, the window either
/// leaves the screen (macOS 15 moves it to y = -24) or stays put and is drawn transparent
/// (macOS 27). Both read as "not showing". Owner, layer and bounds are available without
/// Screen Recording, so this works in black-cover mode too.
enum MenuBarPresence {
    struct BarWindow: Equatable, Sendable {
        var bounds: CGRect   // global CG coordinates, top-left origin
        var alpha: Double
    }

    /// - Parameter displayBounds: `CGDisplayBounds` of the display (top-left origin).
    /// - Returns: `nil` when no bar window is found for the display at all, so the caller
    ///   can fall back to the visibleFrame inset rather than guess.
    static func isShowing(on displayBounds: CGRect, barWindows: [BarWindow]) -> Bool? {
        let mine = barWindows.filter { w in
            w.bounds.width > 0
                && w.bounds.midX >= displayBounds.minX && w.bounds.midX < displayBounds.maxX
                && w.bounds.height < displayBounds.height / 4
        }
        guard !mine.isEmpty else { return nil }
        return mine.contains { w in
            w.alpha > 0.05
                && abs(w.bounds.minY - displayBounds.minY) <= 1
                && w.bounds.intersects(displayBounds)
        }
    }

    /// The bar windows currently in the window list.
    static func currentBarWindows() -> [BarWindow] {
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (info[kCGWindowLayer as String] as? Int) == level,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            return BarWindow(bounds: rect, alpha: onScreen ? alpha : 0)
        }
    }
}
