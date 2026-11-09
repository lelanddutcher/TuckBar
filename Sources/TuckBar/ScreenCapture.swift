import Cocoa
import ScreenCaptureKit

/// Captures the *real, on-screen* wallpaper pixels behind the menu bar so the cover is
/// pixel-perfect. (A copy rendered from the wallpaper *file* can't match — macOS
/// composites a scaled/zoomed version, which is the source of the alignment drift.)
///
/// We capture the desktop behind the menu bar via **ScreenCaptureKit**
/// (`SCScreenshotManager`, macOS 14+), clipped to the menu-bar strip — a stable,
/// supported API (no obsoleted `CGWindowListCreateImageFromArray` shim). Requires
/// Screen Recording permission; without it, callers fall back to a black cover.
enum ScreenCapture {
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    /// `composited` (the default) captures the desktop as macOS draws it; the other modes
    /// capture the bare wallpaper window and are kept for diagnosis:
    ///   defaults write com.lelanddutcher.TuckBar coverCaptureMode -string sck
    static var captureMode: String {
        UserDefaults.standard.string(forKey: "coverCaptureMode") ?? "composited"
    }

    /// The per-display wallpaper window. The Dock drew it up to macOS 26; on macOS 27
    /// WindowManager does. Match on what both share (the title, a below-desktop layer,
    /// full coverage of the display) rather than on the owner, so the next move does not
    /// silently turn the cover black again.
    static func wallpaperWindow(in content: SCShareableContent, bounds: CGRect) -> SCWindow? {
        content.windows.first { window in
            (window.title?.hasPrefix("Wallpaper") ?? false)
                && window.windowLayer < 0
                && bounds.contains(window.frame)
        }
    }

    /// The display as composited, minus every window at layer 0 or above: app windows,
    /// the menu bar, status items, MenuBarAgent's strip and our own cover. What is left is
    /// the wallpaper, the "underbelly" gradient over it, and the Finder desktop.
    static func desktopFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        SCContentFilter(display: display, excludingWindows: content.windows.filter { $0.windowLayer >= 0 })
    }

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

        let mode = captureMode
        let display = content.displays.first(where: { $0.displayID == displayID })
        let wallpaper = wallpaperWindow(in: content, bounds: bounds)

        // `composited` fixes the real defect. macOS draws a legibility gradient over the
        // top of the screen in a Window Server window literally named "underbelly"
        // (3840x183 at the origin, sitting just above the wallpaper and below app
        // windows). It is not part of the wallpaper, so capturing the Dock's wallpaper
        // window — which is what every other mode does — misses it entirely and the cover
        // comes out far brighter than the desktop it is supposed to disappear into.
        // Measured on a QD-OLED: the seam step against the desktop just below the bar goes
        // from +65.06 luma to -1.71 when the gradient is included.
        //
        // Compositing the display is what picks the gradient up, so the filter has to keep
        // desktop-level windows while dropping everything else. Excluding `windowLayer >= 0`
        // drops app windows (a browser parked at the top would otherwise be captured *into*
        // the cover), the menu bar, status items, and our own cover, while keeping the
        // wallpaper, the underbelly, and the Finder desktop.
        //
        // It is also the only path that works on macOS 27, where the wallpaper window moved
        // from the Dock to WindowManager: it needs the display, not a particular window.
        // The wallpaper-window path is kept as the fallback and for the diagnostic modes.
        let filter: SCContentFilter
        if mode == "composited", let display {
            filter = desktopFilter(display: display, content: content)
        } else if let wallpaper {
            filter = SCContentFilter(desktopIndependentWindow: wallpaper)
        } else if let display {
            filter = desktopFilter(display: display, content: content)
        } else {
            return nil
        }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        config.width = max(1, Int((bounds.width * scale).rounded()))
        config.height = max(1, Int((barHeight * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        // The captured pixels already match the desktop exactly (verified: 0.00 luma delta
        // per row). Any remaining difference is in how the strip is *color-managed* on the
        // way to a wide-gamut panel, which screenshots can't show — they re-composite both
        // sides through the same conversion. So the mode is switchable and judged by eye:
        //   defaults write com.lelanddutcher.TuckBar coverCaptureMode -string display
        // NB: `pixelFormat` is ignored by SCScreenshotManager for stills (always 8-bit
        // BGRA), so the only way to get more precision is the HDR path — but on an HDR
        // display that path is actively harmful: asking for extended range makes macOS
        // allocate EDR headroom and tone-map the cover differently from the SDR desktop
        // around it, which shows up as a seam. Plain SDR is the default for that reason.
        // Default is plain SDR: measured on an HDR QD-OLED, the capture already comes back
        // tagged in the display's own space, so no conversion happens and no EDR is requested.
        switch mode {
        case "hdr":                                                 // 16-bit half-float (forces EDR)
            if #available(macOS 15.0, *) { config.captureDynamicRange = .hdrLocalDisplay }
        case "p3":   config.colorSpaceName = CGColorSpace.displayP3
        case "srgb": config.colorSpaceName = CGColorSpace.sRGB
        default: break                                              // "sck"/"retag" = SCK default
        }

        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return nil }

        // The captured pixels are the display's own composited pixels, but the CGImage may
        // be *tagged* with a different space (the display's profile has no name, so it
        // can't be requested via `colorSpaceName`). A wrong tag makes Core Animation
        // convert on the way back to the panel — a small midtone/contrast shift that
        // screenshots can't reveal, since they re-convert both sides identically.
        // Re-tagging without converting makes the round-trip an identity.
        if mode == "retag", let displaySpace = CGDisplayCopyColorSpace(displayID) as CGColorSpace?,
           let retagged = image.copy(colorSpace: displaySpace) {
            return retagged
        }
        return image
    }

    /// True when two fingerprints differ by more than capture noise.
    ///
    /// Compared with a tolerance rather than hashed: repeated grabs of an unchanged
    /// wallpaper still differ slightly (dither/rounding — measured max 6/255, mean ~0.15),
    /// so any hash is unstable and would re-capture forever. A real wallpaper change moves
    /// the mean by tens, so this threshold sits far above the noise and well below a change.
    static func fingerprintsDiffer(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        var total = 0
        for i in 0..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
        return Double(total) / Double(a.count) > 2.0
    }

    /// A cheap content fingerprint of the wallpaper strip, used to notice that the
    /// wallpaper actually changed.
    ///
    /// We can't detect this from `NSWorkspace.desktopImageURL`: with the modern
    /// (dynamic / aerial) wallpaper system that returns a constant 54-byte stub
    /// (`DefaultDesktop.heic`) with empty options, so a URL-based key never changes —
    /// light/dark switches, time-of-day shifts and "Change Wallpaper" all go unnoticed.
    /// Sampling the pixels is the only reliable signal. Captured tiny (64×4) so it costs
    /// far less than a full strip grab.
    static func wallpaperFingerprint(displayID: CGDirectDisplayID, barHeight: CGFloat) async -> [UInt8]? {
        guard barHeight > 0 else { return nil }
        let bounds = CGDisplayBounds(displayID)

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return nil }
        // Sample the same source the cover is drawn from, so a change in either the
        // wallpaper or the gradient over it is noticed.
        let filter: SCContentFilter
        if let wallpaper = wallpaperWindow(in: content, bounds: bounds), captureMode != "composited" {
            filter = SCContentFilter(desktopIndependentWindow: wallpaper)
        } else if let display = content.displays.first(where: { $0.displayID == displayID }) {
            filter = desktopFilter(display: display, content: content)
        } else {
            return nil
        }

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        config.width = 64
        config.height = 4
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return nil }

        // Redraw into a fixed, unpadded buffer. The captured image's own backing store has
        // padded rows holding uninitialized bytes that differ on every grab.
        let w = 64, h = 4, bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }
}
