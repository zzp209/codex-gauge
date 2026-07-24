import XCTest
@testable import CodexGauge

final class PrefsMigrationTests: XCTestCase {
    func testMigratesKnownLegacyValuesWithoutOverwritingCurrentValues() {
        let suiteName = "CodexGaugeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("zh", forKey: LanguageKey)

        Prefs.migrateLegacyDefaultsIfNeeded(
            current: defaults,
            currentDomain: [LanguageKey: "zh"],
            legacyDomain: [
                Prefs.codexPathKey: "/tmp/legacy-sessions",
                Prefs.intervalKey: 300,
                Prefs.alertKey: true,
                LanguageKey: "en",
                "activeQueryEnabled": true
            ]
        )

        XCTAssertEqual(
            defaults.string(forKey: Prefs.codexPathKey),
            "/tmp/legacy-sessions"
        )
        XCTAssertEqual(defaults.integer(forKey: Prefs.intervalKey), 300)
        XCTAssertTrue(defaults.bool(forKey: Prefs.alertKey))
        XCTAssertEqual(defaults.string(forKey: LanguageKey), "zh")
        XCTAssertNil(defaults.object(forKey: "activeQueryEnabled"))
        XCTAssertTrue(defaults.bool(forKey: Prefs.migrationKey))
    }
}
