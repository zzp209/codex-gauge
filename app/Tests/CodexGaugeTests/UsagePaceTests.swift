import XCTest
@testable import CodexGauge

final class UsagePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWeeklyWindowWithMoreQuotaThanTimeSuggestsUseMore() {
        let window = makeWindow(
            kind: .weekly,
            remaining: 70,
            minutes: 10_080,
            secondsToReset: 3.5 * 86_400
        )
        let result = UsagePaceEvaluator.evaluate(window, now: now)
        XCTAssertEqual(result.status, .useMore)
        XCTAssertEqual(result.paceGap ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(result.recommendedPointsPerDay ?? 0, 20, accuracy: 0.01)
    }

    func testHighRemainingWithin24HoursIsWasteRisk() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .weekly,
                remaining: 30,
                minutes: 10_080,
                secondsToReset: 20 * 3_600
            ),
            now: now
        )
        XCTAssertEqual(result.status, .wasteRisk)
    }

    func testLowRemainingFarFromResetIsQuotaTight() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .weekly,
                remaining: 8,
                minutes: 10_080,
                secondsToReset: 2 * 86_400
            ),
            now: now
        )
        XCTAssertEqual(result.status, .quotaTight)
    }

    func testLowRemainingInFiveHourWindowIsQuotaTightBeforeFinalHour() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .fiveHour,
                remaining: 8,
                minutes: 300,
                secondsToReset: 2 * 3_600
            ),
            now: now
        )
        XCTAssertEqual(result.status, .quotaTight)
    }

    func testNegativeGapIsAheadOfPace() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .weekly,
                remaining: 30,
                minutes: 10_080,
                secondsToReset: 5.6 * 86_400
            ),
            now: now
        )
        XCTAssertEqual(result.status, .aheadOfPace)
    }

    func testBalancedWindowStaysBalanced() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .weekly,
                remaining: 60,
                minutes: 10_080,
                secondsToReset: 4.0 * 86_400
            ),
            now: now
        )
        XCTAssertEqual(result.status, .balanced)
    }

    func testPastResetIsExpired() {
        let result = UsagePaceEvaluator.evaluate(
            makeWindow(
                kind: .weekly,
                remaining: 60,
                minutes: 10_080,
                secondsToReset: -1
            ),
            now: now
        )
        XCTAssertEqual(result.status, .expired)
    }

    func testFreshnessUsesEventTimestampAndAllWindowResetDates() {
        let active = makeWindow(
            kind: .weekly,
            remaining: 60,
            minutes: 10_080,
            secondsToReset: 86_400
        )
        let expired = makeWindow(
            kind: .fiveHour,
            remaining: 10,
            minutes: 300,
            secondsToReset: -1
        )
        XCTAssertEqual(
            UsagePaceEvaluator.freshness(
                eventTimestamp: now.addingTimeInterval(-10 * 60),
                windows: [active, expired],
                now: now
            ),
            .fresh
        )
        XCTAssertEqual(
            UsagePaceEvaluator.freshness(
                eventTimestamp: now.addingTimeInterval(-30 * 60),
                windows: [active],
                now: now
            ),
            .aging
        )
        XCTAssertEqual(
            UsagePaceEvaluator.freshness(
                eventTimestamp: now.addingTimeInterval(-3 * 3_600),
                windows: [active],
                now: now
            ),
            .stale
        )
        XCTAssertEqual(
            UsagePaceEvaluator.freshness(
                eventTimestamp: now,
                windows: [expired],
                now: now
            ),
            .expiredWindow
        )
    }

    func testAutomaticMenuSelectionPrefersHigherSeverityThenWeekly() {
        let fiveHour = makeWindow(
            kind: .fiveHour,
            remaining: 50,
            minutes: 300,
            secondsToReset: 2.5 * 3_600
        )
        let weekly = makeWindow(
            kind: .weekly,
            remaining: 55,
            minutes: 10_080,
            secondsToReset: 3.85 * 86_400
        )
        let selected = UsageMenuSelector.select(
            windows: [fiveHour, weekly],
            preference: .automatic,
            now: now
        )
        XCTAssertEqual(selected?.kind, .weekly)
    }

    private func makeWindow(
        kind: UsageWindowKind,
        remaining: Double,
        minutes: Int,
        secondsToReset: TimeInterval
    ) -> UsageWindowSnapshot {
        UsageWindowSnapshot(
            id: kind.key,
            kind: kind,
            limitID: "codex",
            limitName: nil,
            remainingPercent: remaining,
            windowMinutes: minutes,
            resetsAt: now.addingTimeInterval(secondsToReset)
        )
    }
}
