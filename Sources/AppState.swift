import AppKit
import Security
import SwiftUI

protocol APIKeyStoring {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private static let defaultService = "com.hax.haxpick.deepseek-api-key"
    private static let defaultAccount = "deepseek-api-key"

    private let service: String
    private let account: String

    init(
        service: String = KeychainAPIKeyStore.defaultService,
        account: String = KeychainAPIKeyStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw APIKeyStoreError.invalidStoredValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStoreError.keychain(status)
        }
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum APIKeyStoreError: LocalizedError {
    case invalidStoredValue
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            return "Keychain 中的 DeepSeek API Key 无法读取。"
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "Keychain 操作失败（\(status)）：\(message)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private static let legacyAPIKeyStorageKey = "deepseek_api_key"
    private static let modelStorageKey = "deepseek_model"

    @Published var apiKey: String {
        didSet {
            Self.persistAPIKey(
                apiKey,
                store: apiKeyStore,
                legacyDefaults: defaults
            )
        }
    }

    @Published var selectedModel: DeepSeekService.Model {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.modelStorageKey)
        }
    }

    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var statusMessage = "准备就绪"

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    private let apiKeyStore: any APIKeyStoring
    private let defaults: UserDefaults
    private let panelController = ToolbarPanelController()
    private lazy var permissionGuideController = PermissionGuideWindowController(appState: self)
    private lazy var deepSeekService = DeepSeekService(apiKeyProvider: { [weak self] in
        self?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }, modelProvider: { [weak self] in
        self?.selectedModel ?? .flash
    })
    private lazy var selectionMonitor = SelectionMonitor(
        onSelectionDetected: { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.showToolbar(for: snapshot.text, at: snapshot.anchorPoint)
            }
        },
        onSelectionMissed: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleSelectionMissed()
            }
        }
    )
    private var hasStarted = false

    init(
        apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        defaults: UserDefaults = .standard
    ) {
        self.apiKeyStore = apiKeyStore
        self.defaults = defaults
        self.apiKey = Self.loadInitialAPIKey(
            store: apiKeyStore,
            legacyDefaults: defaults
        )
        self.selectedModel = DeepSeekService.Model(
            rawValue: defaults.string(forKey: Self.modelStorageKey) ?? ""
        ) ?? .flash

        panelController.onDismissSelection = { [weak self] text in
            self?.selectionMonitor.ignoreCurrentSelection(text)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)
        selectionMonitor.start()
        if permissionGranted {
            statusMessage = "已开始监听划词"
        } else {
            statusMessage = "首次使用需要先开启辅助功能"
            permissionGuideController.presentIfNeeded()
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        permissionGranted = AXIsProcessTrustedWithOptions(options)
        statusMessage = permissionGranted ? "辅助功能权限已开启" : "已发起权限申请，请在系统设置中开启"
        permissionGuideController.syncVisibility(permissionGranted: permissionGranted)
    }

    func refreshPermissionStatus() {
        permissionGranted = AXIsProcessTrusted()
        statusMessage = permissionGranted ? "权限状态正常，可以开始划词" : "辅助功能权限仍未开启"
        permissionGuideController.syncVisibility(permissionGranted: permissionGranted)
    }

    func showPermissionGuide() {
        permissionGuideController.present()
    }

    func availableModels() -> [DeepSeekService.Model] {
        DeepSeekService.Model.allCases
    }

    static func normalizedAPIKey(from storedValue: String?) -> String {
        let trimmed = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.hasPrefix("sk-") else {
            return ""
        }
        return trimmed
    }

    static func persistableAPIKey(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func loadInitialAPIKey(
        store: any APIKeyStoring,
        legacyDefaults: UserDefaults
    ) -> String {
        do {
            if let storedValue = try store.load() {
                let normalized = normalizedAPIKey(from: storedValue)
                if !normalized.isEmpty {
                    legacyDefaults.removeObject(forKey: legacyAPIKeyStorageKey)
                    if normalized != storedValue {
                        try? store.save(normalized)
                    }
                    return normalized
                }

                try? store.delete()
            }
        } catch {
            // A Keychain read error must not delete the legacy fallback. Migration
            // can retry on the next launch instead of losing the only persisted key.
        }

        let legacyValue = legacyDefaults.string(forKey: legacyAPIKeyStorageKey)
        let normalizedLegacyValue = normalizedAPIKey(from: legacyValue)
        guard !normalizedLegacyValue.isEmpty else {
            legacyDefaults.removeObject(forKey: legacyAPIKeyStorageKey)
            return ""
        }

        do {
            try store.save(normalizedLegacyValue)
            legacyDefaults.removeObject(forKey: legacyAPIKeyStorageKey)
        } catch {
            // Migration is best-effort. Keep the legacy value so a failed Keychain
            // write does not silently erase the user's only persisted credential.
        }
        return normalizedLegacyValue
    }

    @discardableResult
    static func persistAPIKey(
        _ value: String,
        store: any APIKeyStoring,
        legacyDefaults: UserDefaults
    ) -> Bool {
        guard let persistedAPIKey = persistableAPIKey(from: value) else {
            legacyDefaults.removeObject(forKey: legacyAPIKeyStorageKey)
            do {
                try store.delete()
                return true
            } catch {
                return false
            }
        }

        do {
            try store.save(persistedAPIKey)
            legacyDefaults.removeObject(forKey: legacyAPIKeyStorageKey)
            return true
        } catch {
            return false
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func showToolbar(for text: String, at point: NSPoint) {
        guard permissionGranted else {
            statusMessage = "检测到划词，但当前没有辅助功能权限"
            return
        }

        statusMessage = "已捕获划词内容"
        panelController.show(
            text: text,
            at: point,
            service: deepSeekService
        )
    }

    private func handleSelectionMissed() {
        guard permissionGranted else { return }
        statusMessage = "检测到鼠标选中动作，但当前应用未返回可读取的选中文本"
    }
}
