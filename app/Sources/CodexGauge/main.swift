import SwiftUI
import AppKit
import Foundation

@MainActor
func demoModel() -> UsageModel {
    let model = UsageModel(autoStart: false)
    let now = Date()
    model.snapshot = UsageSnapshot(
        planType: "Pro",
        windows: [
            UsageWindowSnapshot(
                id: "demo-five-hour",
                kind: .fiveHour,
                limitID: "codex",
                limitName: nil,
                remainingPercent: 86,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 3_600 + 40 * 60)
            ),
            UsageWindowSnapshot(
                id: "demo-weekly",
                kind: .weekly,
                limitID: "codex",
                limitName: nil,
                remainingPercent: 71,
                windowMinutes: 10_080,
                resetsAt: now.addingTimeInterval(4 * 86_400)
            )
        ],
        credits: CreditsSnapshot(
            hasCredits: false,
            unlimited: false,
            balance: Decimal(0)
        ),
        source: SnapshotSource(
            sessionFile: URL(fileURLWithPath: "/tmp/demo-rollout.jsonl"),
            eventTimestamp: now.addingTimeInterval(-60),
            fileModificationDate: now.addingTimeInterval(-60)
        )
    )
    model.recentUsageChanges[UsageWindowKind.fiveHour.key] = 8
    model.recentUsageChanges[UsageWindowKind.weekly.key] = 22
    return model
}

// "--shot <path>" renders the popover to a PNG (for the README hero) and exits.
// Otherwise launches the normal menu-bar app.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--shot"), i + 1 < args.count {
    let path = args[i + 1]
    UserDefaults.standard.set("en", forKey: LanguageKey)   // render the hero screenshot in English
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let model = demoModel()
        let view = PopoverView(model: model).background(Theme.panel)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)  size=\(img.size)")
        } else {
            print("render failed")
        }
    }
    exit(0)
}

// "--frames <dir> <N>" renders N frames of the rings drawing in (for the demo GIF) and exits.
if let i = args.firstIndex(of: "--frames"), i + 2 < args.count {
    let dir = args[i + 1]
    let n = max(2, Int(args[i + 2]) ?? 16)
    UserDefaults.standard.set("en", forKey: LanguageKey)
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        let model = demoModel()
        for f in 0..<n {
            let tt = Double(f) / Double(n - 1)
            let eased = 1 - pow(1 - tt, 2.2)   // ease-out, matches the app's ring animation
            let view = PopoverView(model: model, ringTrimScale: eased).background(Theme.panel)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: String(format: "%@/frame-%03d.png", dir, f)))
            }
        }
        print("wrote \(n) frames to \(dir)")
    }
    exit(0)
}

// "--check-local [sessions-path]" prints a sanitized local-read diagnostic and exits.
// It never prints a session filename, prompt, response, token, or credential.
if let i = args.firstIndex(of: "--check-local") {
    let path = i + 1 < args.count ? args[i + 1] : "~/.codex/sessions"
    let semaphore = DispatchSemaphore(value: 0)
    var status = 1
    Task.detached {
        defer { semaphore.signal() }
        do {
            let snapshot = try await SessionLogReader().latestSnapshot(path: path)
            let timestamp = ISO8601DateFormatter().string(
                from: snapshot.source.eventTimestamp
            )
            let windows = snapshot.windows.map {
                "\($0.kind.key)=\(Int($0.remainingPercent.rounded()))%"
            }.joined(separator: ",")
            print("event=\(timestamp) windows=\(windows)")
            status = 0
        } catch {
            print("local-read-error=\(error.localizedDescription)")
        }
    }
    semaphore.wait()
    exit(Int32(status))
}

CodexGaugeApp.main()
