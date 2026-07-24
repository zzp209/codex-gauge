import Foundation
import SQLite3
import XCTest
@testable import CodexGauge

final class DailyActivityReaderTests: XCTestCase {
    func testCountsOnlyVisibleRootThreadsAndUserMessagesFromToday() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.cleanup() }

        let calendar = fixture.calendar
        let now = fixture.now
        let start = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let todayMorning = calendar.date(byAdding: .hour, value: 8, to: start)!
        let todayNoon = calendar.date(byAdding: .hour, value: 12, to: start)!

        let firstRoot = try fixture.writeRollout(
            name: "first-root",
            lines: [
                fixture.message(at: yesterday, role: "user"),
                fixture.message(at: todayMorning, role: "user"),
                fixture.message(at: todayNoon, role: "assistant"),
                fixture.message(at: todayNoon, role: "user")
            ]
        )
        let archivedRoot = try fixture.writeRollout(
            name: "archived-root",
            lines: [
                fixture.message(at: todayMorning, role: "user")
            ]
        )
        let subagent = try fixture.writeRollout(
            name: "subagent",
            lines: [
                fixture.message(at: todayMorning, role: "user")
            ]
        )
        let hidden = try fixture.writeRollout(
            name: "hidden",
            lines: [
                fixture.message(at: todayMorning, role: "user")
            ]
        )

        try fixture.insertThread(
            id: "root-new",
            rollout: firstRoot,
            createdAt: todayMorning,
            updatedAt: todayNoon,
            preview: "Visible root"
        )
        try fixture.insertThread(
            id: "root-archived",
            rollout: archivedRoot,
            createdAt: yesterday,
            updatedAt: todayNoon,
            preview: "Archived root",
            archivedAt: todayMorning
        )
        try fixture.insertThread(
            id: "child",
            rollout: subagent,
            createdAt: todayMorning,
            updatedAt: todayNoon,
            preview: "Subagent"
        )
        try fixture.insertSpawnEdge(parent: "root-new", child: "child")
        try fixture.insertThread(
            id: "hidden",
            rollout: hidden,
            createdAt: todayMorning,
            updatedAt: todayNoon,
            preview: ""
        )

        let reader = DailyActivityReader(
            stateDatabaseURL: fixture.databaseURL,
            calendar: calendar
        )

        let snapshot = try await reader.latest(now: now)

        XCTAssertEqual(snapshot.newThreads, 1)
        XCTAssertEqual(snapshot.sentMessages, 3)
        XCTAssertEqual(snapshot.archivedThreads, 1)
    }

    func testDoesNotCountStructuralTextInsideAssistantMessageBody() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.cleanup() }

        let start = fixture.calendar.startOfDay(for: fixture.now)
        let todayMorning = fixture.calendar.date(
            byAdding: .hour,
            value: 8,
            to: start
        )!
        let rollout = try fixture.writeRollout(
            name: "assistant-body",
            lines: [
                """
                {"timestamp":"\(fixture.timestamp(todayMorning))","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"payload: {\\\"type\\\":\\\"message\\\",\\\"role\\\":\\\"user\\\"}"}]}}
                """
            ]
        )
        try fixture.insertThread(
            id: "root",
            rollout: rollout,
            createdAt: todayMorning,
            updatedAt: todayMorning,
            preview: "Visible root"
        )
        let reader = DailyActivityReader(
            stateDatabaseURL: fixture.databaseURL,
            calendar: fixture.calendar
        )

        let snapshot = try await reader.latest(now: fixture.now)

        XCTAssertEqual(snapshot.sentMessages, 0)
    }

    func testCountsFractionalTimestampAtLocalDayStartOnly() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.cleanup() }

        let start = fixture.calendar.startOfDay(for: fixture.now)
        let rollout = try fixture.writeRollout(
            name: "day-boundary",
            lines: [
                """
                {"timestamp":"2026-07-23T16:00:00.500Z","type":"response_item","payload":{"type":"message","role":"user","content":[]}}
                """
            ]
        )
        try fixture.insertThread(
            id: "root",
            rollout: rollout,
            createdAt: start,
            updatedAt: fixture.now,
            preview: "Visible root"
        )
        let reader = DailyActivityReader(
            stateDatabaseURL: fixture.databaseURL,
            calendar: fixture.calendar
        )

        let snapshot = try await reader.latest(now: fixture.now)

        XCTAssertEqual(snapshot.sentMessages, 1)
    }

    func testAppendedMessagesAreCountedWithoutDoubleCountingCache() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.cleanup() }

        let start = fixture.calendar.startOfDay(for: fixture.now)
        let morning = fixture.calendar.date(
            byAdding: .hour,
            value: 8,
            to: start
        )!
        let rollout = try fixture.writeRollout(
            name: "incremental",
            lines: [fixture.message(at: morning, role: "user")]
        )
        try fixture.insertThread(
            id: "root",
            rollout: rollout,
            createdAt: morning,
            updatedAt: fixture.now,
            preview: "Visible root"
        )
        let reader = DailyActivityReader(
            stateDatabaseURL: fixture.databaseURL,
            calendar: fixture.calendar
        )

        let first = try await reader.latest(now: fixture.now)
        try fixture.append(
            fixture.message(at: fixture.now, role: "user"),
            to: rollout
        )
        let second = try await reader.latest(now: fixture.now)

        XCTAssertEqual(first.sentMessages, 1)
        XCTAssertEqual(second.sentMessages, 2)
    }

    func testLongMultibyteMessageBodyDoesNotInvalidateMetadataPrefix() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.cleanup() }

        let start = fixture.calendar.startOfDay(for: fixture.now)
        let morning = fixture.calendar.date(
            byAdding: .hour,
            value: 8,
            to: start
        )!
        let longBody = String(repeating: "中", count: 200)
        let rollout = try fixture.writeRollout(
            name: "multibyte-body",
            lines: [
                """
                {"timestamp":"\(fixture.timestamp(morning))","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\(longBody)"}]}}
                """
            ]
        )
        try fixture.insertThread(
            id: "root",
            rollout: rollout,
            createdAt: morning,
            updatedAt: fixture.now,
            preview: "Visible root"
        )
        let reader = DailyActivityReader(
            stateDatabaseURL: fixture.databaseURL,
            calendar: fixture.calendar
        )

        let snapshot = try await reader.latest(now: fixture.now)

        XCTAssertEqual(snapshot.sentMessages, 1)
    }
}

private final class ActivityFixture {
    let directoryURL: URL
    let databaseURL: URL
    let calendar: Calendar
    let now: Date
    private var database: OpaquePointer?

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        databaseURL = directoryURL.appendingPathComponent("state_5.sqlite")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        self.calendar = calendar
        now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 24,
            hour: 12
        )))

        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw FixtureError.sqlite("open")
        }
        try execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                preview TEXT NOT NULL DEFAULT '',
                archived INTEGER NOT NULL DEFAULT 0,
                archived_at INTEGER
            );
            CREATE TABLE thread_spawn_edges (
                parent_thread_id TEXT NOT NULL,
                child_thread_id TEXT NOT NULL PRIMARY KEY,
                status TEXT NOT NULL
            );
            """
        )
    }

    deinit {
        sqlite3_close(database)
    }

    func cleanup() {
        sqlite3_close(database)
        database = nil
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func writeRollout(name: String, lines: [String]) throws -> URL {
        let url = directoryURL.appendingPathComponent("\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        return url
    }

    func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    func message(at date: Date, role: String) -> String {
        """
        {"timestamp":"\(timestamp(date))","type":"response_item","payload":{"type":"message","role":"\(role)","content":[]}}
        """
    }

    func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    func insertThread(
        id: String,
        rollout: URL,
        createdAt: Date,
        updatedAt: Date,
        preview: String,
        archivedAt: Date? = nil
    ) throws {
        let archivedValue = archivedAt == nil ? 0 : 1
        let archivedTimestamp = archivedAt.map {
            String(Int($0.timeIntervalSince1970))
        } ?? "NULL"
        try execute(
            """
            INSERT INTO threads (
                id, rollout_path, created_at, updated_at, preview,
                archived, archived_at
            ) VALUES (
                '\(id)', '\(rollout.path)',
                \(Int(createdAt.timeIntervalSince1970)),
                \(Int(updatedAt.timeIntervalSince1970)),
                '\(preview)', \(archivedValue), \(archivedTimestamp)
            );
            """
        )
    }

    func insertSpawnEdge(parent: String, child: String) throws {
        try execute(
            """
            INSERT INTO thread_spawn_edges (
                parent_thread_id, child_thread_id, status
            ) VALUES ('\(parent)', '\(child)', 'active');
            """
        )
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw FixtureError.sqlite(message)
        }
    }
}

private enum FixtureError: Error {
    case sqlite(String)
}
