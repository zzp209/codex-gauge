import XCTest
@testable import CodexGauge

final class UsageDestinationTests: XCTestCase {
    func testPrefersInstalledCockpitToolsApplication() {
        let applicationURL = URL(
            fileURLWithPath: "/Applications/Cockpit Tools.app"
        )

        XCTAssertEqual(
            UsageDestinationResolver.preferred(
                cockpitApplicationURL: applicationURL
            ),
            .application(applicationURL)
        )
    }

    func testFallsBackToOfficialUsagePageWhenCockpitToolsIsMissing() {
        XCTAssertEqual(
            UsageDestinationResolver.preferred(
                cockpitApplicationURL: nil
            ),
            .web(UsageDestinationResolver.officialUsageURL)
        )
    }
}
