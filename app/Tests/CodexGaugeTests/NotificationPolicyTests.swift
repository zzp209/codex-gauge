import XCTest
@testable import CodexGauge

final class NotificationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTightQuotaReminderCanBeDisabledIndependently() {
        let window = makeWindow(remaining: 8, hoursToReset: 72)
        let notifications = NotificationPolicy.notifications(
            window: window,
            evaluation: .init(
                status: .quotaTight,
                timeRemainingPercent: 40,
                paceGap: -32,
                recommendedPointsPerHour: nil,
                recommendedPointsPerDay: nil
            ),
            freshness: .fresh,
            now: now,
            sentKeys: [],
            preferences: ReminderPreferences(
                quotaTight: false,
                wasteRisk: true,
                dailyPace: false,
                dailyHour: 17
            )
        )

        XCTAssertTrue(notifications.isEmpty)
    }

    func testEventReminderTakesPriorityOverDailySummary() {
        let window = makeWindow(remaining: 30, hoursToReset: 20)
        let notifications = NotificationPolicy.notifications(
            window: window,
            evaluation: UsagePaceEvaluator.evaluate(window, now: now),
            freshness: .fresh,
            now: now,
            sentKeys: [],
            preferences: ReminderPreferences(
                quotaTight: true,
                wasteRisk: true,
                dailyPace: true,
                dailyHour: 0
            )
        )

        XCTAssertEqual(notifications.map(\.kind), [.waste24Hours])
    }

    func testDailyReminderUsesConfiguredLocalHour() {
        let calendar = Calendar.current
        let before = calendar.date(
            from: DateComponents(
                year: 2027,
                month: 1,
                day: 15,
                hour: 19,
                minute: 59
            )
        )!
        let atTime = calendar.date(
            from: DateComponents(
                year: 2027,
                month: 1,
                day: 15,
                hour: 20
            )
        )!

        XCTAssertFalse(
            NotificationPolicy.isDailyReminderTime(
                now: before,
                hour: 20
            )
        )
        XCTAssertTrue(
            NotificationPolicy.isDailyReminderTime(
                now: atTime,
                hour: 20
            )
        )
    }

    func testDailySummaryDoesNotDuplicateForFiveHourWindow() {
        let window = UsageWindowSnapshot(
            id: "five-hour",
            kind: .fiveHour,
            limitID: "codex",
            limitName: nil,
            remainingPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(4 * 3_600)
        )
        let notifications = NotificationPolicy.notifications(
            window: window,
            evaluation: .init(
                status: .useMore,
                timeRemainingPercent: 80,
                paceGap: 0,
                recommendedPointsPerHour: 5,
                recommendedPointsPerDay: nil
            ),
            freshness: .fresh,
            now: now,
            sentKeys: [],
            preferences: ReminderPreferences(
                quotaTight: true,
                wasteRisk: true,
                dailyPace: true,
                dailyHour: 0
            )
        )

        XCTAssertTrue(notifications.isEmpty)
    }

    func testNoNotificationForAgingSnapshot() {
        let notifications = NotificationPolicy.pendingNotifications(
            window: makeWindow(remaining: 40, hoursToReset: 20),
            evaluation: .init(
                status: .wasteRisk,
                timeRemainingPercent: 10,
                paceGap: 30,
                recommendedPointsPerHour: nil,
                recommendedPointsPerDay: nil
            ),
            freshness: .aging,
            now: now,
            sentKeys: []
        )
        XCTAssertTrue(notifications.isEmpty)
    }

    func testTwentyFourHourWasteReminderIsDeduplicated() {
        let window = makeWindow(remaining: 30, hoursToReset: 20)
        let evaluation = UsagePaceEvaluator.evaluate(window, now: now)
        let first = NotificationPolicy.pendingNotifications(
            window: window,
            evaluation: evaluation,
            freshness: .fresh,
            now: now,
            sentKeys: []
        )
        XCTAssertEqual(first.map(\.kind), [.waste24Hours])

        let second = NotificationPolicy.pendingNotifications(
            window: window,
            evaluation: evaluation,
            freshness: .fresh,
            now: now,
            sentKeys: Set(first.map(\.dedupeKey))
        )
        XCTAssertTrue(second.isEmpty)
    }

    func testNewResetCycleCanNotifyAgain() {
        let firstWindow = makeWindow(remaining: 30, hoursToReset: 20)
        let first = try! XCTUnwrap(
            NotificationPolicy.pendingNotifications(
                window: firstWindow,
                evaluation: UsagePaceEvaluator.evaluate(firstWindow, now: now),
                freshness: .fresh,
                now: now,
                sentKeys: []
            ).first
        )
        let nextWindow = makeWindow(remaining: 30, hoursToReset: 20, resetOffset: 7 * 86_400)
        let nextNow = now.addingTimeInterval(7 * 86_400)
        let next = NotificationPolicy.pendingNotifications(
            window: nextWindow,
            evaluation: UsagePaceEvaluator.evaluate(nextWindow, now: nextNow),
            freshness: .fresh,
            now: nextNow,
            sentKeys: [first.dedupeKey]
        )
        XCTAssertEqual(next.map(\.kind), [.waste24Hours])
    }

    func testBalancedFiveHourWindowDoesNotTriggerWeeklySixHourReminder() {
        let window = UsageWindowSnapshot(
            id: "five-hour",
            kind: .fiveHour,
            limitID: "codex",
            limitName: nil,
            remainingPercent: 60,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3 * 3_600)
        )
        let notifications = NotificationPolicy.pendingNotifications(
            window: window,
            evaluation: UsagePaceEvaluator.evaluate(window, now: now),
            freshness: .fresh,
            now: now,
            sentKeys: []
        )
        XCTAssertTrue(notifications.isEmpty)
    }

    private func makeWindow(
        remaining: Double,
        hoursToReset: Double,
        resetOffset: TimeInterval = 0
    ) -> UsageWindowSnapshot {
        UsageWindowSnapshot(
            id: "weekly",
            kind: .weekly,
            limitID: "codex",
            limitName: nil,
            remainingPercent: remaining,
            windowMinutes: 10_080,
            resetsAt: now.addingTimeInterval(hoursToReset * 3_600 + resetOffset)
        )
    }
}
