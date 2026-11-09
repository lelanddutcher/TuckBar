import AppKit
import XCTest
@testable import TuckBar

final class HousingGapTests: XCTestCase {
    // 14" MacBook Pro in its default scaling: 1512 x 982 pt, notch about 185 pt wide.
    let frame = NSRect(x: 0, y: 0, width: 1512, height: 982)

    func testNotchGapIsBetweenTheTwoAreas() {
        let gap = MenuBarCover.housingGap(screenFrame: frame,
                                          left: NSRect(x: 0, y: 950, width: 663, height: 32),
                                          right: NSRect(x: 849, y: 950, width: 663, height: 32))
        XCTAssertEqual(gap, 663...849)
    }

    func testGapIsWindowLocalOnAnOffsetDisplay() {
        let offset = NSRect(x: -1512, y: 0, width: 1512, height: 982)
        let gap = MenuBarCover.housingGap(screenFrame: offset,
                                          left: NSRect(x: -1512, y: 950, width: 663, height: 32),
                                          right: NSRect(x: -663, y: 950, width: 663, height: 32))
        XCTAssertEqual(gap, 663...849)
    }

    func testNoHousingNoGap() {
        XCTAssertNil(MenuBarCover.housingGap(screenFrame: frame, left: nil, right: nil))
        // Areas that touch or overlap describe no housing.
        XCTAssertNil(MenuBarCover.housingGap(screenFrame: frame,
                                             left: NSRect(x: 0, y: 950, width: 756, height: 32),
                                             right: NSRect(x: 756, y: 950, width: 756, height: 32)))
    }
}
