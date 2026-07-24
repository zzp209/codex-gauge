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
            DisplayFormatter.longLabel(for: .weekly, chinese: true),
            "每周额度"
        )
        XCTAssertEqual(
            DisplayFormatter.longLabel(for: .fiveHour, chinese: true),
            "5 小时额度"
        )
        XCTAssertEqual(
            DisplayFormatter.shortLabel(for: .custom(minutes: 1_440), chinese: true),
            "24时"
        )
    }

    func testChineseResetDateUsesFriendlyMonthDayFormat() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!

        XCTAssertEqual(
            DisplayFormatter.resetDate(
                date,
                chinese: true,
                timeZone: timeZone
            ),
            "1月15日 16:00"
        )
    }

    func testZeroCreditBalanceStaysOutOfCompactPopover() {
        XCTAssertFalse(
            CreditsSnapshot(
                hasCredits: false,
                unlimited: false,
                balance: 0
            ).shouldDisplay
        )
        XCTAssertTrue(
            CreditsSnapshot(
                hasCredits: true,
                unlimited: false,
                balance: 5
            ).shouldDisplay
        )
    }
}
