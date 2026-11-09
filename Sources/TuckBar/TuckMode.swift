/// How TuckBar tucks the menu bar right now.
enum TuckMode: Equatable, Sendable {
    /// Not tucking: bars shown, nothing covered.
    case off
    /// Per-display overlay on the tagged display(s). Other monitors keep their bar, but the
    /// real bar still reserves its strip, so windows stop below it.
    case cover
    /// macOS's own "Automatically hide and show the menu bar". Windows can use the strip,
    /// but it applies to every display (macOS has no per-display switch).
    case nativeAutohide
}

/// Pure decision, kept separate from AppModel so it can be unit-tested.
enum TuckPlanner {
    /// - Parameters:
    ///   - useFullScreen: the user prefers usable space over per-display hiding (issue #1 / #5).
    static func mode(enabled: Bool, snoozing: Bool, taggedDisplaysPresent: Int,
                     displayCount: Int, useFullScreen: Bool) -> TuckMode {
        guard enabled, !snoozing, taggedDisplaysPresent > 0 else { return .off }
        // A single display has no other bar to keep, and an overlay there would leave no way
        // to reach the menu bar, so it always uses native auto-hide.
        if displayCount <= 1 || useFullScreen { return .nativeAutohide }
        return .cover
    }
}
