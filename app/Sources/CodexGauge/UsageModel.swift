import Foundation
import Observation
import SwiftUI
import UserNotifications

enum Prefs {
    static let migrationKey = "didMigrateRuby1304DefaultsV1"
    static let legacyBundleIdentifier = "com.ruby1304.codex-gauge"
    static let codexPathKey = "codexPath"
    static let intervalKey = "refreshInterval"
    static let alertKey = "lowAlertEnabled"
    static let dailyReminderKey = "dailyPaceReminderEnabled"
    static let tightReminderKey = "tightQuotaReminderEnabled"
    static let wasteReminderKey = "unusedQuotaReminderEnabled"
    static let dailyReminderHourKey = "dailyPaceReminderHour"
    static let menuMetricKey = "menuMetricPreference"

    static func registerDefaults() {
        let currentDomain = Bundle.main.bundleIdentifier.flatMap {
            UserDefaults.standard.persistentDomain(forName: $0)
        }
        migrateLegacyDefaultsIfNeeded(
            current: .standard,
            currentDomain: currentDomain,
            legacyDomain: UserDefaults.standard.persistentDomain(
                forName: legacyBundleIdentifier
            )
        )
        UserDefaults.standard.register(defaults: [
            codexPathKey: "~/.codex/sessions",
            intervalKey: 900,
            alertKey: false,
            dailyReminderKey: true,
            tightReminderKey: true,
            wasteReminderKey: true,
            dailyReminderHourKey: 17,
            menuMetricKey: MenuMetricPreference.automatic.rawValue,
            LanguageKey: "zh"
        ])
        let fallbackInterval = normalizedFallbackInterval(
            UserDefaults.standard.integer(forKey: intervalKey)
        )
        if UserDefaults.standard.integer(forKey: intervalKey) != fallbackInterval {
            UserDefaults.standard.set(fallbackInterval, forKey: intervalKey)
        }
    }

    static func migrateLegacyDefaultsIfNeeded(
        current: UserDefaults,
        currentDomain: [String: Any]?,
        legacyDomain: [String: Any]?
    ) {
        guard currentDomain?[migrationKey] as? Bool != true else { return }
        let keys = [
            codexPathKey,
            intervalKey,
            alertKey,
            dailyReminderKey,
            tightReminderKey,
            wasteReminderKey,
            dailyReminderHourKey,
            menuMetricKey,
            LanguageKey,
            "quotaNotificationLedgerV1"
        ]
        for key in keys where currentDomain?[key] == nil {
            if let value = legacyDomain?[key] {
                current.set(value, forKey: key)
            }
        }
        current.set(true, forKey: migrationKey)
    }

    static var codexPath: String {
        UserDefaults.standard.string(forKey: codexPathKey)
            ?? "~/.codex/sessions"
    }

    static var interval: Int {
        normalizedFallbackInterval(
            UserDefaults.standard.integer(forKey: intervalKey)
        )
    }

    static func normalizedFallbackInterval(_ value: Int) -> Int {
        max(300, value)
    }

    static var alertEnabled: Bool {
        UserDefaults.standard.bool(forKey: alertKey)
    }

    static var dailyReminderEnabled: Bool {
        UserDefaults.standard.bool(forKey: dailyReminderKey)
    }

    static var reminderPreferences: ReminderPreferences {
        ReminderPreferences(
            quotaTight: UserDefaults.standard.bool(
                forKey: tightReminderKey
            ),
            wasteRisk: UserDefaults.standard.bool(
                forKey: wasteReminderKey
            ),
            dailyPace: dailyReminderEnabled,
            dailyHour: UserDefaults.standard.integer(
                forKey: dailyReminderHourKey
            )
        )
    }

    static var menuMetric: MenuMetricPreference {
        let raw = UserDefaults.standard.string(forKey: menuMetricKey)
        return MenuMetricPreference(rawValue: raw ?? "") ?? .automatic
    }
}

@MainActor
@Observable
final class UsageModel {
    private let provider: any UsageSnapshotProviding
    private let historyStore: SnapshotHistoryStore
    private let directoryWatcher: any SessionDirectoryWatching
    private var timer: Timer?

    var onSnapshotChange: (@MainActor () -> Void)?
    var snapshot: UsageSnapshot?
    var recentUsageChanges: [String: Double] = [:]
    var lastError: UsageDataError?
    var isRefreshing = false
    var displayDate = Date()

    init(
        provider: any UsageSnapshotProviding = SessionLogReader(),
        historyStore: SnapshotHistoryStore = SnapshotHistoryStore(),
        directoryWatcher: any SessionDirectoryWatching = SessionDirectoryWatcher(),
        autoStart: Bool = true
    ) {
        self.provider = provider
        self.historyStore = historyStore
        self.directoryWatcher = directoryWatcher
        Prefs.registerDefaults()
        NotificationLedger.prune(
            before: Date().addingTimeInterval(-45 * 86_400)
        )
        if autoStart {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
                self?.restartTimer()
            }
        }
    }

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(Prefs.interval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.displayDate = Date()
                self?.refresh()
            }
        }
        timer?.tolerance = min(60, TimeInterval(Prefs.interval) * 0.2)
    }

    func restartMonitoring() {
        restartTimer()
        directoryWatcher.stop()
        try? directoryWatcher.start(path: Prefs.codexPath) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        directoryWatcher.stop()
    }

    func refresh() {
        Task {
            await refreshNow()
        }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            onSnapshotChange?()
        }
        do {
            let value = try await provider.latestSnapshot(path: Prefs.codexPath)
            snapshot = value
            lastError = nil
            let now = Date()
            await updateHistory(with: value, now: now)
            checkNotifications(now: now)
        } catch let error as UsageDataError {
            lastError = error
        } catch {
            lastError = .unsupportedSchema
        }
    }

    func recentUsageChange(for kind: UsageWindowKind) -> Double? {
        recentUsageChanges[kind.key]
    }

    var menuBarTitle: String {
        menuBarTitle(now: displayDate)
    }

    var menuBarColor: Color? {
        menuBarColor(now: displayDate)
    }

    func freshness(now: Date) -> SnapshotFreshness? {
        guard let snapshot else { return nil }
        return UsagePaceEvaluator.freshness(
            eventTimestamp: snapshot.source.eventTimestamp,
            windows: snapshot.windows,
            now: now
        )
    }

    func menuBarTitle(now: Date) -> String {
        guard let snapshot else { return "◌ Codex" }
        guard freshness(now: now) != .expiredWindow else {
            return "! \(isChinese ? "待刷新" : "waiting")"
        }
        guard let window = UsageMenuSelector.select(
            windows: snapshot.windows,
            preference: Prefs.menuMetric,
            now: now
        ) else {
            return "◌ Codex"
        }

        let prefix = freshness(now: now) == .stale ? "? " : ""
        let label = DisplayFormatter.shortLabel(
            for: window.kind,
            chinese: isChinese
        )
        let remaining = Int(window.remainingPercent.rounded())
        return "\(prefix)\(label) \(remaining)%"
    }

    func menuBarColor(now: Date) -> Color? {
        guard let status = menuBarPaceStatus(now: now) else { return nil }
        return status == .balanced ? nil : Theme.pace(status)
    }

    func menuBarPaceStatus(now: Date) -> UsagePaceStatus? {
        guard let snapshot,
              freshness(now: now) != .stale,
              freshness(now: now) != .expiredWindow,
              let window = UsageMenuSelector.select(
                windows: snapshot.windows,
                preference: Prefs.menuMetric,
                now: now
              )
        else { return nil }
        return UsagePaceEvaluator.evaluate(window, now: now).status
    }

    func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, _ in
            if !granted {
                UserDefaults.standard.set(false, forKey: Prefs.alertKey)
            }
        }
    }

    private var isChinese: Bool {
        Strings(
            UserDefaults.standard.string(forKey: LanguageKey) ?? "system"
        ).zh
    }

    private func updateHistory(
        with value: UsageSnapshot,
        now: Date
    ) async {
        guard UsagePaceEvaluator.freshness(
            eventTimestamp: value.source.eventTimestamp,
            windows: value.windows,
            now: now
        ) == .fresh else {
            recentUsageChanges = [:]
            return
        }

        do {
            try await historyStore.append(value, capturedAt: now)
            var changes: [String: Double] = [:]
            for window in value.windows {
                if let delta = try await historyStore.change(
                    in: window.kind,
                    last: 24 * 3_600,
                    now: now
                ), delta > 0 {
                    changes[window.kind.key] = delta
                }
            }
            recentUsageChanges = changes
        } catch {
            recentUsageChanges = [:]
            debugPrint("CodexGauge history update skipped")
        }
    }

    private func checkNotifications(now: Date) {
        guard Prefs.alertEnabled,
              Bundle.main.bundleIdentifier != nil,
              let snapshot,
              let freshness = freshness(now: now)
        else { return }

        var sentKeys = NotificationLedger.allKeys()
        let preferences = Prefs.reminderPreferences
        for window in snapshot.windows {
            let evaluation = UsagePaceEvaluator.evaluate(window, now: now)
            let pending = NotificationPolicy.notifications(
                window: window,
                evaluation: evaluation,
                freshness: freshness,
                now: now,
                sentKeys: sentKeys,
                preferences: preferences
            )
            for notification in pending {
                send(notification)
                sentKeys.insert(notification.dedupeKey)
            }
        }
    }

    private func send(_ notification: QuotaNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: notification.dedupeKey,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                NotificationLedger.insert(notification.dedupeKey)
            }
        }
    }
}
