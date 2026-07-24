import XCTest
@testable import CodexGauge

final class SessionLogReaderTests: XCTestCase {
    func testChoosesNewestEventTimestampAcrossFilesInsteadOfNewestModifiedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let newerEvent = directory.appendingPathComponent("rollout-newer-event.jsonl")
        let newerFile = directory.appendingPathComponent("rollout-newer-file.jsonl")
        try fixture("current-weekly-only")
            .write(to: newerEvent, atomically: true, encoding: .utf8)
        try fixture("legacy-dual-window")
            .write(to: newerFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: newerEvent.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)],
            ofItemAtPath: newerFile.path
        )

        let snapshot = try await SessionLogReader().latestSnapshot(path: directory.path)

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].kind, .weekly)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 51)
        XCTAssertEqual(
            snapshot.source.sessionFile.lastPathComponent,
            "rollout-newer-event.jsonl"
        )
    }

    func testFindsMainSnapshotWhenNewestFileOnlyContainsSparkLimit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let main = directory.appendingPathComponent("rollout-main.jsonl")
        let spark = directory.appendingPathComponent("rollout-spark.jsonl")
        try fixture("current-weekly-only").write(to: main, atomically: true, encoding: .utf8)
        try fixture("spark-before-main")
            .split(separator: "\n")
            .last
            .map(String.init)?
            .write(to: spark, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: main.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: spark.path
        )

        let snapshot = try await SessionLogReader().latestSnapshot(path: directory.path)

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].kind, .weekly)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 51)
        XCTAssertEqual(snapshot.source.sessionFile.lastPathComponent, "rollout-main.jsonl")
    }

    func testReadsRateLimitNearEndOfLargeFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("rollout-large.jsonl")
        var data = Data(repeating: 0x78, count: 12 * 1_024 * 1_024)
        data.append(0x0A)
        data.append(try fixture("current-weekly-only").data(using: .utf8)!)
        try data.write(to: file)

        let snapshot = try await SessionLogReader().latestSnapshot(path: directory.path)

        XCTAssertEqual(snapshot.windows[0].kind, .weekly)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 51)
    }

    func testMissingDirectoryThrowsDirectoryMissing() async {
        do {
            _ = try await SessionLogReader().latestSnapshot(
                path: "/tmp/codex-gauge-does-not-exist"
            )
            XCTFail("Expected directoryMissing")
        } catch {
            XCTAssertEqual(error as? UsageDataError, .directoryMissing)
        }
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexGaugeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
