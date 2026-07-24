import AppKit
import XCTest
@testable import CodexGauge

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testSettingsWindowIsRetainedForSafeReuseAfterClose() throws {
        let delegate = CodexGaugeDelegate()

        delegate.showSettings()
        let window = try XCTUnwrap(delegate.settingsWindow)

        XCTAssertFalse(window.isReleasedWhenClosed)
        window.close()
        XCTAssertTrue(delegate.settingsWindow === window)
        XCTAssertNil(window.contentViewController)

        delegate.showSettings()
        XCTAssertNotNil(window.contentViewController)
    }

    func testShowingPopoverHidesVisibleSettingsWindow() {
        let delegate = CodexGaugeDelegate()

        delegate.showSettings()
        XCTAssertEqual(delegate.settingsWindow?.isVisible, true)

        delegate.showPopover()
        XCTAssertEqual(delegate.settingsWindow?.isVisible, false)

        delegate.settingsWindow?.close()
    }

    func testPopoverContentIsCreatedOnDemandAndReleasedAfterClose() {
        let delegate = CodexGaugeDelegate()

        delegate.configurePopover()
        XCTAssertNil(delegate.popover?.contentViewController)

        delegate.preparePopoverContent()
        XCTAssertNotNil(delegate.popover?.contentViewController)

        delegate.popoverDidClose(
            Notification(
                name: NSPopover.didCloseNotification,
                object: delegate.popover
            )
        )
        XCTAssertNil(delegate.popover?.contentViewController)
    }
}
