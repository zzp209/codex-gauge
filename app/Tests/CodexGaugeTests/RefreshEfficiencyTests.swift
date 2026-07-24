import XCTest
@testable import CodexGauge

final class RefreshEfficiencyTests: XCTestCase {
    func testStatusPresentationCacheOnlyAppliesMeaningfulChanges() {
        var cache = StatusPresentationCache()
        let initial = StatusPresentation(title: "周 44%", tone: .warning)

        XCTAssertTrue(cache.shouldApply(initial))
        XCTAssertFalse(cache.shouldApply(initial))
        XCTAssertTrue(
            cache.shouldApply(
                StatusPresentation(title: "周 44%", tone: .critical)
            )
        )
    }

    func testFallbackPollingNeverRunsMoreOftenThanFiveMinutes() {
        XCTAssertEqual(Prefs.normalizedFallbackInterval(30), 300)
        XCTAssertEqual(Prefs.normalizedFallbackInterval(60), 300)
        XCTAssertEqual(Prefs.normalizedFallbackInterval(900), 900)
    }

    func testSessionDirectoryWatcherObservesNestedRolloutWrites() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("2026/07/24", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let changed = expectation(description: "rollout changed")
        changed.assertForOverFulfill = true
        let watcher = SessionDirectoryWatcher(
            latency: 0.05,
            debounceInterval: 0.05
        )
        try watcher.start(path: root.path) {
            changed.fulfill()
        }
        defer { watcher.stop() }

        let rollout = nested.appendingPathComponent("rollout-test.jsonl")
        try Data("first\n".utf8).write(to: rollout)
        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()

        wait(for: [changed], timeout: 3)
    }

    @MainActor
    func testFileEventRefreshesUsageModelImmediately() async {
        let now = Date()
        let snapshot = UsageSnapshot(
            planType: "pro",
            windows: [
                UsageWindowSnapshot(
                    id: "weekly",
                    kind: .weekly,
                    limitID: "codex",
                    limitName: nil,
                    remainingPercent: 44,
                    windowMinutes: 10_080,
                    resetsAt: now.addingTimeInterval(4 * 86_400)
                )
            ],
            credits: nil,
            source: SnapshotSource(
                sessionFile: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
                eventTimestamp: now,
                fileModificationDate: now
            )
        )
        let provider = WatcherFixedProvider(snapshot: snapshot)
        let watcher = ManualSessionDirectoryWatcher()
        let refreshed = expectation(description: "model refreshed")
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let model = UsageModel(
            provider: provider,
            historyStore: SnapshotHistoryStore(fileURL: historyURL),
            directoryWatcher: watcher,
            autoStart: false
        )
        defer { model.stopMonitoring() }
        model.onSnapshotChange = {
            refreshed.fulfill()
        }

        model.restartMonitoring()
        watcher.emitChange()

        await fulfillment(of: [refreshed], timeout: 1)
        XCTAssertEqual(model.snapshot, snapshot)
    }
}

private actor WatcherFixedProvider: UsageSnapshotProviding {
    let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        snapshot
    }
}

private final class ManualSessionDirectoryWatcher:
    SessionDirectoryWatching,
    @unchecked Sendable
{
    private var onChange: (@Sendable () -> Void)?

    func start(
        path: String,
        onChange: @escaping @Sendable () -> Void
    ) throws {
        self.onChange = onChange
    }

    func stop() {
        onChange = nil
    }

    func emitChange() {
        onChange?()
    }
}
