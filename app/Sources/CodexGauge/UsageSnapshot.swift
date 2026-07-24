import Foundation

enum UsageWindowKind: Hashable, Sendable {
    case fiveHour
    case weekly
    case custom(minutes: Int)
    case unknown

    init(minutes: Int?) {
        switch minutes {
        case 300:
            self = .fiveHour
        case 10_080:
            self = .weekly
        case let value?:
            self = .custom(minutes: value)
        case nil:
            self = .unknown
        }
    }

    var sortOrder: Int {
        switch self {
        case .fiveHour: 0
        case .weekly: 1
        case .custom: 2
        case .unknown: 3
        }
    }

    var key: String {
        switch self {
        case .fiveHour: "five-hour"
        case .weekly: "weekly"
        case let .custom(minutes): "custom-\(minutes)"
        case .unknown: "unknown"
        }
    }
}

struct UsageWindowSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let kind: UsageWindowKind
    let limitID: String
    let limitName: String?
    let remainingPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    static func clampedRemaining(fromUsedPercent used: Double) -> Double {
        max(0, min(100, 100 - used))
    }
}

struct CreditsSnapshot: Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Decimal?
}

extension CreditsSnapshot {
    var shouldDisplay: Bool {
        unlimited || hasCredits || (balance ?? 0) > 0
    }
}

struct SnapshotSource: Equatable, Sendable {
    let sessionFile: URL
    let eventTimestamp: Date
    let fileModificationDate: Date
}

struct UsageSnapshot: Equatable, Sendable {
    let planType: String?
    let windows: [UsageWindowSnapshot]
    let credits: CreditsSnapshot?
    let source: SnapshotSource
}

enum SnapshotFreshness: Equatable, Sendable {
    case fresh
    case aging
    case stale
    case expiredWindow
}

enum UsageDataError: LocalizedError, Equatable, Sendable {
    case directoryMissing
    case permissionDenied
    case noSessionFiles
    case noRateLimitEvents
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .directoryMissing: "Codex 会话目录不存在"
        case .permissionDenied: "没有读取 Codex 会话目录的权限"
        case .noSessionFiles: "尚未找到 Codex 会话文件"
        case .noRateLimitEvents: "尚未找到额度快照"
        case .unsupportedSchema: "额度数据格式暂不支持"
        }
    }
}

enum MenuMetricPreference: String, CaseIterable, Identifiable {
    case automatic
    case fiveHour
    case weekly

    var id: String { rawValue }
}
