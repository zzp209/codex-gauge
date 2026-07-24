import AppKit
import SwiftUI

struct PopoverView: View {
    var model: UsageModel
    var openSettingsAction: (() -> Void)? = nil
    var ringTrimScale: Double = 1

    @AppStorage(LanguageKey) private var lang = "zh"
    @Environment(\.openSettings) private var openSettings

    private var t: Strings { Strings(lang) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header(now: context.date)
                content(now: context.date)
                Divider().overlay(Theme.border)
                accountFooter
            }
            .frame(width: 340)
            .background(Theme.panel)
        }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 8) {
            Text("Codex")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.fg)
            if let plan = model.snapshot?.planType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.track, in: Capsule())
            }
            Spacer()
            Label(
                freshnessText(now: now),
                systemImage: "circle.fill"
            )
            .labelStyle(CompactFreshnessLabelStyle())
            .font(.system(size: 10))
            .foregroundStyle(freshnessColor(now: now))

            Button { model.refresh() } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.fg3)
            .help(t("Refresh local snapshot", "刷新本地快照"))
            .disabled(model.isRefreshing)

            Button {
                if let openSettingsAction {
                    openSettingsAction()
                } else {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.fg3)
            .help(t("Settings", "设置"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = model.snapshot {
            VStack(spacing: 9) {
                if let focus = UsageMenuSelector.select(
                    windows: snapshot.windows,
                    preference: .automatic,
                    now: now
                ) {
                    PaceSummaryView(
                        window: focus,
                        usedPoints: model.recentUsageChange(for: focus.kind),
                        now: now,
                        t: t
                    )
                }

                ForEach(snapshot.windows) { window in
                    UsageWindowCard(
                        window: window,
                        now: now,
                        t: t,
                        trimScale: ringTrimScale
                    )
                }

                if let credits = snapshot.credits, credits.shouldDisplay {
                    creditsRow(credits)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(t("No trusted quota snapshot", "暂无可信额度快照"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text(model.lastError?.localizedDescription
                    ?? t("Run Codex once, then refresh.", "运行一次 Codex 后再刷新。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.fg2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func creditsRow(_ credits: CreditsSnapshot) -> some View {
        HStack {
            Label(t("Paid credits", "付费额度"), systemImage: "creditcard")
                .foregroundStyle(Theme.fg2)
            Spacer()
            if credits.unlimited {
                Text(t("Unlimited", "无限"))
            } else if let balance = credits.balance {
                Text(NSDecimalNumber(decimal: balance).stringValue)
            } else {
                Text("—")
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Theme.fg)
        .padding(9)
        .background(Theme.panelSoft, in: RoundedRectangle(cornerRadius: 9))
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            Button {
                UsageDestinationLauncher.openPreferred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                    Text(t(
                        UsageDestinationLauncher.isCockpitToolsInstalled
                            ? "View reset cards and expiry in Cockpit Tools"
                            : "View reset cards and expiry on the usage page",
                        UsageDestinationLauncher.isCockpitToolsInstalled
                            ? "在 Cockpit Tools 查看重置卡和到期时间"
                            : "在官方用量页查看重置卡和到期时间"
                    ))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(Theme.fg2)

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.fg3)
            .help(t("Quit", "退出"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func freshnessText(now: Date) -> String {
        guard let snapshot = model.snapshot else { return "" }
        let seconds = max(
            0,
            now.timeIntervalSince(snapshot.source.eventTimestamp)
        )
        if seconds < 60, model.freshness(now: now) == .fresh {
            return t("Just now", "刚刚")
        }
        let age = DisplayFormatter.countdown(seconds: seconds, chinese: t.zh)
        switch model.freshness(now: now) {
        case .fresh:
            return t("\(age) ago", "\(age)前")
        case .aging:
            return t("May have changed · \(age)", "可能变化 · \(age)")
        case .stale:
            return t("Stale · \(age)", "已过时 · \(age)")
        case .expiredWindow:
            return t("Waiting for update", "等待新快照")
        case nil:
            return ""
        }
    }

    private func freshnessColor(now: Date) -> Color {
        switch model.freshness(now: now) {
        case .fresh: Theme.good
        case .aging: Theme.caution
        case .stale, .expiredWindow, nil: Theme.muted
        }
    }
}

private struct CompactFreshnessLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 5))
            configuration.title
        }
    }
}

private struct PaceSummaryView: View {
    let window: UsageWindowSnapshot
    let usedPoints: Double?
    let now: Date
    let t: Strings

    var body: some View {
        let evaluation = UsagePaceEvaluator.evaluate(window, now: now)
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon(evaluation.status))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.pace(evaluation.status))
                .frame(width: 21, height: 21)
                .background(
                    Theme.pace(evaluation.status).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText(evaluation.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                if let detail = detailText(evaluation) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.fg2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            Theme.pace(evaluation.status).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private func detailText(_ evaluation: UsagePaceEvaluation) -> String? {
        var parts: [String] = []
        if let usedPoints {
            parts.append(t(
                "24h used \(Int(usedPoints.rounded()))%",
                "近24小时使用 \(Int(usedPoints.rounded()))%"
            ))
        }
        if let perDay = evaluation.recommendedPointsPerDay {
            parts.append(t(
                "aim for \(Int(perDay.rounded()))%/day",
                "建议每天约 \(Int(perDay.rounded()))%"
            ))
        } else if let perHour = evaluation.recommendedPointsPerHour {
            parts.append(t(
                "aim for \(Int(perHour.rounded()))%/hour",
                "建议每小时约 \(Int(perHour.rounded()))%"
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func statusText(_ status: UsagePaceStatus) -> String {
        switch status {
        case .unknown: t("Data needs confirmation", "数据待确认")
        case .balanced: t("Usage pace is balanced", "使用节奏正常")
        case .aheadOfPace: t("Usage is ahead of pace", "使用速度偏快")
        case .useMore: t("Good time to use more", "建议适当多用")
        case .wasteRisk: t("Unused quota may be wasted", "剩余额度有浪费风险")
        case .quotaTight: t("Quota is tight", "额度紧张")
        case .expired: t("Waiting for a new snapshot", "等待新快照")
        }
    }

    private func icon(_ status: UsagePaceStatus) -> String {
        switch status {
        case .balanced: "checkmark.circle.fill"
        case .useMore: "arrow.up.right.circle.fill"
        case .wasteRisk: "clock.badge.exclamationmark.fill"
        case .aheadOfPace: "gauge.with.dots.needle.67percent"
        case .quotaTight: "exclamationmark.triangle.fill"
        case .unknown, .expired: "questionmark.circle.fill"
        }
    }
}

private struct UsageWindowCard: View {
    let window: UsageWindowSnapshot
    let now: Date
    let t: Strings
    let trimScale: Double

    var body: some View {
        let evaluation = UsagePaceEvaluator.evaluate(window, now: now)
        let fraction = max(
            0,
            min(1, window.remainingPercent / 100 * trimScale)
        )
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(DisplayFormatter.longLabel(
                    for: window.kind,
                    chinese: t.zh
                ))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fg)
            }

            QuotaBar(
                fraction: fraction,
                color: Theme.pace(evaluation.status)
            )

            resetRow
        }
        .padding(10)
        .background(Theme.panelSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var resetRow: some View {
        if let resetsAt = window.resetsAt {
            if resetsAt > now {
                HStack {
                    Text(t(
                        "Resets in \(DisplayFormatter.countdown(seconds: resetsAt.timeIntervalSince(now)))",
                        "\(DisplayFormatter.countdown(seconds: resetsAt.timeIntervalSince(now), chinese: true))后重置"
                    ))
                    Spacer()
                    Text(DisplayFormatter.resetDate(
                        resetsAt,
                        chinese: t.zh
                    ))
                }
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(Theme.fg2)
            } else {
                Text(t(
                    "Window ended · waiting for a new snapshot",
                    "额度周期已结束 · 等待新快照"
                ))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(t("Reset time unavailable", "无重置时间"))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct QuotaBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(
                        width: max(0, proxy.size.width * fraction)
                    )
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
    }
}
