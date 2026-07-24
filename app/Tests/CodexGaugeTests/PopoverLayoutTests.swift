import SwiftUI
import XCTest
@testable import CodexGauge

@MainActor
final class PopoverLayoutTests: XCTestCase {
    func testSettingsWindowUsesCompactTabbedLayout() throws {
        let model = UsageModel(provider: LayoutEmptyProvider(), autoStart: false)
        let renderer = ImageRenderer(content: SettingsView(model: model))
        let image = try XCTUnwrap(renderer.nsImage)

        XCTAssertLessThanOrEqual(image.size.height, 460)
    }

    func testChineseWeeklyPopoverFitsCompactHeight() throws {
        let image = try renderWeeklyPopover()

        XCTAssertEqual(image.size.width, 340, accuracy: 0.5)
        XCTAssertLessThanOrEqual(image.size.height, 340)
    }

    func testCompactPopoverHasNoUnsupportedControlGlyph() throws {
        let image = try renderWeeklyPopover()
        let bitmap = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init)
        )
        var magentaPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else { continue }
                if color.redComponent > 0.95,
                   color.greenComponent < 0.4,
                   color.blueComponent > 0.2 {
                    magentaPixelCount += 1
                }
            }
        }

        XCTAssertEqual(magentaPixelCount, 0)
    }

    private func renderWeeklyPopover() throws -> NSImage {
        UserDefaults.standard.set("zh", forKey: LanguageKey)
        let now = Date()
        let model = UsageModel(provider: LayoutEmptyProvider(), autoStart: false)
        model.snapshot = UsageSnapshot(
            planType: "pro",
            windows: [
                UsageWindowSnapshot(
                    id: "weekly",
                    kind: .weekly,
                    limitID: "codex",
                    limitName: nil,
                    remainingPercent: 44,
                    windowMinutes: 10_080,
                    resetsAt: now.addingTimeInterval(4 * 86_400)
                )
            ],
            credits: CreditsSnapshot(
                hasCredits: false,
                unlimited: false,
                balance: 0
            ),
            source: SnapshotSource(
                sessionFile: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
                eventTimestamp: now,
                fileModificationDate: now
            )
        )
        model.recentUsageChanges[UsageWindowKind.weekly.key] = 3

        let renderer = ImageRenderer(content: PopoverView(model: model))
        return try XCTUnwrap(renderer.nsImage)
    }
}

private actor LayoutEmptyProvider: UsageSnapshotProviding {
    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        throw UsageDataError.noRateLimitEvents
    }
}
