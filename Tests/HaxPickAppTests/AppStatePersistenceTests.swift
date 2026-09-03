import XCTest
@testable import HaxPickApp

@MainActor
final class AppStatePersistenceTests: XCTestCase {
    func testLoadInitialAPIKeyPrefersKeychainAndRemovesLegacyPlaintext() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(value: "  sk-keychain  ")

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertEqual(value, "sk-keychain")
        XCTAssertEqual(store.value, "sk-keychain")
        XCTAssertNil(defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialAPIKeyMigratesLegacyValueOnlyAfterSuccessfulKeychainSave() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("  sk-legacy  ", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore()

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(store.value, "sk-legacy")
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertNil(defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialAPIKeyKeepsLegacyValueWhenMigrationSaveFails() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testLoadInitialAPIKeyFallsBackToLegacyWhenKeychainReadFails() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            loadError: StubStoreError.failed,
            saveError: StubStoreError.failed
        )

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testPersistAPIKeyTrimsBeforeSavingAndRemovesLegacyPlaintext() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("sk-old", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore()

        let success = AppState.persistAPIKey(
            "  sk-new  ",
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertTrue(success)
        XCTAssertEqual(store.value, "sk-new")
        XCTAssertEqual(store.savedValues, ["sk-new"])
        XCTAssertNil(defaults.string(forKey: "deepseek_api_key"))
    }

    func testClearingAPIKeyRemovesLegacyPlaintextEvenWhenKeychainDeleteFails() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-keychain",
            deleteError: StubStoreError.failed
        )

        let success = AppState.persistAPIKey(
            "   ",
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertFalse(success)
        XCTAssertNil(defaults.string(forKey: "deepseek_api_key"))
        XCTAssertEqual(store.deleteCount, 1)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "HaxPickAppTests.\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        guard let suiteName = defaults.volatileDomainNames.first(where: { $0.hasPrefix("HaxPickAppTests.") }) else {
            defaults.removeObject(forKey: "deepseek_api_key")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private enum StubStoreError: Error {
    case failed
}

private final class MockAPIKeyStore: APIKeyStoring {
    var value: String?
    let loadError: Error?
    let saveError: Error?
    let deleteError: Error?
    private(set) var savedValues: [String] = []
    private(set) var deleteCount = 0

    init(
        value: String? = nil,
        loadError: Error? = nil,
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.value = value
        self.loadError = loadError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func load() throws -> String? {
        if let loadError {
            throw loadError
        }
        return value
    }

    func save(_ value: String) throws {
        if let saveError {
            throw saveError
        }
        self.value = value
        savedValues.append(value)
    }

    func delete() throws {
        deleteCount += 1
        if let deleteError {
            throw deleteError
        }
        value = nil
    }
}
