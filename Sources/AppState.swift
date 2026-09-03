import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private static let apiKeyStorageKey = "deepseek_api_key"
    private static let modelStorageKey = "deepseek_model"

    @Published var apiKey: String {
        didSet {
            Self.persistAPIKey(apiKey, defaults: .standard)
        }
    }

    @Published var selectedModel: DeepSeekService.Model {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelStorageKey)
        }
    }

    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var statusMessage = "准备就绪"

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

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

    init() {
        let storedAPIKey = UserDefaults.standard.string(forKey: Self.apiKeyStorageKey)
        let normalizedAPIKey = Self.normalizedAPIKey(from: storedAPIKey)
        self.apiKey = normalizedAPIKey
        if normalizedAPIKey != storedAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) {
            Self.persistAPIKey(normalizedAPIKey, defaults: .standard)
        }
        self.selectedModel = DeepSeekService.Model(rawValue: UserDefaults.standard.string(forKey: Self.modelStorageKey) ?? "") ?? .flash
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

    static func persistAPIKey(_ value: String, defaults: UserDefaults) {
        if let persistedAPIKey = persistableAPIKey(from: value) {
            defaults.set(persistedAPIKey, forKey: apiKeyStorageKey)
        } else {
            defaults.removeObject(forKey: apiKeyStorageKey)
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
