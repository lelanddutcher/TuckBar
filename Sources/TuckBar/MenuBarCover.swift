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
    private var wallpaperSig: [CGDirectDisplayID: [UInt8]] = [:]   // pixel fingerprint per display
    private var lastSignatureCheck = Date.distantPast
    private var signatureProbeInFlight = false
    private var barShowing: [CGDirectDisplayID: Bool] = [:]   // real bar on screen (#3)
    private var lastPresenceCheck = Date.distantPast
    private let lingerSeconds: TimeInterval = 0.7

    // Motion. Revealing has to feel instant, so it is a short fade rather than a snap; the
    // eye reads a 0.1 s fade as immediate but not as a jump cut. Tucking back is the moment
    // the user is not looking at the bar any more, so it can take its time and settle.
    private let revealFade: TimeInterval = 0.10
    private let tuckFade: TimeInterval = 0.45
    private let engageFade: TimeInterval = 0.6
    private let wallpaperCrossfade: TimeInterval = 0.8

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
            barShowing.removeValue(forKey: id)
            styleIsWallpaper.removeValue(forKey: id)
            wallpaperSig.removeValue(forKey: id)
        }

        for id in displayIDs {
            guard let screen = Self.screen(for: id) else {
                windows[id]?.orderOut(nil); windows.removeValue(forKey: id); continue
            }
            let isNew = windows[id] == nil
            let win = windows[id] ?? Self.makeWindow()
            win.setFrame(Self.menuBarFrame(for: screen), display: true)
            Self.applyHousingMask(win, for: screen)
            if !isNew, covered[id] == true { win.alphaValue = self.opacity }
            windows[id] = win

            let needsConfigure = isNew
                || styleIsWallpaper[id] != usesWallpaper
                || (usesWallpaper && wallpaperDirty)
            if needsConfigure {
                // only a wallpaper re-grab (same window, same style) → keep the current
                // strip up until the new one lands instead of flashing black
                let refreshOnly = !isNew && styleIsWallpaper[id] == usesWallpaper
                configure(win, for: screen, usesWallpaper: usesWallpaper, refreshOnly: refreshOnly)
                styleIsWallpaper[id] = usesWallpaper
                renderedKey[id] = usesWallpaper ? Self.wallpaperKey(for: screen) : nil
            }
            if isNew { covered[id] = nil }   // force re-evaluation
        }

        if usesWallpaper { wallpaperDirty = false }
        tick()
    }

    func removeAll() {
        for win in windows.values { fade(win, to: 0, duration: revealFade) }
        windows.removeAll(); revealedUntil.removeAll(); covered.removeAll(); styleIsWallpaper.removeAll()
        renderedKey.removeAll(); wallpaperSig.removeAll(); barShowing.removeAll()
        wallpaperDirty = true
    }

    /// Reveal the cover on whichever display the pointer is at the top of; otherwise keep
    /// it covered. Steps aside entirely when the display's menu bar isn't occupying space
    /// (a full-screen Space owns it). Cheap; called ~16×/sec.
    ///
    /// Driven by mouse-move events for an instant reveal, plus a slow timer that lets a
    /// lingering reveal expire when the pointer is still.
    func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        refreshBarPresence(now: now)
        for (id, win) in windows {
            guard let screen = Self.screen(for: id) else { continue }
            let f = screen.frame
            let inset = f.maxY - screen.visibleFrame.maxY
            // Prefer reading the bar itself; the inset stays non-zero in full screen on a
            // notched / Dynamic Island display, which is #3.
            let menuBarVisible = barShowing[id] ?? (inset > 1)
            let barHeight = max(inset, 24)
            let overTop = mouse.x >= f.minX && mouse.x < f.maxX && mouse.y >= f.maxY - barHeight
            if overTop { revealedUntil[id] = now.addingTimeInterval(lingerSeconds) }
            let lingering = revealedUntil[id].map { now < $0 } ?? false
            let shouldCover = menuBarVisible && !(overTop || lingering) && opacity > 0.001
            if covered[id] != shouldCover {
                let firstShow = covered[id] == nil
                if shouldCover {
                    fade(win, to: opacity, duration: firstShow ? engageFade : tuckFade)
                } else {
                    fade(win, to: 0, duration: firstShow ? 0 : revealFade)
                }
                covered[id] = shouldCover
            }
        }
        maybeRefreshWallpaper()
    }

    /// Fade a cover in or out. Interrupting a fade is safe: the animator retargets from the
    /// current alpha, and the order-out at the end only runs if the cover is still meant to
    /// be hidden, so a quick hover-off-hover-on never leaves it ordered out.
    private func fade(_ win: NSWindow, to alpha: CGFloat, duration: TimeInterval) {
        if alpha > 0, !win.isVisible {
            win.alphaValue = 0
            win.orderFrontRegardless()
        }
        guard duration > 0 else {
            win.alphaValue = alpha
            if alpha == 0 { win.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: alpha > 0 ? .easeInEaseOut : .easeOut)
            win.animator().alphaValue = alpha
        }, completionHandler: {
            Task { @MainActor in
                if alpha == 0, win.alphaValue < 0.001 { win.orderOut(nil) }
            }
        })
    }

    /// Re-read which displays' real bars are on screen. Throttled to 4 Hz; the window list
    /// is too heavy to walk on every mouse move.
    private func refreshBarPresence(now: Date) {
        guard now.timeIntervalSince(lastPresenceCheck) >= 0.25 else { return }
        lastPresenceCheck = now
        let bars = MenuBarPresence.currentBarWindows()
        for id in windows.keys {
            barShowing[id] = MenuBarPresence.isShowing(on: CGDisplayBounds(id), barWindows: bars)
        }
    }

    /// Re-read bar presence on the next tick (Space change: a full-screen app came or went).
    func invalidatePresence() { lastPresenceCheck = .distantPast }

    /// Detect a wallpaper change on a covered display and re-render that cover.
    /// Throttled; safe to call every tick.
    ///
    /// Two signals, because neither alone is enough: the `wallpaperKey` catches classic
    /// per-display changes (image URL, scaling, fill), while a small pixel fingerprint
    /// catches everything the modern wallpaper system hides behind a constant stub URL —
    /// light/dark switches, time-of-day shifts, and picking a new dynamic wallpaper.
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

        // pixel fingerprint: slower cadence, and never more than one probe in flight
        guard now.timeIntervalSince(lastSignatureCheck) >= 2.0, !signatureProbeInFlight else { return }
        lastSignatureCheck = now
        let targets = windows.filter { styleIsWallpaper[$0.key] == true }.map(\.key)
        guard !targets.isEmpty, ScreenCapture.hasPermission() else { return }
        signatureProbeInFlight = true
        Task { @MainActor in
            defer { self.signatureProbeInFlight = false }
            for id in targets {
                guard let win = self.windows[id], let screen = Self.screen(for: id) else { continue }
                let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
                guard let print = await ScreenCapture.wallpaperFingerprint(displayID: id, barHeight: barHeight) else { continue }
                guard self.windows[id] === win, self.styleIsWallpaper[id] == true else { continue }
                if let previous = self.wallpaperSig[id], ScreenCapture.fingerprintsDiffer(previous, print) {
                    self.configure(win, for: screen, usesWallpaper: true, refreshOnly: true)
                }
                self.wallpaperSig[id] = print
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

    /// Which compositing path the cover uses. Diagnostic only — see `renderMode` below.
    ///
    /// The framebuffer is provably correct in every mode: measured against the live
    /// wallpaper the cover matches to −0.229 luma, which is the wallpaper's own gradient,
    /// and that holds with the real menu bar composited underneath (so there is no alpha
    /// leak). Yet the strip still reads brighter than the desktop on a QD-OLED with HDR
    /// *off*. A difference that survives an identical framebuffer has to be introduced
    /// after the framebuffer — at scanout — and the likeliest cause is the cover being
    /// promoted to its own hardware overlay plane. It is an ideal candidate: opaque,
    /// rectangular, full-width, single-image contents, no sublayers.
    ///
    /// These modes perturb exactly that eligibility. They cannot be told apart by any
    /// screenshot; the panel is the only instrument that can see the difference.
    ///
    ///   defaults write com.lelanddutcher.TuckBar coverRenderMode -string opaque
    ///
    ///   default     current behaviour (control)
    ///   opaque      isOpaque = true — skips the blend path the cover never needed
    ///   nopromote   image in a child layer, so the tree is not a single flat surface
    ///   both        opaque + nopromote
    ///   imageview   NSImageView instead of raw layer contents (a different draw path)
    static var renderMode: String {
        UserDefaults.standard.string(forKey: "coverRenderMode") ?? "default"
    }

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        // An opaque window skips the blend against whatever is underneath. The cover is a
        // full-bleed opaque strip, so the blend buys nothing — but it does change which
        // compositing path the window server takes.
        let wantsOpaque = renderMode == "opaque" || renderMode == "both"
        win.isOpaque = wantsOpaque
        win.backgroundColor = wantsOpaque ? .black : .clear
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        // Snap in/out with no system show/hide animation. The default behavior lets macOS
        // scale/fade the window as it orders in (a "width-wise pop" on Tahoe), which reads
        // as the wallpaper tearing. The cover must just appear/vanish.
        win.animationBehavior = .none
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
    /// `refreshOnly` re-captures a cover that is already painted (the wallpaper changed).
    /// In that case the old strip stays on screen until the new one is ready and is then
    /// swapped in one step — blanking to black first would flash the cover on every
    /// refresh, which reads as flicker.
    private func configure(_ win: NSWindow, for screen: NSScreen, usesWallpaper: Bool, refreshOnly: Bool = false) {
        guard let base = win.contentView?.layer else { return }
        base.masksToBounds = true
        base.contentsScale = screen.backingScaleFactor
        // Kill implicit Core Animation on the cover layer. Otherwise resizing the window
        // from its initial .zero rect animates the layer's bounds/contents from zero to
        // full width (the "width-wise pop"), stretching the captured strip mid-grow and
        // tearing it against the wallpaper. The cover must update instantly.
        let noAnim = NSNull()
        base.actions = [
            "contents": noAnim, "bounds": noAnim, "position": noAnim, "backgroundColor": noAnim,
            "sublayers": noAnim, "opacity": noAnim, "hidden": noAnim,
            "onOrderIn": noAnim, "onOrderOut": noAnim,
        ]
        base.sublayers?.forEach { $0.removeFromSuperlayer() }
        // the imageview mode parks an NSImageView here; drop it when switching modes
        win.contentView?.subviews.forEach { $0.removeFromSuperview() }

        let id = Self.displayID(for: screen)
        if let id { wallpaperGen[id, default: 0] += 1 }      // invalidate any in-flight capture
        let token = id.flatMap { wallpaperGen[$0] }

        // Black immediately (this is also the fallback when capture is unavailable), but
        // never wipe a cover that's already showing a good strip — see `refreshOnly`.
        let keepExisting = refreshOnly && usesWallpaper && base.contents != nil
        if !keepExisting {
            base.isGeometryFlipped = false
            base.contents = nil
            base.backgroundColor = NSColor.black.cgColor
        }

        guard usesWallpaper, let id, let token, ScreenCapture.hasPermission() else { return }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard let image = await ScreenCapture.wallpaperStrip(displayID: id, barHeight: barHeight, scale: scale),
                  self.wallpaperGen[id] == token else { return }
            base.isGeometryFlipped = true     // captured CGImage is top-left origin
            // half-float (HDR) captures need an extended-range layer or they get clamped
            base.wantsExtendedDynamicRangeContent = image.bitsPerComponent > 8

            switch Self.renderMode {
            case "nopromote", "both":
                // Hand the image to a child layer instead of the root. A layer tree with
                // sublayers is a poorer candidate for promotion to a dedicated scanout
                // plane than a single flat surface, which is the thing under test.
                base.contents = nil
                base.backgroundColor = NSColor.black.cgColor
                let child = CALayer()
                child.actions = base.actions
                child.frame = base.bounds
                child.contentsScale = base.contentsScale
                child.contentsGravity = .resize
                child.wantsExtendedDynamicRangeContent = image.bitsPerComponent > 8
                child.contents = image
                base.addSublayer(child)

            case "imageview":
                // A different draw path entirely: AppKit renders the image rather than the
                // layer holding a CGImage as its contents.
                base.contents = nil
                base.backgroundColor = NSColor.black.cgColor
                let iv = NSImageView(frame: win.contentView?.bounds ?? .zero)
                iv.image = NSImage(cgImage: image, size: .zero)
                iv.imageScaling = .scaleAxesIndependently
                iv.autoresizingMask = [.width, .height]
                iv.wantsLayer = true
                win.contentView?.subviews.forEach { $0.removeFromSuperview() }
                win.contentView?.addSubview(iv)

            default:
                if keepExisting {
                    // The wallpaper changed under a cover that is already showing (rotating
                    // aerials, light/dark). Dissolve to the new strip instead of cutting.
                    let t = CATransition()
                    t.type = .fade
                    t.duration = self.wallpaperCrossfade
                    base.add(t, forKey: "wallpaperCrossfade")
                } else if win.isVisible, win.alphaValue > 0 {
                    // First strip over the black placeholder: a short dissolve, not a flash.
                    let t = CATransition()
                    t.type = .fade
                    t.duration = 0.25
                    base.add(t, forKey: "wallpaperCrossfade")
                }
                base.contents = image
                base.contentsGravity = .resize    // captured image IS the strip → fill 1:1
            }
        }
    }

    /// Leave the camera housing uncovered: the notch, or the Dynamic Island on the 2026
    /// OLED MacBook Pro. The island lives in the menu-bar strip and shows Live Activities;
    /// if macOS draws it below the cover's level, a full-width cover would hide it. On a
    /// notch the gap is black hardware either way, so this costs nothing there.
    private static func applyHousingMask(_ win: NSWindow, for screen: NSScreen) {
        guard let layer = win.contentView?.layer else { return }
        let size = win.frame.size
        guard let gap = housingGap(screenFrame: screen.frame,
                                   left: screen.auxiliaryTopLeftArea,
                                   right: screen.auxiliaryTopRightArea) else {
            layer.mask = nil
            return
        }
        let mask = CAShapeLayer()
        mask.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        mask.frame = CGRect(origin: .zero, size: size)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: gap.lowerBound, height: size.height))
        path.addRect(CGRect(x: gap.upperBound, y: 0, width: size.width - gap.upperBound, height: size.height))
        mask.path = path
        layer.mask = mask
    }

    /// The horizontal span of the camera housing in window-local x, from the areas macOS
    /// reports as usable on either side of it. `nil` on a display without one.
    nonisolated static func housingGap(screenFrame: NSRect, left: NSRect?, right: NSRect?) -> ClosedRange<CGFloat>? {
        guard let left, let right else { return nil }
        let start = left.maxX - screenFrame.minX
        let end = right.minX - screenFrame.minX
        guard end > start, start > 0, end < screenFrame.width else { return nil }
        return start...end
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
