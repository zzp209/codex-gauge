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
                Divider().overlay(Theme.border).padding(.horizontal, 18)
                accountBoundary
                Divider().overlay(Theme.border).padding(.horizontal, 18)
                footer
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
                Text(plan)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.track, in: Capsule())
            }
            Spacer()
            Text(freshnessText(now: now))
                .font(.system(size: 10.5))
                .foregroundStyle(freshnessColor(now: now))
            Button {
                if let openSettingsAction {
                    openSettingsAction()
                } else {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.fg3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = model.snapshot {
            if let focus = UsageMenuSelector.select(
                windows: snapshot.windows,
                preference: .automatic,
                now: now
            ) {
                PaceSummaryView(window: focus, now: now, t: t)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                if let change = model.recentUsageChange(for: focus.kind) {
                    HistorySummaryView(
                        usedPoints: change,
                        evaluation: UsagePaceEvaluator.evaluate(
                            focus,
                            now: now
                        ),
                        t: t
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, -4)
                    .padding(.bottom, 12)
                }
            }

            VStack(spacing: 10) {
                ForEach(snapshot.windows) { window in
                    UsageWindowCard(
                        window: window,
                        now: now,
                        t: t,
                        trimScale: ringTrimScale
                    )
                }
                if let credits = snapshot.credits,
                   credits.hasCredits || credits.unlimited || credits.balance != nil {
                    creditsRow(credits)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("No trusted quota snapshot", "暂无可信额度快照"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text(model.lastError?.localizedDescription
                    ?? t("Run Codex once, then refresh.", "运行一次 Codex 后再刷新。"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fg2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func creditsRow(_ credits: CreditsSnapshot) -> some View {
        HStack {
            Label(t("Credits", "付费额度"), systemImage: "creditcard")
                .font(.system(size: 11.5, weight: .medium))
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
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.fg)
        .padding(10)
        .background(Theme.panelSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    private var accountBoundary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(t("Banked resets", "重置卡"), systemImage: "arrow.counterclockwise.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                Spacer()
                Button(t("Open usage dashboard", "打开官方用量页")) {
                    NSWorkspace.shared.open(
                        URL(string: "https://chatgpt.com/codex/settings/usage")!
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.info)
            }
            Text(t(
                "Count and expiry are not present in local session logs.",
                "数量和到期时间不在本地会话日志中，不做猜测。"
            ))
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.fg3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { model.refresh() } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(t("Refresh local snapshot", "刷新本地快照"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.fg2)
                .disabled(model.isRefreshing)

                Spacer()

                Button { NSApp.terminate(nil) } label: {
                    Text(t("Quit", "退出"))
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.fg3)
            }
            Text(t(
                "Local snapshot only · no token or automatic network access",
                "仅显示本地快照 · 不读取令牌、不自动联网"
            ))
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.fg3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func freshnessText(now: Date) -> String {
        guard let snapshot = model.snapshot else { return "" }
        let seconds = max(0, now.timeIntervalSince(snapshot.source.eventTimestamp))
        let age = DisplayFormatter.countdown(seconds: seconds, chinese: t.zh)
        switch model.freshness(now: now) {
        case .fresh:
            return t("Local · \(age) ago", "本地 · \(age)前")
        case .aging:
            return t("Aging · \(age)", "可能变化 · \(age)")
        case .stale:
            return t("Stale · \(age)", "已过时 · \(age)")
        case .expiredWindow:
            return t("Waiting for new snapshot", "等待新快照")
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

private struct HistorySummaryView: View {
    let usedPoints: Double
    let evaluation: UsagePaceEvaluation
    let t: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                t(
                    "Used \(Int(usedPoints.rounded())) points in the last 24 hours",
                    "最近 24 小时已使用 \(Int(usedPoints.rounded())) 个百分点"
                ),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.fg2)
            Text(outlook)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outlook: String {
        switch evaluation.status {
        case .useMore, .wasteRisk:
            return t(
                "Current pace may leave quota unused.",
                "按当前节奏，本周期可能仍有额度未使用。"
            )
        case .quotaTight, .aheadOfPace:
            return t(
                "Current pace is consuming quota quickly.",
                "当前使用速度较快，请留意后续任务。"
            )
        case .balanced:
            return t(
                "Current pace is aligned with the reset time.",
                "当前节奏与重置时间基本匹配。"
            )
        case .unknown, .expired:
            return t(
                "A fresher snapshot is needed for a forecast.",
                "需要更新快照后再判断后续节奏。"
            )
        }
    }
}

private struct PaceSummaryView: View {
    let window: UsageWindowSnapshot
    let now: Date
    let t: Strings

    var body: some View {
        let evaluation = UsagePaceEvaluator.evaluate(window, now: now)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(evaluation.status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.pace(evaluation.status))
                .frame(width: 22, height: 22)
                .background(
                    Theme.pace(evaluation.status).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(statusText(evaluation.status))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                if let guidance = guidanceText(evaluation) {
                    Text(guidance)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.fg2)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            Theme.pace(evaluation.status).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
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

    private func guidanceText(_ evaluation: UsagePaceEvaluation) -> String? {
        if let perDay = evaluation.recommendedPointsPerDay {
            return t(
                "To use it evenly: about \(Int(perDay.rounded())) points/day",
                "若希望充分使用：每天约 \(Int(perDay.rounded())) 个百分点"
            )
        }
        if let perHour = evaluation.recommendedPointsPerHour {
            return t(
                "To use it evenly: about \(Int(perHour.rounded())) points/hour",
                "若希望充分使用：每小时约 \(Int(perHour.rounded())) 个百分点"
            )
        }
        return nil
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
        let fraction = window.remainingPercent / 100
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: fraction * trimScale)
                    .stroke(
                        Theme.pace(evaluation.status),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: fraction)
                Text("\(Int(window.remainingPercent.rounded()))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fg)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(DisplayFormatter.longLabel(for: window.kind, chinese: t.zh))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                    Text(t("remaining", "剩余"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.fg3)
                }
                if let resetsAt = window.resetsAt {
                    if resetsAt > now {
                        Text(t(
                            "Resets in \(DisplayFormatter.countdown(seconds: resetsAt.timeIntervalSince(now)))",
                            "\(DisplayFormatter.countdown(seconds: resetsAt.timeIntervalSince(now), chinese: true))后重置"
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fg2)
                        Text(
                            resetsAt.formatted(
                                .dateTime.month(.twoDigits).day(.twoDigits)
                                    .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                            )
                        )
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg3)
                    } else {
                        Text(t("Window ended · refresh needed", "窗口已结束 · 等待新快照"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text(t("Reset time unavailable", "无重置时间"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fg3)
                }
            }
            Spacer()
        }
        .padding(11)
        .background(Theme.panelSoft, in: RoundedRectangle(cornerRadius: 12))
    }
}
