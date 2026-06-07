import CoreGraphics
import Foundation

/// A connected display, identified by a stable UUID string so we can recognize
/// the same physical monitor across unplug / replug cycles.
struct DisplayInfo: Identifiable, Hashable, Sendable {
    let id: String                 // stable UUID (CGDisplayCreateUUIDFromDisplayID)
    let displayID: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let widthPx: Int
    let heightPx: Int

    var resolutionText: String { "\(widthPx) × \(heightPx)" }
}

/// The four states of System Settings ▸ "Automatically hide and show the menu bar".
/// macOS stores this as two booleans in NSGlobalDomain. Verified mapping:
///
///   State                | _HIHideMenuBar | AppleMenuBarVisibleInFullscreen
///   ---------------------|----------------|--------------------------------
///   Always (hidden)      | true           | false
///   On Desktop Only      | true           | true
///   In Full Screen Only  | false          | false
///   Never (always shown) | false          | true
enum MenuBarVisibility: String, CaseIterable, Identifiable, Sendable {
    case never
    case inFullScreenOnly
    case onDesktopOnly
    case always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never:            return "Never Hidden"
        case .inFullScreenOnly: return "Hidden in Full Screen"
        case .onDesktopOnly:    return "Hidden on Desktop"
        case .always:           return "Always Hidden"
        }
    }

    /// The states offered in the UI (most → least hidden). "In Full Screen Only"
    /// is intentionally omitted: it leaves the static bar visible on the desktop,
    /// which defeats burn-in protection.
    static var protectCases: [MenuBarVisibility] { [.always, .onDesktopOnly, .never] }

    var hideMenuBar: Bool {
        switch self {
        case .always, .onDesktopOnly:   return true
        case .never, .inFullScreenOnly: return false
        }
    }

    var visibleInFullscreen: Bool {
        switch self {
        case .never, .onDesktopOnly:    return true
        case .always, .inFullScreenOnly: return false
        }
    }

    init(hideMenuBar: Bool, visibleInFullscreen: Bool) {
        switch (hideMenuBar, visibleInFullscreen) {
        case (true, false):  self = .always
        case (true, true):   self = .onDesktopOnly
        case (false, false): self = .inFullScreenOnly
        case (false, true):  self = .never
        }
    }
}
