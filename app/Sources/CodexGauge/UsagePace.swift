import Foundation

enum UsagePaceStatus: Equatable, Sendable {
    case unknown
    case balanced
    case aheadOfPace
    case useMore
    case wasteRisk
    case quotaTight
    case expired

    var attentionRank: Int {
        switch self {
        case .unknown, .expired: 0
        case .balanced: 1
        case .aheadOfPace: 2
        case .useMore: 3
        case .wasteRisk: 4
        case .quotaTight: 5
        }
    }
}

struct UsagePaceEvaluation: Equatable, Sendable {
    let status: UsagePaceStatus
    let timeRemainingPercent: Double?
    let paceGap: Double?
    let recommendedPointsPerHour: Double?
    let recommendedPointsPerDay: Double?
}

enum UsagePaceEvaluator {
    static func evaluate(
        _ window: UsageWindowSnapshot,
        now: Date
    ) -> UsagePaceEvaluation {
        guard let resetsAt = window.resetsAt,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0
        else {
            return UsagePaceEvaluation(
                status: .unknown,
                timeRemainingPercent: nil,
                paceGap: nil,
                recommendedPointsPerHour: nil,
                recommendedPointsPerDay: nil
            )
        }

        let secondsRemaining = resetsAt.timeIntervalSince(now)
        guard secondsRemaining > 0 else {
            return UsagePaceEvaluation(
                status: .expired,
                timeRemainingPercent: 0,
                paceGap: nil,
                recommendedPointsPerHour: nil,
                recommendedPointsPerDay: nil
            )
        }

        let timePercent = max(
            0,
            min(100, secondsRemaining / (Double(windowMinutes) * 60) * 100)
        )
        let gap = window.remainingPercent - timePercent

        let status: UsagePaceStatus
        let wasteTimeThreshold = windowMinutes >= 1_440
            ? 24 * 3_600.0
            : Double(windowMinutes) * 60 * 0.2
        let tightTimeThreshold = windowMinutes >= 1_440
            ? 6 * 3_600.0
            : Double(windowMinutes) * 60 * 0.2

        if window.remainingPercent <= 10 && secondsRemaining > tightTimeThreshold {
            status = .quotaTight
        } else if (secondsRemaining <= wasteTimeThreshold && window.remainingPercent >= 25)
                    || gap >= 25 {
            status = .wasteRisk
        } else if gap >= 15 {
            status = .useMore
        } else if gap <= -20 {
            status = .aheadOfPace
        } else {
            status = .balanced
        }

        let hours = secondsRemaining / 3_600
        let perHour = hours >= 0.25 ? window.remainingPercent / hours : nil
        let perDay = hours >= 24 ? window.remainingPercent / (hours / 24) : nil

        return UsagePaceEvaluation(
            status: status,
            timeRemainingPercent: timePercent,
            paceGap: gap,
            recommendedPointsPerHour: perHour,
            recommendedPointsPerDay: perDay
        )
    }

    static func freshness(
        eventTimestamp: Date,
        windows: [UsageWindowSnapshot],
        now: Date
    ) -> SnapshotFreshness {
        let resetDates = windows.compactMap(\.resetsAt)
        if !resetDates.isEmpty && resetDates.allSatisfy({ $0 <= now }) {
            return .expiredWindow
        }
        let age = max(0, now.timeIntervalSince(eventTimestamp))
        if age <= 15 * 60 { return .fresh }
        if age <= 2 * 60 * 60 { return .aging }
        return .stale
    }
}

enum UsageMenuSelector {
    static func select(
        windows: [UsageWindowSnapshot],
        preference: MenuMetricPreference,
        now: Date
    ) -> UsageWindowSnapshot? {
        switch preference {
        case .fiveHour:
            return windows.first { $0.kind == .fiveHour }
                ?? automaticSelection(from: windows, now: now)
        case .weekly:
            return windows.first { $0.kind == .weekly }
                ?? automaticSelection(from: windows, now: now)
        case .automatic:
            return automaticSelection(from: windows, now: now)
        }
    }

    private static func automaticSelection(
        from windows: [UsageWindowSnapshot],
        now: Date
    ) -> UsageWindowSnapshot? {
        windows.sorted { lhs, rhs in
            let left = UsagePaceEvaluator.evaluate(lhs, now: now).status.attentionRank
            let right = UsagePaceEvaluator.evaluate(rhs, now: now).status.attentionRank
            if left == right {
                if lhs.kind == .weekly { return true }
                if rhs.kind == .weekly { return false }
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return left > right
        }.first
    }
}
