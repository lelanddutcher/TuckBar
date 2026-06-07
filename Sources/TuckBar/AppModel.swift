import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Central coordinator for TuckBar. Protects displays you tag by covering their
/// menu bar with a per-display overlay (opaque = hidden, semi-transparent = dimmed),
/// while leaving other monitors' menu bars untouched. When the protected display is
/// the *only* one connected, it falls back to the native global auto-hide (so you
/// still get hover-reveal and aren't left with no accessible menu bar).
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
    private var appliedAutohide: Bool?     // global auto-hide state we last set
    private var savedDock: Bool?           // Dock autohide before we hid it for protection
    private var snoozeUntil: Date?
    private var snoozeTimer: Timer?
    private var revealTimer: Timer?        // drives the cover's hover-reveal

    private let defaults = UserDefaults.standard
    private var ready = false

    private enum Keys {
        static let enabled = "autoProtectEnabled"
        static let protectedIDs = "protectedDisplayIDs"
        static let coverOpacity = "coverOpacity"
        static let coverWallpaper = "coverUsesWallpaper"
        static let hideDock = "protectDock"
        static let snoozeDuration = "snoozeDurationMinutes"
        static let displayNames = "displayNames"
    }

    private init() {
        Self.migrateFromMenuBarHideIfNeeded(into: defaults)

        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        protectedDisplayIDs = Set(defaults.array(forKey: Keys.protectedIDs) as? [String] ?? [])
        coverOpacity = defaults.object(forKey: Keys.coverOpacity) as? Double ?? 1.0
        coverUsesWallpaper = defaults.object(forKey: Keys.coverWallpaper) as? Bool ?? true
        hideDockWhenProtected = defaults.object(forKey: Keys.hideDock) as? Bool ?? false
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

        ready = true
        Task { @MainActor in AppModel.shared.evaluate() }
    }

    private static func migrateFromMenuBarHideIfNeeded(into defaults: UserDefaults) {
        let migratedFlag = "migratedFromMenuBarHide"
        guard !defaults.bool(forKey: migratedFlag) else { return }
        defaults.set(true, forKey: migratedFlag)
        guard let old = UserDefaults(suiteName: "com.lelanddutcher.MenuBarHide") else { return }
        for key in [Keys.enabled, Keys.protectedIDs, Keys.hideDock, Keys.snoozeDuration, Keys.displayNames]
        where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
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
    /// True when protecting but the protected display is the only one connected,
    /// so we use the native auto-hide instead of an overlay.
    var usingAutohideFallback: Bool { isProtecting && displays.count <= 1 }

    private func evaluate() {
        guard ready else { return }

        let present = protectedDisplaysPresent
        let active = isEnabled && !present.isEmpty && !isSnoozing
        isProtecting = active

        guard active else {
            // Not protecting right now: uncover, show bars, restore the Dock.
            stopRevealTracking()
            cover.removeAll()
            setGlobalAutohide(false)
            restoreDock()
            return
        }

        if displays.count <= 1 {
            // Only the protected display is connected → native auto-hide fallback.
            stopRevealTracking()
            cover.removeAll()
            setGlobalAutohide(true)
        } else {
            // Multiple displays → cover the protected one(s), keep the others' bars.
            setGlobalAutohide(false)
            cover.update(displayIDs: Set(present.map(\.displayID)), opacity: coverOpacity, usesWallpaper: coverUsesWallpaper)
            startRevealTracking()
        }

        if hideDockWhenProtected {
            if savedDock == nil { savedDock = SystemSettings.dockAutohide() }
            if !SystemSettings.dockAutohide() { SystemSettings.setDockAutohide(true) }
        } else {
            restoreDock()
        }
    }

    private func refreshCovers() {
        guard isProtecting, displays.count > 1 else { return }
        cover.update(displayIDs: Set(protectedDisplaysPresent.map(\.displayID)), opacity: coverOpacity, usesWallpaper: coverUsesWallpaper)
    }

    /// Toggle the global OS auto-hide, only when it actually needs to change
    /// (avoids redundant ControlCenter/SystemUIServer refreshes).
    private func setGlobalAutohide(_ on: Bool) {
        guard appliedAutohide != on else { return }
        SystemSettings.setMenuBarVisibility(on ? .always : .never)
        appliedAutohide = on
    }

    private func restoreDock() {
        if let saved = savedDock {
            SystemSettings.setDockAutohide(saved)
            savedDock = nil
        }
    }

    // MARK: - Hover-reveal timer (drives MenuBarCover.tick)

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

    var statusSymbol: String {
        if !isEnabled { return "shield.slash" }
        if isSnoozing { return "timer" }
        if isProtecting { return "shield.lefthalf.filled" }
        return "shield"
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
        setGlobalAutohide(false)
        restoreDock()
    }

    func quit() {
        restoreForQuit()
        NSApp.terminate(nil)
    }
}
