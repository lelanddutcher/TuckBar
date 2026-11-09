import Foundation

/// When to ask for an App Store rating. Pure, so it can be unit-tested.
///
/// The ask goes through StoreKit, which decides whether the prompt actually appears and
/// caps it at three a year. This only picks the moment: after TuckBar has been doing its
/// job for a while, never in the first days, and at most once per version.
enum ReviewPolicy {
    static let minProtectedHours: Double = 10
    static let minDaysSinceFirstUse: Double = 3

    static func shouldAsk(protectedSeconds: TimeInterval, firstUse: Date, now: Date,
                          lastAskedVersion: String?, currentVersion: String) -> Bool {
        guard lastAskedVersion != currentVersion else { return false }
        guard protectedSeconds >= minProtectedHours * 3600 else { return false }
        return now.timeIntervalSince(firstUse) >= minDaysSinceFirstUse * 86_400
    }
}
