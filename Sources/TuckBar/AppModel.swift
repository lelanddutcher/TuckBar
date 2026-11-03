import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Central coordinator for TuckBar. Tucks the menu bar on displays you tag by covering
/// it with a per-display overlay (opaque = hidden, semi-transparent = dimmed), while
/// leaving other monitors' menu bars untouched. When the tagged display is the *only*
/// one connected, it falls back to the native global auto-hide (so you still get
/// hover-reveal and aren't left with no accessible menu bar).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    static let snoozeChoices = [5, 10, 15, 30, 60]

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var displayNames: [String: String] = [:]

    /// True while protection is actively engaged (covering or auto-hiding).
    @Published private(set) var isProtecting = false

    @Published private(set) var isSnoozing = false
    @Published private(set) var snoozeRemaining: TimeInterval = 0

    /// True when wallpaper mode is active but Screen Recording permission is missing.
    @Published private(set) var needsScreenRecording = false

    /// True when a System Events call was refused — Automation permission is missing,
    /// so the menu-bar / Dock toggles silently do nothing until it's granted.
    @Published private(set) var needsAutomation = false

    // Persisted configuration.
    @Published var isEnabled: Bool {
        didSet { guard ready else { return }; defaults.set(isEnabled, forKey: Keys.enabled); evaluate() }
    }
    @Published var protectedDisplayIDs: Set<String> {
        didSet { guard ready else { return }; defaults.set(Array(protectedDisplayIDs), forKey: Keys.protectedIDs); evaluate() }
    }
    /// Overlay opacity for protected displays: 1 = hidden (black), <1 = dimmed, 0 = off.
    @Published var coverOpacity: Double {
        didSet {
            guard ready else { return }
            defaults.set(coverOpacity, forKey: Keys.coverOpacity)
            if isProtecting { refreshCovers() }
        }
    }
    /// Cover style: true = seamless desktop-wallpaper slice, false = solid black.
    @Published var coverUsesWallpaper: Bool {
        didSet {
            guard ready else { return }
            defaults.set(coverUsesWallpaper, forKey: Keys.coverWallpaper)
            if isProtecting { refreshCovers() }
        }
    }
    /// Use macOS's own auto-hide even with several displays, so windows can grow into the
    /// menu-bar strip on the tagged display. Trade-off: the bar hides on every display.
    @Published var useFullScreen: Bool {
        didSet { guard ready else { return }; defaults.set(useFullScreen, forKey: Keys.useFullScreen); evaluate() }
    }
    @Published var hideDockWhenProtected: Bool {
        didSet { guard ready else { return }; defaults.set(hideDockWhenProtected, forKey: Keys.hideDock); evaluate() }
    }
    @Published var snoozeDurationMinutes: Int {
        didSet { guard ready else { return }; defaults.set(snoozeDurationMinutes, forKey: Keys.snoozeDuration) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard ready else { return }
            if LoginItemManager.setEnabled(launchAtLogin) == false {
                ready = false
                launchAtLogin = LoginItemManager.isEnabled
                ready = true
            }
        }
    }

    // Engine state.
    private let cover = MenuBarCover()
    private var appliedAutohide: Bool?     // global auto-hide state we last set (nil = unknown)
    private var savedDock: Bool?           // Dock autohide before we hid it for protection
    private var snoozeUntil: Date?
    private var snoozeTimer: Timer?
    private var revealTimer: Timer?        // drives the cover's hover-reveal
    private var requestedScreenRecording = false

    /// Serial queue for the blocking System Events / `defaults` calls, so they never
    /// stall the main thread — especially the first Automation consent prompt, which
    /// blocks until the user responds. Serial so ordered toggles stay ordered.
    private let systemQueue = DispatchQueue(label: "com.lelanddutcher.TuckBar.system", qos: .userInitiated)

    private let defaults = UserDefaults.standard
    private var ready = false

    private enum Keys {
        static let enabled = "autoProtectEnabled"
        static let protectedIDs = "protectedDisplayIDs"
        static let coverOpacity = "coverOpacity"
        static let coverWallpaper = "coverUsesWallpaper"
        static let hideDock = "protectDock"
        static let useFullScreen = "useFullScreenWhenTucked"
        static let snoozeDuration = "snoozeDurationMinutes"
        static let displayNames = "displayNames"
        /// Marks that *we* enabled the global auto-hide, so a crash/force-quit that skips
        /// `restoreForQuit` can be reconciled (and the bar restored) at next launch.
        static let setAutohide = "tuckbarSetGlobalAutohide"
    }

    private init() {
        Self.migrateFromMenuBarHideIfNeeded(into: defaults)

        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        protectedDisplayIDs = Set(defaults.array(forKey: Keys.protectedIDs) as? [String] ?? [])
        coverOpacity = defaults.object(forKey: Keys.coverOpacity) as? Double ?? 1.0
        coverUsesWallpaper = defaults.object(forKey: Keys.coverWallpaper) as? Bool ?? true
        hideDockWhenProtected = defaults.object(forKey: Keys.hideDock) as? Bool ?? false
        useFullScreen = defaults.object(forKey: Keys.useFullScreen) as? Bool ?? false
        snoozeDurationMinutes = defaults.object(forKey: Keys.snoozeDuration) as? Int ?? 10
        displayNames = defaults.dictionary(forKey: Keys.displayNames) as? [String: String] ?? [:]
        launchAtLogin = LoginItemManager.isEnabled

        refreshDisplays()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in Task { @MainActor in AppModel.shared.handleScreenChange() } }

        // Per-Space wallpapers differ — refresh the cover image when the Space changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { _ in Task { @MainActor in AppModel.shared.handleSpaceChange() } }

        // Light/Dark switches can swap the wallpaper variant — refresh then too.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in Task { @MainActor in AppModel.shared.handleSpaceChange() } }

        // Re-check Screen Recording when the user returns to the app after granting it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { _ in Task { @MainActor in AppModel.shared.recheckPermission() } }

        // NB: these observers live for the whole process (AppModel is a true singleton)
        // and capture `AppModel.shared`, not `self`, so there's no retain cycle and no
        // dangling-observer crash. A future de-singleton would need a `deinit` that
        // removes them.

        ready = true
        Task { @MainActor in
            AppModel.shared.reconcileMenuBarAtLaunch()
            AppModel.shared.evaluate()
        }
    }

    private static func migrateFromMenuBarHideIfNeeded(into defaults: UserDefaults) {
        let migratedFlag = "migratedFromMenuBarHide"
        guard !defaults.bool(forKey: migratedFlag) else { return }
        guard let old = UserDefaults(suiteName: "com.lelanddutcher.MenuBarHide") else {
            defaults.set(true, forKey: migratedFlag)
            return
        }
        for key in [Keys.enabled, Keys.protectedIDs, Keys.hideDock, Keys.snoozeDuration, Keys.displayNames]
        where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: migratedFlag)
    }

    // MARK: - Display tracking

    private func handleScreenChange() {
        refreshDisplays()
        cover.invalidateWallpaper()   // geometry changed → re-render the slice
        evaluate()
    }

    private func handleSpaceChange() {
        cover.invalidateWallpaper()
        evaluate()
    }

    private func refreshDisplays() {
        let mainID = CGMainDisplayID()
        var list: [DisplayInfo] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = number.uint32Value as CGDirectDisplayID
            let uuid = Self.uuid(for: displayID) ?? "screen-\(displayID)"
            let scale = screen.backingScaleFactor
            list.append(DisplayInfo(
                id: uuid, displayID: displayID, name: screen.localizedName,
                isMain: displayID == mainID,
                widthPx: Int(screen.frame.width * scale), heightPx: Int(screen.frame.height * scale)
            ))
        }
        var names = displayNames
        for display in list { names[display.id] = display.name }
        if names != displayNames {
            displayNames = names
            defaults.set(names, forKey: Keys.displayNames)
        }
        displays = list
    }

    private static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        return CFUUIDCreateString(nil, unmanaged.takeRetainedValue()) as String?
    }

    // MARK: - Engine

    var protectedDisplaysPresent: [DisplayInfo] {
        displays.filter { protectedDisplayIDs.contains($0.id) }
    }
    var hasTaggedDisplay: Bool { !protectedDisplayIDs.isEmpty }
    var taggedDisplayNames: [String] {
        protectedDisplayIDs.map { displayNames[$0] ?? "a tagged display" }.sorted()
    }
    /// The mode the engine should be in for the current state.
    var tuckMode: TuckMode {
        TuckPlanner.mode(enabled: isEnabled, snoozing: isSnoozing,
                         taggedDisplaysPresent: protectedDisplaysPresent.count,
                         displayCount: displays.count, useFullScreen: useFullScreen)
    }
    /// True when protecting with macOS's native auto-hide instead of an overlay: the tagged
    /// display is the only one connected, or the user chose "Use the full screen".
    var usingAutohideFallback: Bool { isProtecting && tuckMode == .nativeAutohide }

    private func evaluate() {
        guard ready else { return }

        let present = protectedDisplaysPresent
        let mode = tuckMode
        let active = mode != .off
        isProtecting = active

        guard active else {
            // Not protecting right now: uncover, show bars, restore the Dock.
            stopRevealTracking()
            cover.removeAll()
            setGlobalAutohide(false)
            restoreDock()
            needsScreenRecording = false
            return
        }

        if mode == .nativeAutohide {
            // Single display, or "Use the full screen": native auto-hide, so windows can use
            // the strip (global: no per-display switch exists).
            stopRevealTracking()
            cover.removeAll()
            setGlobalAutohide(true)
        } else {
            // Multiple displays → cover the protected one(s), keep the others' bars.
            setGlobalAutohide(false)
            cover.update(displayIDs: Set(present.map(\.displayID)), opacity: coverOpacity, usesWallpaper: coverUsesWallpaper)
            updateRevealTracking()
        }

        if hideDockWhenProtected {
            if savedDock == nil { savedDock = SystemSettings.dockAutohide() }
            if savedDock == false { setDockAutohideAsync(true) }
        } else {
            restoreDock()
        }

        updatePermissionState()
    }

    private func refreshCovers() {
        guard isProtecting, tuckMode == .cover else { return }
        cover.update(displayIDs: Set(protectedDisplaysPresent.map(\.displayID)), opacity: coverOpacity, usesWallpaper: coverUsesWallpaper)
        updateRevealTracking()
        updatePermissionState()
    }

    /// Track whether wallpaper capture needs Screen Recording permission, requesting it once.
    private func updatePermissionState() {
        let usingCapture = isProtecting && coverUsesWallpaper && tuckMode == .cover
        if usingCapture && !ScreenCapture.hasPermission() {
            needsScreenRecording = true
            if !requestedScreenRecording {
                requestedScreenRecording = true
                ScreenCapture.requestPermission()
            }
        } else {
            needsScreenRecording = false
        }
    }

    /// Re-check Screen Recording (e.g. the user just granted it in System Settings and
    /// came back) and re-render the cover in place — no relaunch needed.
    func recheckPermission() {
        guard ready else { return }
        let wasMissing = needsScreenRecording
        updatePermissionState()
        if wasMissing && !needsScreenRecording && isProtecting {
            cover.invalidateWallpaper()
            refreshCovers()
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - System toggles (off-main, ordered, failure-aware)

    /// Toggle the global OS auto-hide. The blocking System Events call runs off-main;
    /// `appliedAutohide` and the crash-recovery marker are only committed on success, so
    /// a denied Automation prompt leaves us free to retry once it's granted.
    private func setGlobalAutohide(_ on: Bool) {
        guard appliedAutohide != on else { return }
        let target: MenuBarVisibility = on ? .always : .never
        systemQueue.async {
            let ok = SystemSettings.setMenuBarVisibility(target)
            Task { @MainActor in AppModel.shared.didApplyAutohide(on, success: ok) }
        }
    }

    private func didApplyAutohide(_ on: Bool, success: Bool) {
        if success {
            appliedAutohide = on
            defaults.set(on, forKey: Keys.setAutohide)
            needsAutomation = false
        } else {
            needsAutomation = true   // leave appliedAutohide unset so a retry can fire
        }
    }

    private func setDockAutohideAsync(_ on: Bool) {
        systemQueue.async {
            let ok = SystemSettings.setDockAutohide(on)
            if !ok { Task { @MainActor in AppModel.shared.needsAutomation = true } }
        }
    }

    private func restoreDock() {
        guard let saved = savedDock else { return }
        savedDock = nil
        systemQueue.async {
            // Only revert if the Dock is still auto-hiding (the state we set). If the user
            // changed it themselves while protecting, leave their choice alone.
            if SystemSettings.dockAutohide() {
                _ = SystemSettings.setDockAutohide(saved)
            }
        }
    }

    /// If a prior session enabled the global auto-hide and didn't restore it (crash /
    /// force-quit, where `applicationWillTerminate` never fires), clear it at launch so
    /// the user is never stranded with a permanently hidden menu bar.
    private func reconcileMenuBarAtLaunch() {
        guard defaults.bool(forKey: Keys.setAutohide) else { return }
        appliedAutohide = true       // so setGlobalAutohide(false) actually fires
        setGlobalAutohide(false)
    }

    // MARK: - Hover-reveal timer (drives MenuBarCover.tick)

    /// Run the reveal poll only when there's actually a visible cover to reveal.
    private func updateRevealTracking() {
        if coverOpacity > 0.001 { startRevealTracking() } else { stopRevealTracking() }
    }

    private func startRevealTracking() {
        guard revealTimer == nil else { return }
        let timer = Timer(timeInterval: 0.06, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.cover.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    private func stopRevealTracking() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    // MARK: - Snooze ("Untuck")

    func snooze(minutes: Int) {
        snoozeDurationMinutes = minutes
        snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        snoozeRemaining = TimeInterval(minutes * 60)
        isSnoozing = true
        startSnoozeTimer()
        evaluate()   // reveal everything
    }

    func startSnooze() { snooze(minutes: snoozeDurationMinutes) }

    func endSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeUntil = nil
        snoozeRemaining = 0
        isSnoozing = false
        evaluate()   // re-protect
    }

    private func startSnoozeTimer() {
        snoozeTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.tickSnooze() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    private func tickSnooze() {
        guard let until = snoozeUntil else { return }
        let remaining = until.timeIntervalSinceNow
        if remaining <= 0 { endSnooze() } else { snoozeRemaining = remaining }
    }

    var snoozeRemainingText: String {
        let total = max(0, Int(snoozeRemaining.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - UI helpers

    var statusGlyph: NSImage {
        MenuBarGlyph.current(snoozing: isSnoozing, enabled: isEnabled)
    }

    func refreshAll() { refreshDisplays() }
    func isProtected(_ id: String) -> Bool { protectedDisplayIDs.contains(id) }
    func toggleProtected(_ id: String) {
        if protectedDisplayIDs.contains(id) { protectedDisplayIDs.remove(id) }
        else { protectedDisplayIDs.insert(id) }
    }

    // MARK: - Lifecycle

    func restoreForQuit() {
        stopRevealTracking()
        cover.removeAll()
        // Clear the crash-recovery marker synchronously and restore the bar/Dock.
        defaults.set(false, forKey: Keys.setAutohide)
        if appliedAutohide == true {
            _ = SystemSettings.setMenuBarVisibility(.never)
            appliedAutohide = false
        }
        if let saved = savedDock {
            savedDock = nil
            if SystemSettings.dockAutohide() { _ = SystemSettings.setDockAutohide(saved) }
        }
    }

    func quit() {
        restoreForQuit()
        NSApp.terminate(nil)
    }
}
