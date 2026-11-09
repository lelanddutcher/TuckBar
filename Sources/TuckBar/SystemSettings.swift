import Foundation

/// Reads and applies the system preferences we manage: the menu-bar visibility
/// (Control Center ▸ "Automatically hide and show the menu bar") and Dock auto-hide.
///
/// Both are applied through System Events, which animates the change smoothly —
/// exactly like toggling it in System Settings — with no process relaunch and no
/// visual flash. Requires the one-time Automation permission.
///
/// The mutating calls block (subprocess / AppleEvent round-trip and, on first use, the
/// Automation consent prompt), so callers must invoke them **off the main thread**
/// (see `AppModel.systemQueue`). Each returns `false` if System Events couldn't be
/// driven — e.g. Automation was denied — so the caller can surface that.
enum SystemSettings {

    // MARK: Menu bar

    static func menuBarVisibility() -> MenuBarVisibility {
        let hide = readBool("NSGlobalDomain", "_HIHideMenuBar") ?? false
        let visFS = readBool("NSGlobalDomain", "AppleMenuBarVisibleInFullscreen") ?? true
        return MenuBarVisibility(hideMenuBar: hide, visibleInFullscreen: visFS)
    }

    /// Applies `v` using the step order for the running OS (see `MenuBarApplyPlan`:
    /// macOS 27 needs System Events to run last, with no SystemUIServer restart).
    @discardableResult
    static func setMenuBarVisibility(_ v: MenuBarVisibility) -> Bool {
        var ok = true
        for step in MenuBarApplyPlan.steps(for: v, osMajorVersion: OSVersion.major) {
            switch step {
            case .systemEvents(let hide):
                ok = systemEvents("set autohide menu bar of dock preferences to \(hide ? "true" : "false")")
            case .writeDefaults(let hide, let visibleInFullscreen):
                // Persist (incl. the full-screen nuance, applied on the next FS transition).
                writeBool("NSGlobalDomain", "_HIHideMenuBar", hide)
                writeBool("NSGlobalDomain", "AppleMenuBarVisibleInFullscreen", visibleInFullscreen)
            case .restartMenuBarAgents:
                // Redraw the menu-bar agents in place (no flash; needed so the change shows at once).
                killall("ControlCenter")
                killall("SystemUIServer")
            }
        }
        return ok
    }

    // MARK: Dock

    static func dockAutohide() -> Bool {
        readBool("com.apple.dock", "autohide") ?? false
    }

    @discardableResult
    static func setDockAutohide(_ on: Bool) -> Bool {
        // Drive the Dock through System Events so it animates smoothly. `killall
        // Dock` would relaunch it and flash the desktop background — avoid it.
        let ok = systemEvents("set autohide of dock preferences to \(on ? "true" : "false")")
        writeBool("com.apple.dock", "autohide", on)
        return ok
    }

    // MARK: - Plumbing

    /// Runs one System Events command in-process (so the Automation consent prompt is
    /// attributed to TuckBar and uses our usage string). Returns `false` on failure.
    @discardableResult
    private static func systemEvents(_ command: String) -> Bool {
        let source = "tell application \"System Events\" to \(command)"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            NSLog("TuckBar: System Events failed (\(command)): \(error)")
            return false
        }
        return true
    }

    @discardableResult
    private static func defaults(_ args: [String]) -> String? {
        run("/usr/bin/defaults", args)
    }

    static func readBool(_ domain: String, _ key: String) -> Bool? {
        guard let out = defaults(["read", domain, key])?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        switch out.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    static func writeBool(_ domain: String, _ key: String, _ value: Bool) {
        defaults(["write", domain, key, "-bool", value ? "true" : "false"])
    }

    private static func killall(_ name: String) {
        run("/usr/bin/killall", [name])
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
