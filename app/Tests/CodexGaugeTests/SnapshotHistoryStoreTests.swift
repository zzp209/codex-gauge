import XCTest
@testable import CodexGauge

final class SnapshotHistoryStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testHistoryPointContainsNoSessionPathOrChatContent() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = SnapshotHistoryStore(fileURL: fileURL)
        let sensitivePath = "/Users/person/.codex/sessions/private-chat.jsonl"

        try await store.append(
            makeSnapshot(remaining: 70, sourcePath: sensitivePath),
            capturedAt: now
        )

        let text = try String(contentsOf: fileURL)
        XCTAssertFalse(text.contains("private-chat"))
        XCTAssertFalse(text.contains("/Users/person"))
        XCTAssertFalse(text.contains("prompt"))
        let points = try await store.allPoints()
        XCTAssertEqual(points.count, 1)
    }

    func testDoesNotAppendDuplicatePointWithinThirtyMinutes() async throws {
        let store = SnapshotHistoryStore(fileURL: temporaryFileURL())
        try await store.append(makeSnapshot(remaining: 70), capturedAt: now)
        try await store.append(
            makeSnapshot(remaining: 69.5),
            capturedAt: now.addingTimeInterval(20 * 60)
        )
        let points = try await store.allPoints()
        XCTAssertEqual(points.count, 1)
    }

    func testAppendsWhenRemainingChangesByAtLeastOnePoint() async throws {
        let store = SnapshotHistoryStore(fileURL: temporaryFileURL())
        try await store.append(makeSnapshot(remaining: 70), capturedAt: now)
        try await store.append(
            makeSnapshot(remaining: 68.9),
            capturedAt: now.addingTimeInterval(5 * 60)
        )
        let points = try await store.allPoints()
        XCTAssertEqual(points.count, 2)
    }

    func testAppendsWhenResetCycleChanges() async throws {
        let store = SnapshotHistoryStore(fileURL: temporaryFileURL())
        try await store.append(makeSnapshot(remaining: 10), capturedAt: now)
        try await store.append(
            makeSnapshot(
                remaining: 100,
                resetsAt: now.addingTimeInterval(14 * 86_400)
            ),
            capturedAt: now.addingTimeInterval(60)
        )
        let points = try await store.allPoints()
        XCTAssertEqual(points.count, 2)
    }

    func testPrunesPointsOlderThanNinetyDays() async throws {
        let store = SnapshotHistoryStore(fileURL: temporaryFileURL())
        try await store.append(
            makeSnapshot(remaining: 80),
            capturedAt: now.addingTimeInterval(-100 * 86_400)
        )
        try await store.append(makeSnapshot(remaining: 70), capturedAt: now)
        let points = try await store.allPoints()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.remainingPercent, 70)
    }

    func testComputesTwentyFourHourUsedPercentDelta() async throws {
        let store = SnapshotHistoryStore(fileURL: temporaryFileURL())
        try await store.append(
            makeSnapshot(remaining: 72),
            capturedAt: now.addingTimeInterval(-23 * 3_600)
        )
        try await store.append(
            makeSnapshot(remaining: 50),
            capturedAt: now
        )
        let delta = try await store.change(
            in: .weekly,
            last: 24 * 3_600,
            now: now
        )
        XCTAssertEqual(delta ?? 0, 22, accuracy: 0.001)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history-v1.json")
    }

    private func makeSnapshot(
        remaining: Double,
        resetsAt: Date? = nil,
        sourcePath: String = "/tmp/rollout.jsonl"
    ) -> UsageSnapshot {
        UsageSnapshot(
            planType: "pro",
            windows: [
                UsageWindowSnapshot(
                    id: "weekly",
                    kind: .weekly,
                    limitID: "codex",
                    limitName: nil,
                    remainingPercent: remaining,
                    windowMinutes: 10_080,
                    resetsAt: resetsAt ?? now.addingTimeInterval(7 * 86_400)
                )
            ],
            credits: nil,
            source: SnapshotSource(
                sessionFile: URL(fileURLWithPath: sourcePath),
                eventTimestamp: now,
                fileModificationDate: now
            )
        )
    }
}
