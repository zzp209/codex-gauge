import AppKit
import SwiftUI

struct SettingsView: View {
    var model: UsageModel

    @AppStorage(Prefs.codexPathKey) private var codexPath = "~/.codex/sessions"
    @AppStorage(Prefs.intervalKey) private var refreshInterval = 60
    @AppStorage(Prefs.alertKey) private var alertEnabled = false
    @AppStorage(Prefs.dailyReminderKey) private var dailyReminderEnabled = true
    @AppStorage(Prefs.menuMetricKey) private var menuMetric = MenuMetricPreference.automatic.rawValue
    @AppStorage(LanguageKey) private var lang = "zh"

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginError: String?

    private var t: Strings { Strings(lang) }

    var body: some View {
        Form {
            Section(t("Data source", "数据来源")) {
                HStack(spacing: 8) {
                    TextField(
                        t("Codex sessions folder", "Codex 会话文件夹"),
                        text: $codexPath
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.refresh() }
                    Button(t("Choose…", "选取…")) { pick() }
                }
                Text(t(
                    "The app only reads local rollout JSONL files.",
                    "应用仅读取本地 rollout JSONL 文件。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(t("Display", "显示")) {
                Picker(t("Menu bar metric", "菜单栏显示"), selection: $menuMetric) {
                    Text(t("Automatic", "自动选择")).tag(MenuMetricPreference.automatic.rawValue)
                    Text(t("5-hour window", "5 小时窗口")).tag(MenuMetricPreference.fiveHour.rawValue)
                    Text(t("Weekly window", "每周窗口")).tag(MenuMetricPreference.weekly.rawValue)
                }
                Picker(t("Refresh local files every", "本地刷新频率"), selection: $refreshInterval) {
                    Text(t("30 seconds", "30 秒")).tag(30)
                    Text(t("1 minute", "1 分钟")).tag(60)
                    Text(t("5 minutes", "5 分钟")).tag(300)
                    Text(t("15 minutes", "15 分钟")).tag(900)
                }
                .onChange(of: refreshInterval) {
                    model.restartTimer()
                }
            }

            Section(t("Utilization reminders", "额度利用提醒")) {
                Toggle(
                    t("Notify about tight or unused quota", "额度紧张或可能浪费时提醒"),
                    isOn: $alertEnabled
                )
                .onChange(of: alertEnabled) {
                    if alertEnabled {
                        model.requestNotificationAuthorization()
                    }
                }
                Toggle(
                    t("Daily pace check after 17:00", "每天 17:00 后检查使用节奏"),
                    isOn: $dailyReminderEnabled
                )
                .disabled(!alertEnabled)
                Text(t(
                    "Notifications are suppressed when the local snapshot is not fresh.",
                    "本地快照不新鲜时不会发送通知。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(t("Startup", "启动")) {
                Toggle(
                    t("Launch at login", "登录后自动启动"),
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) {
                    do {
                        try LaunchAtLoginController.setEnabled(launchAtLogin)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLogin = LaunchAtLoginController.isEnabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(t("Language", "语言")) {
                Picker(t("Language", "语言"), selection: $lang) {
                    Text(t("System", "跟随系统")).tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
            }

            Section {
                HStack {
                    Text("Codex Gauge \(version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Open usage dashboard", "打开官方用量页")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://chatgpt.com/codex/settings/usage")!
                        )
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
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
            model.refresh()
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "1.1"
    }
}
