import XCTest
@testable import HaxPickApp

@MainActor
final class AppStatePersistenceTests: XCTestCase {
    func testLoadInitialAPIKeyPrefersKeychainAndRemovesLegacyPlaintext() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(value: "  sk-keychain  ")

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(value, "sk-keychain")
        XCTAssertEqual(store.value, "sk-keychain")
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialAPIKeyMigratesLegacyValueOnlyAfterSuccessfulKeychainSave() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("  sk-legacy  ", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore()

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(store.value, "sk-legacy")
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialAPIKeyKeepsLegacyValueWhenMigrationSaveFails() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testLoadInitialAPIKeyFallsBackToLegacyWhenKeychainReadFails() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            loadError: StubStoreError.failed,
            saveError: StubStoreError.failed
        )

        let value = AppState.loadInitialAPIKey(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testPersistAPIKeyTrimsBeforeSavingAndRemovesLegacyPlaintext() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-old", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore()

        let success = AppState.persistAPIKey(
            "  sk-new  ",
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertTrue(success)
        XCTAssertEqual(store.value, "sk-new")
        XCTAssertEqual(store.savedValues, ["sk-new"])
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testClearingAPIKeyRemovesLegacyPlaintextEvenWhenKeychainDeleteFails() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-keychain",
            deleteError: StubStoreError.failed
        )

        let success = AppState.persistAPIKey(
            "   ",
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertFalse(success)
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
        XCTAssertEqual(store.deleteCount, 1)
    }

    private func makeDefaults() -> TestDefaults {
        TestDefaults(suiteName: "HaxPickAppTests.\(UUID().uuidString)")
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
