import AppKit
import SwiftUI

@MainActor
final class CodexGaugeDelegate:
    NSObject,
    NSApplicationDelegate,
    NSPopoverDelegate,
    NSWindowDelegate
{
    let model = UsageModel(autoStart: false)

    private var statusItem: NSStatusItem?
    private(set) var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var statusTimer: Timer?
    private var statusCache = StatusPresentationCache()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        if Prefs.alertEnabled {
            model.requestNotificationAuthorization()
        }
        model.onSnapshotChange = { [weak self] in
            self?.updateStatusTitle()
        }
        model.restartMonitoring()
        Task {
            await model.refreshNow()
        }
        statusTimer = Timer.scheduledTimer(
            withTimeInterval: 300,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.displayDate = Date()
                self?.updateStatusTitle()
            }
        }
        statusTimer?.tolerance = 60
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        model.stopMonitoring()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        item.button?.title = "◌ Codex"
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
    }

    func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover
    }

    func preparePopoverContent() {
        guard let popover, popover.contentViewController == nil else {
            return
        }
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                openSettingsAction: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.showSettings()
                }
            )
        )
    }

    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let tone: StatusTone
        switch model.menuBarPaceStatus(now: now) {
        case .useMore:
            tone = .informational
        case .wasteRisk:
            tone = .warning
        case .aheadOfPace:
            tone = .warning
        case .quotaTight:
            tone = .critical
        case .unknown, .expired:
            tone = .muted
        case .balanced, nil:
            tone = .normal
        }
        let presentation = StatusPresentation(
            title: model.menuBarTitle(now: now),
            tone: tone
        )
        guard statusCache.shouldApply(presentation) else { return }
        button.attributedTitle = NSAttributedString(
            string: presentation.title,
            attributes: [.foregroundColor: color(for: tone)]
        )
    }

    private func color(for tone: StatusTone) -> NSColor {
        switch tone {
        case .normal: .labelColor
        case .informational: .systemBlue
        case .warning: .systemOrange
        case .critical: .systemRed
        case .muted: .secondaryLabelColor
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton? = nil) {
        guard let button = button ?? statusItem?.button, let popover else {
            return
        }
        if !popover.isShown {
            preparePopoverContent()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(model: model)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = Strings(
                UserDefaults.standard.string(forKey: LanguageKey) ?? "system"
            )("Codex Gauge Settings", "Codex Gauge 设置")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = true
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow
        else { return }
        settingsWindow = nil
    }
}

struct CodexGaugeApp: App {
    @NSApplicationDelegateAdaptor(CodexGaugeDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
