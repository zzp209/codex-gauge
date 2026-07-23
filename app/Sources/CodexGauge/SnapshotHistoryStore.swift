import Foundation

struct HistoryPoint: Codable, Equatable, Sendable {
    let capturedAt: Date
    let kindKey: String
    let remainingPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
}

actor SnapshotHistoryStore {
    static let retention: TimeInterval = 90 * 86_400
    static let minimumInterval: TimeInterval = 30 * 60

    private let fileURL: URL

    init(fileURL: URL = SnapshotHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func append(
        _ snapshot: UsageSnapshot,
        capturedAt: Date = Date()
    ) throws {
        let cutoff = capturedAt.addingTimeInterval(-Self.retention)
        let existing = try load()
        var points = existing.filter { $0.capturedAt >= cutoff }
        var changed = false

        for window in snapshot.windows {
            let point = HistoryPoint(
                capturedAt: capturedAt,
                kindKey: window.kind.key,
                remainingPercent: window.remainingPercent,
                resetsAt: window.resetsAt,
                windowMinutes: window.windowMinutes
            )
            if shouldAppend(point, to: points) {
                points.append(point)
                changed = true
            }
        }

        points.sort { $0.capturedAt < $1.capturedAt }
        if changed || points != existing {
            try save(points)
        }
    }

    func allPoints() throws -> [HistoryPoint] {
        try load().sorted { $0.capturedAt < $1.capturedAt }
    }

    func change(
        in kind: UsageWindowKind,
        last interval: TimeInterval,
        now: Date = Date()
    ) throws -> Double? {
        let cutoff = now.addingTimeInterval(-interval)
        let candidates = try load()
            .filter {
                $0.kindKey == kind.key
                    && $0.capturedAt >= cutoff
                    && $0.capturedAt <= now
            }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let latest = candidates.last else { return nil }
        let sameCycle = candidates.filter { $0.resetsAt == latest.resetsAt }
        guard let first = sameCycle.first, sameCycle.count >= 2 else {
            return nil
        }
        return max(0, first.remainingPercent - latest.remainingPercent)
    }

    private func shouldAppend(
        _ point: HistoryPoint,
        to points: [HistoryPoint]
    ) -> Bool {
        guard let previous = points.last(where: {
            $0.kindKey == point.kindKey
        }) else {
            return true
        }
        if previous.resetsAt != point.resetsAt {
            return true
        }
        let elapsed = point.capturedAt.timeIntervalSince(previous.capturedAt)
        let change = abs(point.remainingPercent - previous.remainingPercent)
        return elapsed >= Self.minimumInterval || change >= 1
    }

    private func load() throws -> [HistoryPoint] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([HistoryPoint].self, from: data)
    }

    private func save(_ points: [HistoryPoint]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(points)
        try data.write(to: fileURL, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("CodexGauge", isDirectory: true)
            .appendingPathComponent("history-v1.json")
    }
}
