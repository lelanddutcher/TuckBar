import XCTest
@testable import TuckBar

final class ReviewPolicyTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600
    let day: TimeInterval = 86_400

    func ask(hours: Double, days: Double, last: String? = nil, current: String = "0.2.0") -> Bool {
        ReviewPolicy.shouldAsk(protectedSeconds: hours * hour, firstUse: start,
                               now: start.addingTimeInterval(days * day),
                               lastAskedVersion: last, currentVersion: current)
    }

    func testAsksOnceBothThresholdsAreMet() {
        XCTAssertTrue(ask(hours: 10, days: 3))
        XCTAssertTrue(ask(hours: 40, days: 30))
    }

    func testWaitsForEnoughTucking() {
        XCTAssertFalse(ask(hours: 9.9, days: 30))
    }

    func testNeverInTheFirstDays() {
        // Heavy use on day one still waits: a rating asked for too early is a worse rating.
        XCTAssertFalse(ask(hours: 48, days: 2.9))
    }

    func testOncePerVersion() {
        XCTAssertFalse(ask(hours: 40, days: 30, last: "0.2.0", current: "0.2.0"))
        XCTAssertTrue(ask(hours: 40, days: 30, last: "0.2.0", current: "0.3.0"))
    }
}
