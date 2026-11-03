import XCTest
@testable import TuckBar

final class MenuBarVisibilityTests: XCTestCase {

    /// The verified System Settings mapping documented on `MenuBarVisibility`.
    func testBooleanMapping() {
        XCTAssertEqual(MenuBarVisibility(hideMenuBar: true, visibleInFullscreen: false), .always)
        XCTAssertEqual(MenuBarVisibility(hideMenuBar: true, visibleInFullscreen: true), .onDesktopOnly)
        XCTAssertEqual(MenuBarVisibility(hideMenuBar: false, visibleInFullscreen: false), .inFullScreenOnly)
        XCTAssertEqual(MenuBarVisibility(hideMenuBar: false, visibleInFullscreen: true), .never)
    }

    func testRoundTrip() {
        for v in MenuBarVisibility.allCases {
            XCTAssertEqual(MenuBarVisibility(hideMenuBar: v.hideMenuBar, visibleInFullscreen: v.visibleInFullscreen), v)
        }
    }

    func testProtectCasesOmitFullScreenOnly() {
        XCTAssertFalse(MenuBarVisibility.protectCases.contains(.inFullScreenOnly))
    }
}
