import XCTest
@testable import CodexGauge

final class QuotaRefreshPresentationTests: XCTestCase {
    func testRecentSuccessfulCheckExplainsStaleMainQuotaSnapshot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let eventTimestamp = now.addingTimeInterval(
            -(16 * 3_600 + 24 * 60)
        )

        let presentation = QuotaRefreshPresentation.make(
            freshness: .stale,
            eventTimestamp: eventTimestamp,
            lastSuccessfulCheckAt: now.addingTimeInterval(-30),
            now: now,
            refreshInterval: 900,
            t: Strings("zh")
        )

        XCTAssertEqual(presentation.headerText, "已刷新 · 待主额度")
        XCTAssertEqual(presentation.paceTitle, "等待主额度新快照")
        XCTAssertEqual(
            presentation.paceDetail,
            "上次主额度 16小时24分钟前 · 自动刷新正常"
        )
        XCTAssertTrue(presentation.usesMutedQuotaStyle)
    }
}
