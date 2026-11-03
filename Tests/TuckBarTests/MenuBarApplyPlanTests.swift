import XCTest
@testable import TuckBar

final class MenuBarApplyPlanTests: XCTestCase {

    // MARK: macOS 26 and earlier: unchanged v0.1 behavior

    func testTahoeKeepsOriginalOrder() {
        XCTAssertEqual(
            MenuBarApplyPlan.steps(for: .always, osMajorVersion: 26),
            [.systemEvents(hide: true),
             .writeDefaults(hide: true, visibleInFullscreen: false),
             .restartMenuBarAgents]
        )
    }

    func testSonomaAndSequoiaMatchTahoe() {
        for major in [14, 15] {
            XCTAssertEqual(
                MenuBarApplyPlan.steps(for: .never, osMajorVersion: major),
                MenuBarApplyPlan.steps(for: .never, osMajorVersion: 26),
                "macOS \(major)"
            )
        }
    }

    // MARK: macOS 27+: System Events last, no SystemUIServer restart

    func testGoldenGateRunsSystemEventsLast() {
        for v in MenuBarVisibility.allCases {
            let steps = MenuBarApplyPlan.steps(for: v, osMajorVersion: 27)
            XCTAssertEqual(steps.last, .systemEvents(hide: v.hideMenuBar), "\(v)")
        }
    }

    func testGoldenGateNeverRestartsMenuBarAgents() {
        for major in [27, 28] {
            for v in MenuBarVisibility.allCases {
                XCTAssertFalse(
                    MenuBarApplyPlan.steps(for: v, osMajorVersion: major).contains(.restartMenuBarAgents),
                    "macOS \(major) \(v)"
                )
            }
        }
    }

    func testGoldenGateStillPersistsDefaults() {
        XCTAssertEqual(
            MenuBarApplyPlan.steps(for: .never, osMajorVersion: 27),
            [.writeDefaults(hide: false, visibleInFullscreen: true),
             .systemEvents(hide: false)]
        )
    }

    // MARK: Every OS: a restart never follows the System Events call it would undo

    func testNoRestartAfterSystemEventsOn27() {
        let steps = MenuBarApplyPlan.steps(for: .always, osMajorVersion: 27)
        guard let se = steps.firstIndex(of: .systemEvents(hide: true)) else {
            return XCTFail("missing System Events step")
        }
        XCTAssertFalse(steps[se...].contains(.restartMenuBarAgents))
    }

    // MARK: OS version parsing

    func testParseMajor() {
        XCTAssertEqual(OSVersion.parseMajor("27.2.1"), 27)
        XCTAssertEqual(OSVersion.parseMajor("26.0"), 26)
        XCTAssertEqual(OSVersion.parseMajor("15"), 15)
        XCTAssertEqual(OSVersion.parseMajor(" 27.1\n"), 27)
        XCTAssertNil(OSVersion.parseMajor(""))
        XCTAssertNil(OSVersion.parseMajor("abc"))
        XCTAssertNil(OSVersion.parseMajor("0.1"))
    }

    func testRunningMajorIsPlausible() {
        // Package.swift requires macOS 14+, so anything lower means the read went wrong.
        XCTAssertGreaterThanOrEqual(OSVersion.major, 14)
    }
}
