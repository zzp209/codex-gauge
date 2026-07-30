import XCTest
@testable import CodexGauge

@MainActor
final class UsageModelTests: XCTestCase {
    func testMenuTitleIsCompactForWeeklySnapshot() {
        UserDefaults.standard.set("zh", forKey: LanguageKey)
        UserDefaults.standard.set("automatic", forKey: Prefs.menuMetricKey)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = UsageModel(provider: EmptyProvider(), autoStart: false)
        model.snapshot = makeSnapshot(
            eventTimestamp: now,
            resetsAt: now.addingTimeInterval(5 * 86_400 + 14 * 3_600)
        )

        XCTAssertEqual(model.menuBarTitle(now: now), "周 51%")
    }

    func testMenuTitleShowsWaitingWhenWindowExpired() {
        UserDefaults.standard.set("en", forKey: LanguageKey)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = UsageModel(provider: EmptyProvider(), autoStart: false)
        model.snapshot = makeSnapshot(
            eventTimestamp: now,
            resetsAt: now.addingTimeInterval(-1)
        )

        XCTAssertEqual(model.menuBarTitle(now: now), "! waiting")
    }

    func testRefreshNowLoadsSnapshotAndRecordsFreshHistory() async throws {
        let now = Date()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history-v1.json")
        defer {
            try? FileManager.default.removeItem(
                at: fileURL.deletingLastPathComponent()
            )
        }
        let snapshot = makeSnapshot(
            eventTimestamp: now,
            resetsAt: now.addingTimeInterval(5 * 86_400)
        )
        let history = SnapshotHistoryStore(fileURL: fileURL)
        let model = UsageModel(
            provider: FixedProvider(snapshot: snapshot),
            historyStore: history,
            autoStart: false
        )

        await model.refreshNow()

        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertNil(model.lastError)
        let points = try await history.allPoints()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.kindKey, "weekly")
    }

    func testRefreshNowDoesNotReplaceSnapshotWithOlderEvent() async {
        let now = Date()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history-v1.json")
        defer {
            try? FileManager.default.removeItem(
                at: fileURL.deletingLastPathComponent()
            )
        }
        let newer = makeSnapshot(
            eventTimestamp: now,
            resetsAt: now.addingTimeInterval(5 * 86_400)
        )
        let older = makeSnapshot(
            eventTimestamp: now.addingTimeInterval(-60),
            resetsAt: now.addingTimeInterval(5 * 86_400)
        )
        let model = UsageModel(
            provider: SequenceProvider(snapshots: [newer, older]),
            historyStore: SnapshotHistoryStore(fileURL: fileURL),
            autoStart: false
        )

        await model.refreshNow()
        await model.refreshNow()

        XCTAssertEqual(model.snapshot, newer)
        XCTAssertNil(model.lastError)
    }

    func testSuccessfulRefreshRecordsQuotaCheckTime() async {
        let checkTime = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot(
            eventTimestamp: checkTime.addingTimeInterval(-16 * 3_600),
            resetsAt: checkTime.addingTimeInterval(5 * 86_400)
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history-v1.json")
        defer {
            try? FileManager.default.removeItem(
                at: fileURL.deletingLastPathComponent()
            )
        }
        let model = UsageModel(
            provider: FixedProvider(snapshot: snapshot),
            historyStore: SnapshotHistoryStore(fileURL: fileURL),
            autoStart: false
        )

        await model.refreshNow(now: checkTime)

        XCTAssertEqual(model.lastSuccessfulQuotaCheckAt, checkTime)
        XCTAssertEqual(model.snapshot, snapshot)
    }

    func testDailyActivityRefreshIsIndependentFromQuotaRefresh() async {
        let activity = FixedActivityProvider(
            snapshot: DailyActivitySnapshot(
                newThreads: 10,
                sentMessages: 125,
                archivedThreads: 31
            )
        )
        let model = UsageModel(
            provider: EmptyProvider(),
            activityProvider: activity,
            autoStart: false
        )

        await model.refreshNow()

        XCTAssertNil(model.dailyActivity)
        let quotaOnlyInvocationCount = await activity.invocationCount
        XCTAssertEqual(quotaOnlyInvocationCount, 0)

        await model.refreshDailyActivityNow()

        XCTAssertEqual(
            model.dailyActivity,
            DailyActivitySnapshot(
                newThreads: 10,
                sentMessages: 125,
                archivedThreads: 31
            )
        )
        let activityInvocationCount = await activity.invocationCount
        XCTAssertEqual(activityInvocationCount, 1)
    }

    private func makeSnapshot(
        eventTimestamp: Date,
        resetsAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            planType: "pro",
            windows: [
                UsageWindowSnapshot(
                    id: "weekly",
                    kind: .weekly,
                    limitID: "codex",
                    limitName: nil,
                    remainingPercent: 51,
                    windowMinutes: 10_080,
                    resetsAt: resetsAt
                )
            ],
            credits: nil,
            source: SnapshotSource(
                sessionFile: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
                eventTimestamp: eventTimestamp,
                fileModificationDate: eventTimestamp
            )
        )
    }
}

private actor EmptyProvider: UsageSnapshotProviding {
    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        throw UsageDataError.noRateLimitEvents
    }
}

private actor FixedProvider: UsageSnapshotProviding {
    let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        snapshot
    }
}

private actor SequenceProvider: UsageSnapshotProviding {
    var snapshots: [UsageSnapshot]

    init(snapshots: [UsageSnapshot]) {
        self.snapshots = snapshots
    }

    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        guard !snapshots.isEmpty else {
            throw UsageDataError.noRateLimitEvents
        }
        return snapshots.removeFirst()
    }
}

private actor FixedActivityProvider: DailyActivityProviding {
    let snapshot: DailyActivitySnapshot
    private(set) var invocationCount = 0

    init(snapshot: DailyActivitySnapshot) {
        self.snapshot = snapshot
    }

    func latest(now: Date) async throws -> DailyActivitySnapshot {
        invocationCount += 1
        return snapshot
    }
}
