import AppKit
import SwiftUI

@MainActor
final class CodexGaugeDelegate: NSObject, NSApplicationDelegate {
    let model = UsageModel(autoStart: false)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var displayTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        if Prefs.alertEnabled {
            model.requestNotificationAuthorization()
        }
        model.restartTimer()
        Task {
            await model.refreshNow()
            updateStatusTitle()
        }
        displayTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.displayDate = Date()
                self?.updateStatusTitle()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayTimer?.invalidate()
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

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                openSettingsAction: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.showSettings()
                }
            )
        )
        self.popover = popover
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let color: NSColor
        switch model.menuBarPaceStatus(now: now) {
        case .useMore:
            color = .systemBlue
        case .wasteRisk:
            color = .systemOrange
        case .aheadOfPace:
            color = .systemYellow
        case .quotaTight:
            color = .systemRed
        case .unknown, .expired:
            color = .secondaryLabelColor
        case .balanced, nil:
            color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: model.menuBarTitle(now: now),
            attributes: [.foregroundColor: color]
        )
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
            window.title = "Codex Gauge Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
