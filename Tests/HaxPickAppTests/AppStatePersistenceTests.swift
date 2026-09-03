import XCTest
@testable import HaxPickApp

@MainActor
final class AppStatePersistenceTests: XCTestCase {
    func testLoadInitialCredentialPrefersKeychainAndRemovesLegacyPlaintext() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(value: "  sk-keychain  ")

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "sk-keychain")
        XCTAssertEqual(result.storageState, .keychain)
        XCTAssertEqual(store.value, "sk-keychain")
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialCredentialMigratesLegacyValueOnlyAfterSuccessfulKeychainSave() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("  sk-legacy  ", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore()

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .keychain)
        XCTAssertEqual(store.value, "sk-legacy")
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testLoadInitialCredentialReportsPendingMigrationWhenSaveFails() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .legacyMigrationPending)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testKeychainReadFailureReportsUnavailableAndUsesLegacyWithoutWritingItBack() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-newer-keychain",
            loadError: StubStoreError.failed
        )

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "sk-legacy")
        XCTAssertEqual(result.storageState, .keychainUnavailable)
        XCTAssertEqual(store.value, "sk-newer-keychain")
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testKeychainReadFailureWithoutLegacyStillReportsUnavailable() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(loadError: StubStoreError.failed)

        let result = AppState.loadInitialCredential(
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertEqual(result.value, "")
        XCTAssertEqual(result.storageState, .keychainUnavailable)
    }

    func testRetryPendingMigrationReadsKeychainAgainThenMigratesOnlyWhenMissing() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .legacyMigrationPending)
        XCTAssertEqual(store.loadCount, 1)

        store.saveError = nil
        XCTAssertTrue(appState.retryAPIKeyStorage())

        XCTAssertEqual(store.loadCount, 2)
        XCTAssertEqual(store.savedValues, ["sk-legacy"])
        XCTAssertEqual(store.value, "sk-legacy")
        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testRetryAfterReadFailureUsesNewerKeychainAndNeverWritesLegacyBack() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-newer-keychain",
            loadError: StubStoreError.failed
        )
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .keychainUnavailable)
        XCTAssertTrue(store.savedValues.isEmpty)

        store.loadError = nil
        XCTAssertTrue(appState.retryAPIKeyStorage())

        XCTAssertEqual(appState.apiKey, "sk-newer-keychain")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertEqual(store.value, "sk-newer-keychain")
        XCTAssertNil(storage.defaults.string(forKey: "deepseek_api_key"))
    }

    func testRetryReadFailureKeepsLegacyFallbackWithoutWriting() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-newer-keychain",
            loadError: StubStoreError.failed
        )
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertFalse(appState.retryAPIKeyStorage())

        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .keychainUnavailable)
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertEqual(store.value, "sk-newer-keychain")
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
    }

    func testPersistAPIKeyTrimsBeforeSavingAndRemovesLegacyPlaintextAfterSuccess() {
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

    func testFailedExplicitSavePreservesLastCommittedLegacyAndKeychainValues() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-current",
            saveError: StubStoreError.failed
        )

        let success = AppState.persistAPIKey(
            "sk-new",
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertFalse(success)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
        XCTAssertEqual(store.value, "sk-current")
    }

    func testFailedExplicitClearPreservesLastCommittedLegacyAndKeychainValues() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(
            value: "sk-current",
            deleteError: StubStoreError.failed
        )

        let success = AppState.persistAPIKey(
            "   ",
            store: store,
            legacyDefaults: storage.defaults
        )

        XCTAssertFalse(success)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")
        XCTAssertEqual(store.value, "sk-current")
        XCTAssertEqual(store.deleteCount, 1)
    }

    func testPendingMigrationFailedExplicitSaveKeepsFallbackAndPendingStateRetryable() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertEqual(appState.apiKeyStorageState, .legacyMigrationPending)
        XCTAssertFalse(appState.saveAPIKey("sk-new"))

        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .legacyMigrationPending)
        XCTAssertEqual(storage.defaults.string(forKey: "deepseek_api_key"), "sk-legacy")

        store.saveError = nil
        XCTAssertTrue(appState.retryAPIKeyStorage())
        XCTAssertEqual(appState.apiKey, "sk-legacy")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertEqual(store.value, "sk-legacy")
    }

    func testAppStateRejectsInvalidKeyWithoutTouchingCommittedValue() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(value: "sk-current")
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        let success = appState.saveAPIKey("not-a-deepseek-key")

        XCTAssertFalse(success)
        XCTAssertEqual(appState.apiKey, "sk-current")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertEqual(store.value, "sk-current")
        XCTAssertTrue(store.savedValues.isEmpty)
        XCTAssertTrue(appState.apiKeyStorageError?.contains("格式无效") == true)
    }

    func testAppStateFailedSaveKeepsLastCommittedRuntimeValueAndState() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(value: "sk-current")
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)
        store.saveError = StubStoreError.failed

        let success = appState.saveAPIKey("sk-new")

        XCTAssertFalse(success)
        XCTAssertEqual(appState.apiKey, "sk-current")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertEqual(store.value, "sk-current")
        XCTAssertNotNil(appState.apiKeyStorageError)
    }

    func testAppStateFailedClearKeepsLastCommittedRuntimeValueAndState() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(value: "sk-current")
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)
        store.deleteError = StubStoreError.failed

        let success = appState.saveAPIKey("   ")

        XCTAssertFalse(success)
        XCTAssertEqual(appState.apiKey, "sk-current")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertEqual(store.value, "sk-current")
        XCTAssertNotNil(appState.apiKeyStorageError)
    }

    func testAppStateSuccessfulSaveCommitsRuntimeValueAndClearsPreviousError() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(value: "sk-current")
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)
        store.saveError = StubStoreError.failed

        XCTAssertFalse(appState.saveAPIKey("sk-failed"))
        XCTAssertNotNil(appState.apiKeyStorageError)

        store.saveError = nil
        XCTAssertTrue(appState.saveAPIKey("  sk-recovered  "))

        XCTAssertNil(appState.apiKeyStorageError)
        XCTAssertEqual(appState.apiKey, "sk-recovered")
        XCTAssertEqual(appState.apiKeyStorageState, .keychain)
        XCTAssertEqual(store.value, "sk-recovered")
    }

    func testAppStateSuccessfulClearCommitsEmptyStorageState() {
        let storage = makeDefaults()
        defer { storage.clear() }
        let store = MockAPIKeyStore(value: "sk-current")
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertTrue(appState.saveAPIKey(""))

        XCTAssertEqual(appState.apiKey, "")
        XCTAssertEqual(appState.apiKeyStorageState, .empty)
        XCTAssertNil(store.value)
    }

    func testCredentialStatusMessageDoesNotClaimLegacyFallbackIsInKeychain() {
        let storage = makeDefaults()
        defer { storage.clear() }
        storage.defaults.set("sk-legacy", forKey: "deepseek_api_key")
        let store = MockAPIKeyStore(saveError: StubStoreError.failed)
        let appState = AppState(apiKeyStore: store, defaults: storage.defaults)

        XCTAssertTrue(appState.apiKeyStorageNeedsAttention)
        XCTAssertTrue(appState.canRetryAPIKeyStorage)
        XCTAssertTrue(appState.apiKeyStorageStatusMessage.contains("旧版存储"))
        XCTAssertFalse(appState.apiKeyStorageStatusMessage.contains("已安全保存在"))
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
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?
    private(set) var loadCount = 0
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
        loadCount += 1
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
