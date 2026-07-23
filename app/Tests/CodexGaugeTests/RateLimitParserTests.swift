import XCTest
@testable import CodexGauge

final class RateLimitParserTests: XCTestCase {
    func testParsesLegacyDualWindowByMinutes() throws {
        let event = try parsedEvent("legacy-dual-window")
        XCTAssertEqual(event.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(event.windows.map(\.remainingPercent), [88, 72])
    }

    func testParsesCurrentWeeklyOnlyWithoutMislabelingAsFiveHour() throws {
        let event = try parsedEvent("current-weekly-only")
        XCTAssertEqual(event.windows.count, 1)
        XCTAssertEqual(event.windows[0].kind, .weekly)
        XCTAssertEqual(event.windows[0].remainingPercent, 51)
        XCTAssertNil(event.windows.first { $0.kind == .fiveHour })
        XCTAssertEqual(event.credits?.balance, Decimal(0))
    }

    func testIgnoresNewerIndependentModelLimitForMainSnapshot() throws {
        let event = try parsedEvent("spark-before-main")
        XCTAssertEqual(event.limitID, "codex")
        XCTAssertEqual(event.windows[0].remainingPercent, 60)
    }

    func testMalformedInputDoesNotProduceSnapshot() throws {
        let text = try fixture("malformed-lines")
        XCTAssertNil(RateLimitParser.latestMainEvent(in: text))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func parsedEvent(_ name: String) throws -> RateLimitEvent {
        try XCTUnwrap(RateLimitParser.latestMainEvent(in: fixture(name)))
    }
}
