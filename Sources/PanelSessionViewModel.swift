import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelSessionViewModel: ObservableObject {
    enum PanelMode {
        case toolbar
        case result
    }

    @Published private(set) var mode: PanelMode = .toolbar
    @Published private(set) var selectedText = ""
    @Published var followUpInput = ""
    @Published var isOriginalExpanded = false
    var onModeChanged: ((PanelMode) -> Void)?

    private let aiSession: AiAgentSession
    private let onClose: () -> Void
    private var agentObservation: AnyCancellable?
    private var isDismissed = false

    init(service: DeepSeekService, onClose: @escaping () -> Void) {
        self.aiSession = AiAgentSession(service: service)
        self.onClose = onClose
        observeAgentSession()
    }

    init(aiSession: AiAgentSession, onClose: @escaping () -> Void) {
        self.aiSession = aiSession
        self.onClose = onClose
        observeAgentSession()
    }

    var currentAction: AiToolAction? {
        aiSession.currentAction
    }

    var conversationMessages: [AiMessage] {
        aiSession.visibleMessages
    }

    var lastAssistantContent: String? {
        aiSession.lastAssistantContent
    }

    var isLoading: Bool {
        aiSession.isLoading
    }

    var errorMessage: String? {
        aiSession.errorMessage
    }

    var didStop: Bool {
        aiSession.didStop
    }

    var canRetry: Bool {
        aiSession.canRetry
    }

    var canStop: Bool {
        aiSession.canStop
    }

    var titleText: String {
        currentAction?.resultTitle ?? "划词助手"
    }

    var statusHint: String {
        if isLoading {
            return "正在生成..."
        }
        if didStop {
            return "已停止，可继续使用当前结果"
        }
        if errorMessage != nil {
            return "请求失败，可重试"
        }
        if lastAssistantContent != nil {
            return "生成完成"
        }
        return "请选择动作"
    }

    var canSubmitFollowUp: Bool {
        lastAssistantContent != nil &&
            !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoading
    }

    var suggestions: [String] {
        guard !isLoading, lastAssistantContent != nil else { return [] }
        return currentAction?.suggestions ?? []
    }

    func reset(with text: String) {
        aiSession.clear()
        isDismissed = false
        selectedText = text
        followUpInput = ""
        isOriginalExpanded = false
        mode = .toolbar
        onModeChanged?(.toolbar)
    }

    func handlePrimaryAction(_ action: AiToolAction) {
        guard !isDismissed else { return }
        switch action {
        case .copy:
            copyOriginalText()
            close()
        default:
            mode = .result
            onModeChanged?(.result)
            aiSession.runToolAction(action, sourceText: selectedText)
        }
    }

    func retry() {
        guard !isDismissed else { return }
        aiSession.retry()
    }

    func stopGeneration() {
        guard !isDismissed else { return }
        aiSession.stopGeneration()
    }

    func submitFollowUp() {
        let text = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDismissed, !text.isEmpty else { return }
        if aiSession.sendMessage(text) {
            followUpInput = ""
        }
    }

    func askSuggestion(_ suggestion: String) {
        guard !isDismissed else { return }
        _ = aiSession.sendMessage(suggestion)
    }

    func copyOriginalText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    func copyResult() {
        guard let lastAssistantContent, !lastAssistantContent.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAssistantContent, forType: .string)
    }

    func toggleOriginalExpanded() {
        isOriginalExpanded.toggle()
    }

    @discardableResult
    func prepareForDismissal() -> Bool {
        guard !isDismissed else { return false }
        isDismissed = true
        aiSession.cancel()
        return true
    }

    func close() {
        onClose()
    }

    private func observeAgentSession() {
        agentObservation = aiSession.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
