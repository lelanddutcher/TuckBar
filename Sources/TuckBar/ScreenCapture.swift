import Cocoa
import ScreenCaptureKit

/// Captures the *real, on-screen* wallpaper pixels behind the menu bar so the cover is
/// pixel-perfect. (A copy rendered from the wallpaper *file* can't match — macOS
/// composites a scaled/zoomed version, which is the source of the alignment drift.)
///
/// We capture the Dock's live per-display "Wallpaper" window via **ScreenCaptureKit**
/// (`SCScreenshotManager`, macOS 14+), clipped to the menu-bar strip — a stable,
/// supported API (no obsoleted `CGWindowListCreateImageFromArray` shim). Requires
/// Screen Recording permission; without it, callers fall back to a black cover.
enum ScreenCapture {
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Trigger the system permission prompt (gated to wallpaper mode by callers).
    static func requestPermission() {
        // SCShareableContent needs Screen Recording and surfaces the prompt.
        SCShareableContent.getWithCompletionHandler { _, _ in }
    }

    /// The slice of `displayID`'s wallpaper behind the menu bar (top `barHeight` points),
    /// captured at `scale` (the display's backing scale). Returns nil → black fallback.
    static func wallpaperStrip(displayID: CGDirectDisplayID, barHeight: CGFloat, scale: CGFloat) async -> CGImage? {
        guard barHeight > 0 else { return nil }
        let bounds = CGDisplayBounds(displayID)

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return nil }

        // The Dock draws one "Wallpaper" window per display; pick the one covering this one.
        guard let wallpaper = content.windows.first(where: { window in
            (window.title?.hasPrefix("Wallpaper") ?? false)
                && window.owningApplication?.bundleIdentifier == "com.apple.dock"
                && bounds.contains(window.frame)
        }) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: wallpaper)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        config.width = max(1, Int((bounds.width * scale).rounded()))
        config.height = max(1, Int((barHeight * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
