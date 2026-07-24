import Foundation
import SQLite3

struct DailyActivitySnapshot: Equatable, Sendable {
    let newThreads: Int
    let sentMessages: Int
    let archivedThreads: Int
}

protocol DailyActivityProviding: Sendable {
    func latest(now: Date) async throws -> DailyActivitySnapshot
}

enum DailyActivityError: Error {
    case databaseUnavailable
    case databaseQueryFailed
}

actor DailyActivityReader: DailyActivityProviding {
    private static let contentMarker = Data("\"content\":".utf8)

    private struct RolloutCandidate {
        let url: URL
        let createdAt: Int64
        let updatedAt: Int64
        let archivedAt: Int64?
    }

    private struct FileCache {
        let dayStart: Date
        let processedOffset: UInt64
        let messageCount: Int
    }

    private let stateDatabaseURL: URL
    private let calendar: Calendar
    private var fileCaches: [URL: FileCache] = [:]

    init(
        stateDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        calendar: Calendar = .current
    ) {
        self.stateDatabaseURL = stateDatabaseURL
        self.calendar = calendar
    }

    func latest(now: Date = Date()) async throws -> DailyActivitySnapshot {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            throw DailyActivityError.databaseQueryFailed
        }
        let startSeconds = Int64(dayStart.timeIntervalSince1970)
        let endSeconds = Int64(dayEnd.timeIntervalSince1970)
        let candidates = try queryCandidates(
            startSeconds: startSeconds,
            endSeconds: endSeconds
        )

        var newThreads = 0
        var archivedThreads = 0
        var sentMessages = 0
        let startTimestamp = Self.comparableTimestamp(
            Self.timestamp(dayStart)
        )!
        let endTimestamp = Self.comparableTimestamp(
            Self.timestamp(dayEnd)
        )!
        var activeURLs = Set<URL>()

        for candidate in candidates {
            if Self.contains(
                candidate.createdAt,
                start: startSeconds,
                end: endSeconds
            ) {
                newThreads += 1
            }
            if let archivedAt = candidate.archivedAt,
               Self.contains(
                   archivedAt,
                   start: startSeconds,
                   end: endSeconds
               ) {
                archivedThreads += 1
            }
            guard Self.contains(
                candidate.updatedAt,
                start: startSeconds,
                end: endSeconds
            ) else {
                continue
            }
            activeURLs.insert(candidate.url)
            sentMessages += try countMessages(
                in: candidate.url,
                dayStart: dayStart,
                startTimestamp: startTimestamp,
                endTimestamp: endTimestamp
            )
        }

        fileCaches = fileCaches.filter { activeURLs.contains($0.key) }
        return DailyActivitySnapshot(
            newThreads: newThreads,
            sentMessages: sentMessages,
            archivedThreads: archivedThreads
        )
    }

    private func queryCandidates(
        startSeconds: Int64,
        endSeconds: Int64
    ) throws -> [RolloutCandidate] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(
            stateDatabaseURL.path,
            &database,
            flags,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw DailyActivityError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let sql = """
        SELECT
            t.rollout_path,
            t.created_at,
            t.updated_at,
            t.archived_at
        FROM threads AS t
        WHERE t.preview <> ''
          AND NOT EXISTS (
              SELECT 1
              FROM thread_spawn_edges AS e
              WHERE e.child_thread_id = t.id
          )
          AND (
              (t.created_at >= ?1 AND t.created_at < ?2)
              OR (t.updated_at >= ?1 AND t.updated_at < ?2)
              OR (t.archived_at >= ?1 AND t.archived_at < ?2)
          );
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw DailyActivityError.databaseQueryFailed
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, startSeconds)
        sqlite3_bind_int64(statement, 2, endSeconds)

        var candidates: [RolloutCandidate] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let pathValue = sqlite3_column_text(statement, 0) else {
                    continue
                }
                let path = String(cString: pathValue)
                let archivedAt: Int64? = sqlite3_column_type(
                    statement,
                    3
                ) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 3)
                candidates.append(RolloutCandidate(
                    url: URL(fileURLWithPath: path),
                    createdAt: sqlite3_column_int64(statement, 1),
                    updatedAt: sqlite3_column_int64(statement, 2),
                    archivedAt: archivedAt
                ))
            case SQLITE_DONE:
                return candidates
            default:
                throw DailyActivityError.databaseQueryFailed
            }
        }
    }

    private func countMessages(
        in url: URL,
        dayStart: Date,
        startTimestamp: String,
        endTimestamp: String
    ) throws -> Int {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            fileCaches[url] = nil
            return 0
        }
        defer { try? fileHandle.close() }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        let cached = fileCaches[url].flatMap {
            $0.dayStart == dayStart && $0.processedOffset <= fileSize
                ? $0
                : nil
        }
        let initialOffset = cached?.processedOffset ?? 0
        var count = cached?.messageCount ?? 0
        if initialOffset == fileSize {
            return count
        }
        try fileHandle.seek(toOffset: initialOffset)

        var position = initialOffset
        var lastCompleteOffset = initialOffset
        var header = Data()
        header.reserveCapacity(256)
        var capturingHeader = true

        while let chunk = try fileHandle.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            for byte in chunk {
                position += 1
                if byte == 0x0A {
                    if Self.isUserMessage(
                        header,
                        startTimestamp: startTimestamp,
                        endTimestamp: endTimestamp
                    ) {
                        count += 1
                    }
                    header.removeAll(keepingCapacity: true)
                    capturingHeader = true
                    lastCompleteOffset = position
                } else if capturingHeader && header.count < 256 {
                    header.append(byte)
                    if header.count >= Self.contentMarker.count,
                       header.suffix(Self.contentMarker.count)
                           .elementsEqual(Self.contentMarker) {
                        capturingHeader = false
                    }
                }
            }
        }

        fileCaches[url] = FileCache(
            dayStart: dayStart,
            processedOffset: lastCompleteOffset,
            messageCount: count
        )
        return count
    }

    private static func isUserMessage(
        _ headerData: Data,
        startTimestamp: String,
        endTimestamp: String
    ) -> Bool {
        guard let prefix = String(data: headerData, encoding: .utf8) else {
            return false
        }
        let metadata = prefix.components(separatedBy: "\"content\":").first
            ?? prefix
        guard metadata.contains("\"type\":\"response_item\""),
              metadata.contains("\"payload\":{\"type\":\"message\""),
              metadata.contains("\"role\":\"user\""),
              let timestamp = value(
                  after: "\"timestamp\":\"",
                  in: metadata
              )
        else {
            return false
        }
        guard let comparable = comparableTimestamp(timestamp) else {
            return false
        }
        return comparable >= startTimestamp && comparable < endTimestamp
    }

    private static func value(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let suffix = text[markerRange.upperBound...]
        guard let end = suffix.firstIndex(of: "\"") else { return nil }
        return String(suffix[..<end])
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func comparableTimestamp(_ value: String) -> String? {
        guard value.hasSuffix("Z") else { return nil }
        let body = value.dropLast()
        let parts = body.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.first?.count == 19 else { return nil }
        let rawFraction = parts.count == 2 ? String(parts[1]) : ""
        guard rawFraction.allSatisfy(\.isNumber) else { return nil }
        let fraction = String(rawFraction.prefix(9))
            .padding(
                toLength: 9,
                withPad: "0",
                startingAt: 0
            )
        return "\(parts[0]).\(fraction)"
    }

    private static func contains(
        _ value: Int64,
        start: Int64,
        end: Int64
    ) -> Bool {
        value >= start && value < end
    }
}
