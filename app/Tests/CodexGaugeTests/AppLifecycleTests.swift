import AppKit
import XCTest
@testable import CodexGauge

@MainActor
final class AppLifecycleTests: XCTestCase {
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
