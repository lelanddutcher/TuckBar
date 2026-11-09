import CoreGraphics
import XCTest
@testable import TuckBar

final class MenuBarPresenceTests: XCTestCase {
    // A 4K main display and a portrait display to its left, as on the dev Mac.
    let main = CGRect(x: 0, y: 0, width: 3840, height: 2160)
    let side = CGRect(x: -1200, y: 85, width: 1200, height: 1920)

    func bar(_ display: CGRect, y: CGFloat? = nil, alpha: Double = 1) -> MenuBarPresence.BarWindow {
        .init(bounds: CGRect(x: display.minX, y: y ?? display.minY, width: display.width, height: 30), alpha: alpha)
    }

    func testVisibleBarIsShowing() {
        XCTAssertEqual(MenuBarPresence.isShowing(on: main, barWindows: [bar(main), bar(side)]), true)
    }

    func testTransparentBarIsHidden() {
        // macOS 27: a hidden bar stays at the top edge and is drawn transparent.
        XCTAssertEqual(MenuBarPresence.isShowing(on: main, barWindows: [bar(main, alpha: 0), bar(side)]), false)
    }

    func testBarMovedOffTheTopIsHidden() {
        // macOS 15: a hidden bar moves above the display.
        XCTAssertEqual(MenuBarPresence.isShowing(on: main, barWindows: [bar(main, y: -24)]), false)
    }

    func testOtherDisplaysBarDoesNotCount() {
        XCTAssertEqual(MenuBarPresence.isShowing(on: main, barWindows: [bar(main, alpha: 0), bar(side, alpha: 1)]), false)
        XCTAssertEqual(MenuBarPresence.isShowing(on: side, barWindows: [bar(main, alpha: 0), bar(side, alpha: 1)]), true)
    }

    func testNoBarWindowIsUnknown() {
        XCTAssertNil(MenuBarPresence.isShowing(on: main, barWindows: [bar(side)]))
        XCTAssertNil(MenuBarPresence.isShowing(on: main, barWindows: []))
    }
}
