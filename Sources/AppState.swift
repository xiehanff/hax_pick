import AppKit
import Combine

enum APIKeyStorageState: Equatable {
    case local
    case empty
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private static let apiKeyStorageKey = "deepseek_api_key"
    private static let modelStorageKey = "deepseek_model"

    @Published private(set) var apiKey: String
    @Published private(set) var apiKeyStorageState: APIKeyStorageState

    @Published var selectedModel: DeepSeekService.Model {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.modelStorageKey)
        }
    }

    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var statusMessage = "准备就绪"
    @Published private(set) var permissionRepairError: String?
    @Published private(set) var apiKeyStorageError: String?

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

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
    private var permissionPollTimer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedKey = Self.normalizedAPIKey(from: defaults.string(forKey: Self.apiKeyStorageKey))
        self.apiKey = storedKey
        self.apiKeyStorageState = storedKey.isEmpty ? .empty : .local
        self.selectedModel = DeepSeekService.Model(
            rawValue: defaults.string(forKey: Self.modelStorageKey) ?? ""
        ) ?? .flash

        panelController.onDismissSelection = { [weak self] text in
            self?.selectionMonitor.ignoreCurrentSelection(text)
        }
    }

    var apiKeyStorageStatusMessage: String {
        switch apiKeyStorageState {
        case .local:
            return "Key 已保存在本地缓存。"
        case .empty:
            return "尚未配置 API Key，保存后会写入本地缓存。"
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)

        permissionGranted = AXIsProcessTrusted()
        installPermissionMonitoring()
        selectionMonitor.start()

        if permissionGranted {
            statusMessage = "已开始监听划词"
        } else {
            statusMessage = "需要开启辅助功能权限"
            startPermissionPollingIfNeeded()
            permissionGuideController.presentIfNeeded()
        }
    }

    func refreshPermissionStatus() {
        permissionRepairError = nil
        permissionGranted = AXIsProcessTrusted()
        statusMessage = permissionGranted ? "权限状态正常，可以开始划词" : "当前进程仍未获得辅助功能权限"

        if permissionGranted {
            stopPermissionPolling()
        } else {
            startPermissionPollingIfNeeded()
        }
        permissionGuideController.syncVisibility(permissionGranted: permissionGranted)
    }

    /// Repairs the common development-time TCC mismatch where System Settings
    /// still shows an older build as enabled but AXIsProcessTrusted() rejects the
    /// newly-built process. This is explicit user action; HaxPick never resets
    /// privacy grants automatically.
    func repairAccessibilityPermission() {
        permissionRepairError = nil
        statusMessage = "正在清理旧的辅助功能权限记录…"

        let bundleID = Bundle.main.bundleIdentifier ?? "com.hax.haxpick"
        Task { [weak self] in
            let errorMessage = await Self.resetAccessibilityPermission(bundleID: bundleID)
            guard let self else { return }

            if let errorMessage {
                self.permissionRepairError = errorMessage
                self.statusMessage = "无法自动重置权限，请稍后重试"
                self.requestAccessibilityPrompt()
                return
            }

            self.permissionGranted = false
            self.statusMessage = "旧权限记录已清除，请重新授权 HaxPick"
            self.startPermissionPollingIfNeeded()
            self.requestAccessibilityPrompt()
        }
    }

    private func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    nonisolated private static func resetAccessibilityPermission(bundleID: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return "无法启动 tccutil：\(error.localizedDescription)"
            }

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return detail?.isEmpty == false
                    ? detail
                    : "tccutil 返回状态 \(process.terminationStatus)"
            }
            return nil
        }.value
    }

    func availableModels() -> [DeepSeekService.Model] {
        DeepSeekService.Model.allCases
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && Self.normalizedAPIKey(from: trimmed).isEmpty {
            apiKeyStorageError = "API Key 格式无效，应以 sk- 开头。"
            return false
        }

        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.apiKeyStorageKey)
        } else {
            defaults.set(trimmed, forKey: Self.apiKeyStorageKey)
        }
        apiKey = trimmed
        apiKeyStorageState = trimmed.isEmpty ? .empty : .local
        apiKeyStorageError = nil
        return true
    }

    static func normalizedAPIKey(from storedValue: String?) -> String {
        let trimmed = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.hasPrefix("sk-") else {
            return ""
        }
        return trimmed
    }


    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func installPermissionMonitoring() {
        guard didBecomeActiveObserver == nil else { return }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatus()
            }
        }
    }

    private func startPermissionPollingIfNeeded() {
        guard !permissionGranted, permissionPollTimer == nil else { return }

        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPermissionStatus()
            }
        }
        permissionPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func pollPermissionStatus() {
        let trustedNow = AXIsProcessTrusted()
        guard trustedNow != permissionGranted else { return }

        permissionGranted = trustedNow
        permissionRepairError = nil
        statusMessage = trustedNow
            ? "辅助功能权限已开启，可以开始划词"
            : "辅助功能权限已关闭"

        if trustedNow {
            stopPermissionPolling()
        }
        permissionGuideController.syncVisibility(permissionGranted: trustedNow)
    }

    private func showToolbar(for text: String, at point: NSPoint) {
        let trustedNow = AXIsProcessTrusted()
        if trustedNow != permissionGranted {
            permissionGranted = trustedNow
            if trustedNow {
                stopPermissionPolling()
            } else {
                startPermissionPollingIfNeeded()
            }
        }
        guard trustedNow else {
            statusMessage = "检测到划词，但当前进程没有辅助功能权限"
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
