import CoreServices
import Foundation

protocol SessionDirectoryWatching: AnyObject {
    func start(
        path: String,
        onChange: @escaping @Sendable () -> Void
    ) throws
    func stop()
}

enum SessionDirectoryWatcherError: Error {
    case directoryUnavailable
    case streamCreationFailed
    case streamStartFailed
}

final class SessionDirectoryWatcher: SessionDirectoryWatching {
    private let latency: TimeInterval
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.zzp209.codex-gauge.session-watcher",
        qos: .utility
    )
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private var onChange: (@Sendable () -> Void)?

    init(
        latency: TimeInterval = 0.5,
        debounceInterval: TimeInterval = 0.5
    ) {
        self.latency = latency
        self.debounceInterval = debounceInterval
    }

    func start(
        path: String,
        onChange: @escaping @Sendable () -> Void
    ) throws {
        stop()
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: expanded,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SessionDirectoryWatcherError.directoryUnavailable
        }

        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<SessionDirectoryWatcher>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                watcher.scheduleChange()
            },
            &context,
            [expanded] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            self.onChange = nil
            throw SessionDirectoryWatcherError.streamCreationFailed
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stop()
            throw SessionDirectoryWatcherError.streamStartFailed
        }
    }

    func stop() {
        stateLock.lock()
        pendingWork?.cancel()
        pendingWork = nil
        onChange = nil
        stateLock.unlock()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func scheduleChange() {
        stateLock.lock()
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.deliverChange()
        }
        pendingWork = work
        stateLock.unlock()
        queue.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }

    private func deliverChange() {
        stateLock.lock()
        let callback = onChange
        pendingWork = nil
        stateLock.unlock()
        callback?()
    }
}
