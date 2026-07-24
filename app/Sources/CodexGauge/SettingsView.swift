import AppKit
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case reminders
    case data

    var id: Self { self }
}

struct SettingsView: View {
    var model: UsageModel

    @AppStorage(Prefs.codexPathKey) private var codexPath =
        "~/.codex/sessions"
    @AppStorage(Prefs.intervalKey) private var refreshInterval = 900
    @AppStorage(Prefs.alertKey) private var alertEnabled = false
    @AppStorage(Prefs.tightReminderKey) private var tightReminderEnabled = true
    @AppStorage(Prefs.wasteReminderKey) private var wasteReminderEnabled = true
    @AppStorage(Prefs.dailyReminderKey) private var dailyReminderEnabled = true
    @AppStorage(Prefs.dailyReminderHourKey) private var dailyReminderHour = 17
    @AppStorage(Prefs.menuMetricKey) private var menuMetric =
        MenuMetricPreference.automatic.rawValue
    @AppStorage(LanguageKey) private var lang = "zh"

    @State private var page: SettingsPage = .general
    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginError: String?

    private var t: Strings { Strings(lang) }

    var body: some View {
        VStack(spacing: 0) {
            pagePicker
            Divider()
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 500, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pagePicker: some View {
        Picker("", selection: $page) {
            Text(t("General", "常规")).tag(SettingsPage.general)
            Text(t("Reminders", "提醒")).tag(SettingsPage.reminders)
            Text(t("Data", "数据")).tag(SettingsPage.data)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .general:
            generalPage
        case .reminders:
            remindersPage
        case .data:
            dataPage
        }
    }

    private var generalPage: some View {
        SettingsPageContainer {
            SettingsGroup(title: t("Menu bar", "菜单栏")) {
                SettingsRow(
                    title: t("Displayed quota", "显示额度"),
                    detail: t(
                        "Automatic picks the quota needing attention.",
                        "自动选择当前最需要关注的额度。"
                    )
                ) {
                    Picker("", selection: $menuMetric) {
                        Text(t("Automatic", "自动")).tag(
                            MenuMetricPreference.automatic.rawValue
                        )
                        Text(t("5-hour", "5 小时")).tag(
                            MenuMetricPreference.fiveHour.rawValue
                        )
                        Text(t("Weekly", "每周")).tag(
                            MenuMetricPreference.weekly.rawValue
                        )
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                Divider()

                SettingsRow(
                    title: t("Fallback check", "兜底检查"),
                    detail: t(
                        "File changes still refresh immediately.",
                        "会话文件变化仍会立即刷新。"
                    )
                ) {
                    Picker("", selection: $refreshInterval) {
                        Text(t("5 min", "5 分钟")).tag(300)
                        Text(t("15 min", "15 分钟")).tag(900)
                        Text(t("30 min", "30 分钟")).tag(1_800)
                        Text(t("1 hour", "1 小时")).tag(3_600)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .onChange(of: refreshInterval) {
                        model.restartMonitoring()
                    }
                }
            }

            SettingsGroup(title: t("App", "应用")) {
                SettingsToggleRow(
                    title: t("Launch at login", "登录后自动启动"),
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) {
                    updateLaunchAtLogin()
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                SettingsRow(title: t("Language", "界面语言")) {
                    Picker("", selection: $lang) {
                        Text(t("System", "跟随系统")).tag("system")
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
        }
    }

    private var remindersPage: some View {
        SettingsPageContainer {
            SettingsGroup(title: t("Quota reminders", "额度提醒")) {
                SettingsToggleRow(
                    title: t("Enable reminders", "启用额度提醒"),
                    detail: t(
                        "Only fresh local snapshots can trigger notifications.",
                        "仅新鲜的本地快照会触发通知。"
                    ),
                    isOn: $alertEnabled
                )
                .onChange(of: alertEnabled) {
                    if alertEnabled {
                        model.requestNotificationAuthorization()
                    }
                }
            }

            SettingsGroup(title: t("Reminder scenarios", "提醒场景")) {
                SettingsToggleRow(
                    title: t("Quota is running low", "额度紧张"),
                    detail: t(
                        "Warn when little quota remains well before reset.",
                        "剩余额度偏低且距离重置仍较远时提醒。"
                    ),
                    isOn: $tightReminderEnabled
                )
                .disabled(!alertEnabled)

                Divider()

                SettingsToggleRow(
                    title: t("Quota may expire unused", "额度可能浪费"),
                    detail: t(
                        "One reminder per 48h, 24h and final stage.",
                        "按 48 小时、24 小时和最后阶段各提醒一次。"
                    ),
                    isOn: $wasteReminderEnabled
                )
                .disabled(!alertEnabled)

                Divider()

                SettingsToggleRow(
                    title: t("Daily pace summary", "每日节奏回顾"),
                    detail: t(
                        "Suggest using more only when the pace is low.",
                        "仅在使用节奏偏低时建议安排任务。"
                    ),
                    isOn: $dailyReminderEnabled
                )
                .disabled(!alertEnabled)

                if dailyReminderEnabled {
                    HStack {
                        Text(t("Check after", "检查时间"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $dailyReminderHour) {
                            ForEach([9, 12, 15, 17, 18, 20, 21], id: \.self) {
                                Text(String(format: "%02d:00", $0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    .disabled(!alertEnabled)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var dataPage: some View {
        SettingsPageContainer {
            SettingsGroup(title: t("Local data", "本地数据")) {
                TextField(
                    t("Codex sessions folder", "Codex 会话文件夹"),
                    text: $codexPath
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.restartMonitoring()
                    model.refresh()
                }

                HStack {
                    Label(
                        t(
                            "Local rollout JSONL only; no tokens or chat text.",
                            "仅读取本地 rollout JSONL，不读取令牌和对话正文。"
                        ),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Choose…", "选取…")) {
                        pick()
                    }
                }
            }

            SettingsGroup(title: t("Quota details", "额度详情")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Reset cards and expiry", "重置卡和到期时间"))
                            .font(.callout.weight(.medium))
                        Text(t(
                            UsageDestinationLauncher.isCockpitToolsInstalled
                                ? "Cockpit Tools is installed."
                                : "Cockpit Tools is not installed.",
                            UsageDestinationLauncher.isCockpitToolsInstalled
                                ? "已检测到 Cockpit Tools。"
                                : "未检测到 Cockpit Tools，将打开官方页面。"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t(
                        UsageDestinationLauncher.isCockpitToolsInstalled
                            ? "Open Cockpit Tools"
                            : "Open usage page",
                        UsageDestinationLauncher.isCockpitToolsInstalled
                            ? "打开 Cockpit Tools"
                            : "打开用量页"
                    )) {
                        UsageDestinationLauncher.openPreferred()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Codex Gauge \(version)")
                .foregroundStyle(.secondary)
            Spacer()
            Button(t("Official usage page", "官方用量页")) {
                UsageDestinationLauncher.openOfficialUsagePage()
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: (codexPath as NSString).expandingTildeInPath
        )
        if panel.runModal() == .OK, let url = panel.url {
            codexPath = url.path
            model.restartMonitoring()
            model.refresh()
        }
    }

    private func updateLaunchAtLogin() {
        do {
            try LaunchAtLoginController.setEnabled(launchAtLogin)
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "1.2"
    }
}

private struct SettingsPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(18)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}
