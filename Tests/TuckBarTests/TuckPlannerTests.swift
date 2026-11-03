import XCTest
@testable import TuckBar

final class TuckPlannerTests: XCTestCase {
    private func mode(enabled: Bool = true, snoozing: Bool = false, tagged: Int = 1,
                      displays: Int = 2, fullScreen: Bool = false) -> TuckMode {
        TuckPlanner.mode(enabled: enabled, snoozing: snoozing, taggedDisplaysPresent: tagged,
                         displayCount: displays, useFullScreen: fullScreen)
    }

    func testOffWhenDisabledSnoozingOrNothingTagged() {
        XCTAssertEqual(mode(enabled: false), .off)
        XCTAssertEqual(mode(snoozing: true), .off)
        XCTAssertEqual(mode(tagged: 0), .off)
        XCTAssertEqual(mode(enabled: false, fullScreen: true), .off)
        XCTAssertEqual(mode(snoozing: true, fullScreen: true), .off)
    }

    /// v0.1 behavior is unchanged when the new setting is off.
    func testMultiDisplayDefaultsToPerDisplayCover() {
        XCTAssertEqual(mode(displays: 2), .cover)
        XCTAssertEqual(mode(tagged: 2, displays: 3), .cover)
    }

    func testSingleDisplayAlwaysUsesNativeAutohide() {
        XCTAssertEqual(mode(displays: 1), .nativeAutohide)
        XCTAssertEqual(mode(displays: 1, fullScreen: true), .nativeAutohide)
    }

    /// Issue #1: MacBook + external monitor, user wants windows in the strip.
    func testUseFullScreenSwitchesMultiDisplayToNativeAutohide() {
        XCTAssertEqual(mode(displays: 2, fullScreen: true), .nativeAutohide)
        XCTAssertEqual(mode(tagged: 1, displays: 3, fullScreen: true), .nativeAutohide)
    }
}
