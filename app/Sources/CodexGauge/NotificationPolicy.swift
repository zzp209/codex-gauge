import Foundation

enum QuotaNotificationKind: String, Equatable, Sendable {
    case quotaTight
    case waste48Hours
    case waste24Hours
    case waste6Hours
    case dailyPace
}

struct QuotaNotification: Equatable, Sendable {
    let kind: QuotaNotificationKind
    let title: String
    let body: String
    let dedupeKey: String
}

struct ReminderPreferences: Equatable, Sendable {
    let quotaTight: Bool
    let wasteRisk: Bool
    let dailyPace: Bool
    let dailyHour: Int
}

enum NotificationPolicy {
    static func notifications(
        window: UsageWindowSnapshot,
        evaluation: UsagePaceEvaluation,
        freshness: SnapshotFreshness,
        now: Date,
        sentKeys: Set<String>,
        preferences: ReminderPreferences
    ) -> [QuotaNotification] {
        let eventNotifications = pendingNotifications(
            window: window,
            evaluation: evaluation,
            freshness: freshness,
            now: now,
            sentKeys: sentKeys
        ).filter { notification in
            switch notification.kind {
            case .quotaTight:
                preferences.quotaTight
            case .waste48Hours, .waste24Hours, .waste6Hours:
                preferences.wasteRisk
            case .dailyPace:
                false
            }
        }
        if !eventNotifications.isEmpty {
            return eventNotifications
        }
        guard preferences.dailyPace,
              isDailyReminderTime(
                now: now,
                hour: preferences.dailyHour
              ),
              let daily = dailyNotification(
                window: window,
                evaluation: evaluation,
                freshness: freshness,
                now: now,
                sentKeys: sentKeys
              )
        else {
            return []
        }
        return [daily]
    }

    static func isDailyReminderTime(
        now: Date,
        hour: Int,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.component(.hour, from: now) >= min(23, max(0, hour))
    }

    static func pendingNotifications(
        window: UsageWindowSnapshot,
        evaluation: UsagePaceEvaluation,
        freshness: SnapshotFreshness,
        now: Date,
        sentKeys: Set<String>
    ) -> [QuotaNotification] {
        guard freshness == .fresh,
              let resetsAt = window.resetsAt,
              resetsAt > now
        else { return [] }

        let seconds = resetsAt.timeIntervalSince(now)
        let kind: QuotaNotificationKind?
        if evaluation.status == .quotaTight {
            kind = .quotaTight
        } else if evaluation.status != .wasteRisk {
            kind = nil
        } else if seconds <= finalReminderThreshold(for: window)
                    && window.remainingPercent >= 10 {
            kind = .waste6Hours
        } else if seconds <= 24 * 3_600 && window.remainingPercent >= 25 {
            kind = .waste24Hours
        } else if seconds <= 48 * 3_600 && window.remainingPercent >= 35 {
            kind = .waste48Hours
        } else {
            kind = nil
        }

        guard let kind else { return [] }
        let key = dedupeKey(
            window: window,
            resetsAt: resetsAt,
            kind: kind
        )
        guard !sentKeys.contains(key) else { return [] }

        return [
            QuotaNotification(
                kind: kind,
                title: title(for: kind),
                body: body(for: kind, window: window, seconds: seconds),
                dedupeKey: key
            )
        ]
    }

    private static func finalReminderThreshold(
        for window: UsageWindowSnapshot
    ) -> TimeInterval {
        guard let minutes = window.windowMinutes, minutes < 1_440 else {
            return 6 * 3_600
        }
        return min(6 * 3_600, Double(minutes) * 60 * 0.2)
    }

    static func dailyNotification(
        window: UsageWindowSnapshot,
        evaluation: UsagePaceEvaluation,
        freshness: SnapshotFreshness,
        now: Date,
        sentKeys: Set<String>
    ) -> QuotaNotification? {
        guard freshness == .fresh,
              window.kind == .weekly,
              evaluation.status == .useMore || evaluation.status == .wasteRisk,
              let resetsAt = window.resetsAt,
              resetsAt > now
        else { return nil }
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let key = "\(window.kind.key)|\(Int(resetsAt.timeIntervalSince1970))|daily|\(Int(day))"
        guard !sentKeys.contains(key) else { return nil }
        return QuotaNotification(
            kind: .dailyPace,
            title: "Codex 额度建议多用",
            body: "\(Int(window.remainingPercent.rounded()))% 剩余，\(DisplayFormatter.countdown(seconds: resetsAt.timeIntervalSince(now), chinese: true))后重置",
            dedupeKey: key
        )
    }

    private static func dedupeKey(
        window: UsageWindowSnapshot,
        resetsAt: Date,
        kind: QuotaNotificationKind
    ) -> String {
        "\(window.kind.key)|\(Int(resetsAt.timeIntervalSince1970))|\(kind.rawValue)"
    }

    private static func title(for kind: QuotaNotificationKind) -> String {
        switch kind {
        case .quotaTight: "Codex 额度紧张"
        case .waste48Hours: "Codex 额度可能浪费"
        case .waste24Hours: "Codex 额度即将重置"
        case .waste6Hours: "Codex 额度即将过期"
        case .dailyPace: "Codex 额度建议多用"
        }
    }

    private static func body(
        for kind: QuotaNotificationKind,
        window: UsageWindowSnapshot,
        seconds: TimeInterval
    ) -> String {
        let remaining = Int(window.remainingPercent.rounded())
        let countdown = DisplayFormatter.countdown(seconds: seconds, chinese: true)
        switch kind {
        case .quotaTight:
            return "仅剩 \(remaining)%，距离重置还有 \(countdown)"
        case .waste48Hours, .waste24Hours, .waste6Hours:
            return "仍剩 \(remaining)%，\(countdown)后重置"
        case .dailyPace:
            return "仍剩 \(remaining)%，建议安排合适的 Codex 任务"
        }
    }
}

enum NotificationLedger {
    private static let key = "quotaNotificationLedgerV1"

    static func allKeys(defaults: UserDefaults = .standard) -> Set<String> {
        Set(load(defaults: defaults).keys)
    }

    static func insert(
        _ value: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        var values = load(defaults: defaults)
        values[value] = now.timeIntervalSince1970
        defaults.set(values, forKey: key)
    }

    static func prune(
        before cutoff: Date,
        defaults: UserDefaults = .standard
    ) {
        let values = load(defaults: defaults).filter {
            $0.value >= cutoff.timeIntervalSince1970
        }
        defaults.set(values, forKey: key)
    }

    private static func load(defaults: UserDefaults) -> [String: TimeInterval] {
        defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    }
}
