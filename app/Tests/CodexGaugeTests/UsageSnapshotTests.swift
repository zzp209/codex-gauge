import XCTest
@testable import CodexGauge

final class UsageSnapshotTests: XCTestCase {
    func testClassifiesKnownAndCustomWindows() {
        XCTAssertEqual(UsageWindowKind(minutes: 300), .fiveHour)
        XCTAssertEqual(UsageWindowKind(minutes: 10_080), .weekly)
        XCTAssertEqual(UsageWindowKind(minutes: 1_440), .custom(minutes: 1_440))
        XCTAssertEqual(UsageWindowKind(minutes: nil), .unknown)
    }

    func testClampsRemainingPercent() {
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: -5), 100)
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: 49), 51)
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: 120), 0)
    }
}
