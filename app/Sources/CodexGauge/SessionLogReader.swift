import Foundation

protocol UsageSnapshotProviding: Sendable {
    func latestSnapshot(path: String) async throws -> UsageSnapshot
}

actor SessionLogReader: UsageSnapshotProviding {
    private struct Candidate {
        let url: URL
        let modificationDate: Date
        let fileSize: UInt64
    }

    private struct CachedEvent {
        let fileSize: UInt64
        let event: RateLimitEvent?
    }

    private let fileManager: FileManager
    private let chunkSize = 1_048_576
    private let maximumCarriedLineSize = 1_048_576
    private var cache: [URL: CachedEvent] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw UsageDataError.directoryMissing
        }
        guard fileManager.isReadableFile(atPath: expanded) else {
            throw UsageDataError.permissionDenied
        }

        let directory = URL(fileURLWithPath: expanded, isDirectory: true)
        let candidates = try newestSessionFiles(in: directory)
        guard !candidates.isEmpty else {
            throw UsageDataError.noSessionFiles
        }

        for candidate in candidates {
            if let event = try latestMainEvent(in: candidate) {
                return UsageSnapshot(
                    planType: event.planType,
                    windows: event.windows,
                    credits: event.credits,
                    source: SnapshotSource(
                        sessionFile: candidate.url,
                        eventTimestamp: event.timestamp,
                        fileModificationDate: candidate.modificationDate
                    )
                )
            }
        }
        throw UsageDataError.noRateLimitEvents
    }

    private func newestSessionFiles(in directory: URL) throws -> [Candidate] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw UsageDataError.permissionDenied
        }

        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            candidates.append(
                Candidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    fileSize: UInt64(values.fileSize ?? 0)
                )
            )
        }
        return candidates.sorted { $0.modificationDate > $1.modificationDate }
    }

    private func latestMainEvent(in candidate: Candidate) throws -> RateLimitEvent? {
        if let cached = cache[candidate.url], cached.fileSize == candidate.fileSize {
            return cached.event
        }

        let handle = try FileHandle(forReadingFrom: candidate.url)
        defer { try? handle.close() }

        var position = candidate.fileSize
        var carriedPrefix = Data()

        while position > 0 {
            let start = position > UInt64(chunkSize)
                ? position - UInt64(chunkSize)
                : 0
            try handle.seek(toOffset: start)
            var block = try handle.read(upToCount: Int(position - start)) ?? Data()
            block.append(carriedPrefix)

            let parseData: Data
            if start == 0 {
                parseData = block
                carriedPrefix = Data()
            } else if let newline = block.firstIndex(of: 0x0A) {
                let prefix = block[..<newline]
                carriedPrefix = prefix.count <= maximumCarriedLineSize
                    ? Data(prefix)
                    : Data()
                parseData = Data(block[block.index(after: newline)...])
            } else {
                carriedPrefix = block.count <= maximumCarriedLineSize
                    ? block
                    : Data()
                parseData = Data()
            }

            if let text = String(data: parseData, encoding: .utf8),
               let event = RateLimitParser.latestMainEvent(in: text) {
                cache[candidate.url] = CachedEvent(
                    fileSize: candidate.fileSize,
                    event: event
                )
                return event
            }
            position = start
        }

        cache[candidate.url] = CachedEvent(
            fileSize: candidate.fileSize,
            event: nil
        )
        return nil
    }
}
