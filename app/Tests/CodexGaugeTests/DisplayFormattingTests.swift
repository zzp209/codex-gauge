import XCTest
@testable import CodexGauge

final class DisplayFormattingTests: XCTestCase {
    func testCountdownShowsDaysAndHours() {
        XCTAssertEqual(
            DisplayFormatter.countdown(seconds: 5 * 86_400 + 14 * 3_600),
            "5d 14h"
        )
    }

    func testCountdownShowsHoursAndMinutes() {
        XCTAssertEqual(
            DisplayFormatter.countdown(seconds: 2 * 3_600 + 40 * 60),
            "2h 40m"
        )
    }

    func testWindowLabelsAreSemantic() {
        XCTAssertEqual(DisplayFormatter.shortLabel(for: .fiveHour, chinese: true), "5时")
        XCTAssertEqual(DisplayFormatter.shortLabel(for: .weekly, chinese: true), "周")
        XCTAssertEqual(
            DisplayFormatter.shortLabel(for: .custom(minutes: 1_440), chinese: true),
            "24时"
        )
    }
}
