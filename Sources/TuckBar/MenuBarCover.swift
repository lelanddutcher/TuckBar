import AppKit

/// Per-display overlay windows that cover the menu-bar strip on chosen displays.
///
/// The cover can be **solid black** (pixels off = most burn-in-protective) or a
/// **seamless wallpaper slice** — it captures the *real on-screen pixels* of the
/// display's wallpaper behind the menu bar (via `ScreenCapture` / ScreenCaptureKit), so
/// the bar appears to simply vanish and the wallpaper continues to the top edge with no
/// alignment drift. Either way it auto-hides on hover (see `tick()`), steps aside when a
/// full-screen Space owns the display, and only ever touches the displays you tag.
@MainActor
final class MenuBarCover {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var revealedUntil: [CGDirectDisplayID: Date] = [:]
    private var covered: [CGDirectDisplayID: Bool] = [:]   // current shown-state (nil = unknown)
    private var styleIsWallpaper: [CGDirectDisplayID: Bool] = [:]
    private var wallpaperGen: [CGDirectDisplayID: Int] = [:]   // drops stale async captures
    private var opacity: CGFloat = 1
    private var wallpaperDirty = true                       // reload images on next configure
    private var renderedKey: [CGDirectDisplayID: String] = [:]   // wallpaper identity last rendered
    private var lastWallpaperCheck = Date.distantPast
    private let lingerSeconds: TimeInterval = 0.7

    var isActive: Bool { !windows.isEmpty }

    /// Mark wallpaper images stale (call on Space / display changes).
    func invalidateWallpaper() { wallpaperDirty = true }

    func update(displayIDs: Set<CGDirectDisplayID>, opacity: Double, usesWallpaper: Bool) {
        self.opacity = CGFloat(max(0, min(1, opacity)))

        for (id, win) in windows where !displayIDs.contains(id) {
            win.orderOut(nil)
            windows.removeValue(forKey: id)
            revealedUntil.removeValue(forKey: id)
            covered.removeValue(forKey: id)
            styleIsWallpaper.removeValue(forKey: id)
        }

        for id in displayIDs {
            guard let screen = Self.screen(for: id) else {
                windows[id]?.orderOut(nil); windows.removeValue(forKey: id); continue
            }
            let isNew = windows[id] == nil
            let win = windows[id] ?? Self.makeWindow()
            win.setFrame(Self.menuBarFrame(for: screen), display: true)
            win.alphaValue = self.opacity
            windows[id] = win

            let needsConfigure = isNew
                || styleIsWallpaper[id] != usesWallpaper
                || (usesWallpaper && wallpaperDirty)
            if needsConfigure {
                configure(win, for: screen, usesWallpaper: usesWallpaper)
                styleIsWallpaper[id] = usesWallpaper
                renderedKey[id] = usesWallpaper ? Self.wallpaperKey(for: screen) : nil
            }
            if isNew { covered[id] = nil }   // force re-evaluation
        }

        if usesWallpaper { wallpaperDirty = false }
        tick()
    }

    func removeAll() {
        for win in windows.values { win.orderOut(nil) }
        windows.removeAll(); revealedUntil.removeAll(); covered.removeAll(); styleIsWallpaper.removeAll()
        renderedKey.removeAll()
        wallpaperDirty = true
    }

    /// Reveal the cover on whichever display the pointer is at the top of; otherwise keep
    /// it covered. Steps aside entirely when the display's menu bar isn't occupying space
    /// (a full-screen Space owns it). Cheap; called ~16×/sec.
    func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        for (id, win) in windows {
            guard let screen = Self.screen(for: id) else { continue }
            let f = screen.frame
            let inset = f.maxY - screen.visibleFrame.maxY
            let menuBarVisible = inset > 1            // ~0 when a full-screen Space owns this display
            let barHeight = max(inset, 24)
            let overTop = mouse.x >= f.minX && mouse.x < f.maxX && mouse.y >= f.maxY - barHeight
            if overTop { revealedUntil[id] = now.addingTimeInterval(lingerSeconds) }
            let lingering = revealedUntil[id].map { now < $0 } ?? false
            let shouldCover = menuBarVisible && !(overTop || lingering) && opacity > 0.001
            if covered[id] != shouldCover {
                if shouldCover {
                    win.alphaValue = opacity
                    win.orderFrontRegardless()
                } else {
                    win.orderOut(nil)
                }
                covered[id] = shouldCover
            }
        }
        maybeRefreshWallpaper()
    }

    /// Detect a wallpaper change (new image, scaling, or fill) on a covered display
    /// and re-render that cover. Throttled to ~1×/sec; safe to call every tick.
    private func maybeRefreshWallpaper() {
        let now = Date()
        guard now.timeIntervalSince(lastWallpaperCheck) >= 1.0 else { return }
        lastWallpaperCheck = now
        for (id, win) in windows where styleIsWallpaper[id] == true {
            guard let screen = Self.screen(for: id) else { continue }
            let key = Self.wallpaperKey(for: screen)
            if renderedKey[id] != key {
                configure(win, for: screen, usesWallpaper: true)
                renderedKey[id] = key
            }
        }
    }

    private static func wallpaperKey(for screen: NSScreen) -> String {
        let url = NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "none"
        let opts = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let scaling = (opts[.imageScaling] as? NSNumber)?.intValue ?? -1
        let clip = (opts[.allowClipping] as? NSNumber)?.boolValue ?? true
        let fill = (opts[.fillColor] as? NSColor)?.description ?? ""
        return "\(url)|\(scaling)|\(clip)|\(fill)"
    }

    // MARK: - Window + content

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        win.contentView = view
        return win
    }

    /// Fill the cover with the *captured* wallpaper slice behind the menu bar
    /// (pixel-perfect — the real on-screen pixels), or black if wallpaper mode is off or
    /// Screen Recording permission isn't granted yet. Capture is async (ScreenCaptureKit),
    /// so the cover shows black until the strip arrives; a per-display generation token
    /// drops stale captures after a fast style / Space switch.
    private func configure(_ win: NSWindow, for screen: NSScreen, usesWallpaper: Bool) {
        guard let base = win.contentView?.layer else { return }
        base.masksToBounds = true
        base.contentsScale = screen.backingScaleFactor
        base.sublayers?.forEach { $0.removeFromSuperlayer() }

        let id = Self.displayID(for: screen)
        if let id { wallpaperGen[id, default: 0] += 1 }      // invalidate any in-flight capture
        let token = id.flatMap { wallpaperGen[$0] }

        // Black immediately (this is also the fallback when capture is unavailable).
        base.isGeometryFlipped = false
        base.contents = nil
        base.backgroundColor = NSColor.black.cgColor

        guard usesWallpaper, let id, let token, ScreenCapture.hasPermission() else { return }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard let image = await ScreenCapture.wallpaperStrip(displayID: id, barHeight: barHeight, scale: scale),
                  self.wallpaperGen[id] == token else { return }
            base.isGeometryFlipped = true     // captured CGImage is top-left origin
            base.contents = image
            base.contentsGravity = .resize    // captured image IS the strip → fill 1:1
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func menuBarFrame(for screen: NSScreen) -> NSRect {
        let f = screen.frame
        let barHeight = max(f.maxY - screen.visibleFrame.maxY, 24)
        return NSRect(x: f.minX, y: f.maxY - barHeight, width: f.width, height: barHeight)
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
