import XCTest
@testable import HaxPickApp

@MainActor
final class CredentialHealthRecoveryTests: XCTestCase {
    func testInvalidKeychainCleanupFailureDoesNotWriteLegacyOverUnknownItem() {
        let storage = TestCredentialDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = CleanupFailureStore(
            value: "corrupt-keychain-value",
            deleteError: StubCredentialError.failed
        )

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .keychainUnavailable)
        XCTAssertEqual(store.value, "corrupt-keychain-value")
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testRetryAfterInvalidKeychainCleanupRecoversBeforeMigratingLegacy() {
        let storage = TestCredentialDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = CleanupFailureStore(
            value: "corrupt-keychain-value",
            deleteError: StubCredentialError.failed
        )
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertEqual(appState.apiKeyStorageState, .keychainUnavailable)
        XCTAssertTrue(store.savedValues.isEmpty)

        store.deleteError = nil
        XCTAssertTrue(appState.retryAPIKeyStorage())

        XCTAssertEqual(store.deleteCount, 2)
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertEqual(store.value, "sk-legacy")
        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testUndecodableKeychainItemIsDeletedBeforeLegacyMigration() {
        let storage = TestCredentialDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = UndecodableStore()

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .keychain)
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testUndecodableKeychainItemDeleteFailureStaysUnavailableAndDoesNotWriteLegacy() {
        let storage = TestCredentialDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = UndecodableStore(deleteError: StubCredentialError.failed)

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .keychainUnavailable)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }
}

private struct TestCredentialDefaults {
    let suiteName = "CredentialHealthRecoveryTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func clear() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private enum StubCredentialError: Error {
    case failed
}

private final class CleanupFailureStore: APIKeyStoring {
    var value: String?
    var deleteError: Error?
    private(set) var savedValues: [String] = []
    private(set) var deleteCount = 0

    init(value: String?, deleteError: Error?) {
        self.value = value
        self.deleteError = deleteError
    }

    func load() throws -> String? {
        value
    }

    func save(_ value: String) throws {
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

private final class UndecodableStore: APIKeyStoring {
    var deleteError: Error?
    private(set) var savedValues: [String] = []
    private(set) var deleteCount = 0
    private var hasBadItem = true

    init(deleteError: Error? = nil) {
        self.deleteError = deleteError
    }

    func load() throws -> String? {
        if hasBadItem {
            throw APIKeyStoreError.invalidStoredValue
        }
        return nil
    }

    func save(_ value: String) throws {
        savedValues.append(value)
    }

    func delete() throws {
        deleteCount += 1
        if let deleteError {
            throw deleteError
        }
        hasBadItem = false
    }
}
