import Foundation

enum DisplayFormatter {
    static func countdown(
        seconds: TimeInterval,
        chinese: Bool = false
    ) -> String {
        let value = max(0, Int(seconds))
        let days = value / 86_400
        let hours = (value % 86_400) / 3_600
        let minutes = (value % 3_600) / 60

        if chinese {
            if days > 0 { return "\(days)天\(hours)小时" }
            if hours > 0 { return "\(hours)小时\(minutes)分钟" }
            return "\(minutes)分钟"
        }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func shortLabel(
        for kind: UsageWindowKind,
        chinese: Bool
    ) -> String {
        switch kind {
        case .fiveHour:
            return chinese ? "5时" : "5h"
        case .weekly:
            return chinese ? "周" : "Week"
        case let .custom(minutes):
            if minutes.isMultiple(of: 60) {
                return chinese ? "\(minutes / 60)时" : "\(minutes / 60)h"
            }
            return chinese ? "\(minutes)分" : "\(minutes)m"
        case .unknown:
            return chinese ? "额度" : "Quota"
        }
    }

    static func longLabel(
        for kind: UsageWindowKind,
        chinese: Bool
    ) -> String {
        switch kind {
        case .fiveHour:
            return chinese ? "5 小时窗口" : "5-hour window"
        case .weekly:
            return chinese ? "每周窗口" : "Weekly window"
        case let .custom(minutes):
            return chinese ? "\(minutes) 分钟窗口" : "\(minutes)-minute window"
        case .unknown:
            return chinese ? "额度窗口" : "Quota window"
        }
    }
}
