import XCTest
@testable import HaxPickApp

@MainActor
final class LocalCredentialPersistenceTests: XCTestCase {
    func testLoadsAPIKeyFromLocalDefaults() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("  sk-local  ", forKey: "deepseek_api_key")

        let appState = AppState(defaults: storage.defaults)

        XCTAssertEqual(appState.apiKey, "sk-local")
        XCTAssertEqual(appState.apiKeyStorageState, .local)
        XCTAssertEqual(appState.apiKeyStorageStatusMessage, "Key 已保存在本地缓存。")
    }

    func testSaveAndClearAPIKeyUseLocalDefaultsOnly() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let appState = AppState(defaults: storage.defaults)

        XCTAssertTrue(appState.saveAPIKey("  sk-saved  "))
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-saved")
        XCTAssertEqual(appState.apiKey, "sk-saved")
        XCTAssertEqual(appState.apiKeyStorageState, .local)

        XCTAssertTrue(appState.saveAPIKey("   "))
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
        XCTAssertEqual(appState.apiKeyStorageState, .empty)
    }

    func testInvalidAPIKeyDoesNotChangeLocalValue() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-existing", forKey: "deepseek_api_key")
        let appState = AppState(defaults: storage.defaults)

        XCTAssertFalse(appState.saveAPIKey("not-a-deepseek-key"))
        XCTAssertEqual(appState.apiKey, "sk-existing")
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-existing")
        XCTAssertNotNil(appState.apiKeyStorageError)
    }

    private func makeDefaults() -> TestDefaults {
        TestDefaults(suiteName: "LocalCredentialPersistenceTests.\(UUID().uuidString)")
    }
}

private struct TestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init(suiteName: String) {
        self.suiteName = suiteName
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    func clear() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
