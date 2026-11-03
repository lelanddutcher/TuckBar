import Darwin
import Foundation

/// One side effect performed while applying a menu-bar visibility state.
enum MenuBarApplyStep: Equatable, Sendable {
    /// `tell application "System Events" to set autohide menu bar of dock preferences …`
    case systemEvents(hide: Bool)
    /// Persist `_HIHideMenuBar` + `AppleMenuBarVisibleInFullscreen` in NSGlobalDomain.
    case writeDefaults(hide: Bool, visibleInFullscreen: Bool)
    /// `killall ControlCenter` + `killall SystemUIServer` so the bar redraws at once.
    case restartMenuBarAgents
}

/// Decides *which* steps apply a menu-bar visibility state, and in what order, for a
/// given macOS major version. Pure (no system calls) so it can be unit-tested.
///
/// - macOS 26 and earlier: System Events applies the change live, the defaults are
///   persisted, then ControlCenter / SystemUIServer are restarted so the change shows
///   immediately with no flash. (Unchanged from v0.1.)
/// - macOS 27 and later: the menu bar is rendered by a single window and defaults writes
///   no longer move it. Restarting SystemUIServer brings the bar back *revealed*, which
///   would undo the System Events call that preceded it. So we persist the defaults
///   first and make System Events the last word, with no agent restart.
///   (Reported in paulsp94/omacosy#97, reproduced on macOS 27.2; needs on-device
///   confirmation for TuckBar, see the tracking issue.)
enum MenuBarApplyPlan {
    /// First macOS major version that uses the System-Events-last ordering.
    static let systemEventsLastMajor = 27

    static func steps(for v: MenuBarVisibility, osMajorVersion: Int) -> [MenuBarApplyStep] {
        let write = MenuBarApplyStep.writeDefaults(hide: v.hideMenuBar, visibleInFullscreen: v.visibleInFullscreen)
        let apply = MenuBarApplyStep.systemEvents(hide: v.hideMenuBar)
        if osMajorVersion >= systemEventsLastMajor {
            return [write, apply]
        }
        return [apply, write, .restartMenuBarAgents]
    }
}

/// The running macOS major version.
enum OSVersion {
    /// Real major version of the running OS.
    ///
    /// Reads `kern.osproductversion` rather than trusting `ProcessInfo` alone: a binary
    /// linked against an older SDK can be handed a compatibility version number
    /// (e.g. "16.0" on macOS 26), which would silently pick the wrong apply order.
    /// The sysctl reports the real version (the compat value lives in the separate
    /// `kern.osproductversioncompat`).
    static var major: Int {
        if let s = sysctlString("kern.osproductversion"), let m = parseMajor(s) { return m }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// "27.2.1" → 27. Returns nil for anything that doesn't start with a positive integer.
    static func parseMajor(_ version: String) -> Int? {
        let head = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let n = Int(head), n > 0 else { return nil }
        return n
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
