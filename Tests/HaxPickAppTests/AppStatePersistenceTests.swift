import XCTest
@testable import HaxPickApp

@MainActor
final class AppStatePersistenceTests: XCTestCase {
    func testPersistAPIKeyRemovesStoredValueWhenCleared() {
        let suiteName = "HaxPickAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppState.persistAPIKey("sk-existing", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "deepseek_api_key"), "sk-existing")

        AppState.persistAPIKey("   ", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "deepseek_api_key"))
    }

    func testPersistAPIKeyTrimsWhitespaceBeforeSaving() {
        let suiteName = "HaxPickAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppState.persistAPIKey("  sk-test  ", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "deepseek_api_key"), "sk-test")
    }
}
