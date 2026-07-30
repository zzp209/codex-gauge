import Foundation

struct QuotaRefreshPresentation: Equatable {
    let headerText: String
    let paceTitle: String?
    let paceDetail: String?
    let showsSuccessfulCheck: Bool
    let usesMutedQuotaStyle: Bool

    static func make(
        freshness: SnapshotFreshness?,
        eventTimestamp: Date?,
        lastSuccessfulCheckAt: Date?,
        now: Date,
        refreshInterval: TimeInterval,
        t: Strings
    ) -> QuotaRefreshPresentation {
        guard let freshness, let eventTimestamp else {
            return QuotaRefreshPresentation(
                headerText: "",
                paceTitle: nil,
                paceDetail: nil,
                showsSuccessfulCheck: false,
                usesMutedQuotaStyle: false
            )
        }

        let eventAge = max(0, now.timeIntervalSince(eventTimestamp))
        let ageText = DisplayFormatter.countdown(
            seconds: eventAge,
            chinese: t.zh
        )
        let recentCheckThreshold = max(
            5 * 60,
            refreshInterval * 1.5
        )
        let hasRecentSuccessfulCheck = lastSuccessfulCheckAt.map {
            now.timeIntervalSince($0) <= recentCheckThreshold
        } ?? false

        switch freshness {
        case .fresh:
            return QuotaRefreshPresentation(
                headerText: eventAge < 60
                    ? t("Just now", "刚刚")
                    : t("\(ageText) ago", "\(ageText)前"),
                paceTitle: nil,
                paceDetail: nil,
                showsSuccessfulCheck: false,
                usesMutedQuotaStyle: false
            )
        case .aging:
            return QuotaRefreshPresentation(
                headerText: t(
                    "May have changed · \(ageText)",
                    "可能变化 · \(ageText)"
                ),
                paceTitle: nil,
                paceDetail: nil,
                showsSuccessfulCheck: false,
                usesMutedQuotaStyle: false
            )
        case .stale, .expiredWindow:
            let headerText = hasRecentSuccessfulCheck
                ? t("Refreshed · awaiting quota", "已刷新 · 待主额度")
                : t(
                    "Main quota stale · \(ageText)",
                    "主额度已过时 · \(ageText)"
                )
            let detailSuffix = hasRecentSuccessfulCheck
                ? t("auto-refresh is working", "自动刷新正常")
                : t("awaiting local refresh", "等待自动刷新")
            return QuotaRefreshPresentation(
                headerText: headerText,
                paceTitle: t(
                    "Waiting for a new main quota snapshot",
                    "等待主额度新快照"
                ),
                paceDetail: t(
                    "Last main quota \(ageText) ago · \(detailSuffix)",
                    "上次主额度 \(ageText)前 · \(detailSuffix)"
                ),
                showsSuccessfulCheck: hasRecentSuccessfulCheck,
                usesMutedQuotaStyle: true
            )
        }
    }
}
