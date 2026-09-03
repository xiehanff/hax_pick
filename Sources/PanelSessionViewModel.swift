import SwiftUI

@MainActor
final class PanelSessionViewModel: ObservableObject {
    typealias PerformAction = (
        DeepSeekService.ToolAction,
        String,
        String?,
        String?
    ) async throws -> String

    enum PanelMode {
        case toolbar
        case result
    }

    struct ConversationTurn: Identifiable {
        let id = UUID()
        let question: String?   // nil = 首次操作无用户气泡
        let answer: String
    }

    @Published private(set) var mode: PanelMode = .toolbar
    @Published private(set) var selectedText = ""
    @Published private(set) var currentAction: DeepSeekService.ToolAction?
    @Published private(set) var conversationTurns: [ConversationTurn] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusHint = "请选择动作"
    @Published var followUpInput = ""
    @Published var isOriginalExpanded = false
    var onModeChanged: ((PanelMode) -> Void)?

    private let performAction: PerformAction
    private let onClose: () -> Void
    private var requestGeneration = 0
    private var currentTask: Task<Void, Never>?
    private var isDismissed = false

    init(service: DeepSeekService, onClose: @escaping () -> Void) {
        self.performAction = { action, text, previousResult, followUp in
            try await service.perform(
                action: action,
                text: text,
                previousResult: previousResult,
                followUp: followUp
            )
        }
        self.onClose = onClose
    }

    init(performAction: @escaping PerformAction, onClose: @escaping () -> Void) {
        self.performAction = performAction
        self.onClose = onClose
    }

    var titleText: String {
        guard let currentAction else { return "划词助手" }
        return currentAction.resultTitle
    }

    var canSubmitFollowUp: Bool {
        !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var suggestions: [String] {
        guard let currentAction else { return [] }
        return currentAction.suggestions
    }

    func reset(with text: String) {
        invalidateCurrentRequest()
        isDismissed = false
        selectedText = text
        currentAction = nil
        conversationTurns = []
        statusHint = "请选择动作"
        followUpInput = ""
        isOriginalExpanded = false
        isLoading = false
        mode = .toolbar
        onModeChanged?(.toolbar)
    }

    func handlePrimaryAction(_ action: DeepSeekService.ToolAction) {
        guard !isDismissed else { return }
        switch action {
        case .copy:
            copyOriginalText()
            close()
        default:
            mode = .result
            onModeChanged?(.result)
            run(action: action, followUp: nil)
        }
    }

    func run(action: DeepSeekService.ToolAction, followUp: String?) {
        guard !isDismissed, !isLoading else { return }
        currentAction = action
        isLoading = true
        statusHint = "正在生成..."

        let generation = requestGeneration
        let originalText = selectedText
        let priorResult = conversationTurns.last?.answer
        let performer = performAction

        currentTask = Task { [weak self] in
            do {
                let output = try await performer(
                    action,
                    originalText,
                    priorResult,
                    followUp
                )
                guard !Task.isCancelled,
                      let self,
                      self.requestGeneration == generation,
                      !self.isDismissed else {
                    return
                }

                let turn = ConversationTurn(question: followUp, answer: output)
                self.conversationTurns.append(turn)
                self.isLoading = false
                self.statusHint = "生成完成"
                self.currentTask = nil
                if followUp != nil {
                    self.followUpInput = ""
                }
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.requestGeneration == generation,
                      !self.isDismissed else {
                    return
                }

                let errorMessage = error.localizedDescription
                let turn = ConversationTurn(question: followUp, answer: errorMessage)
                self.conversationTurns.append(turn)
                self.isLoading = false
                self.statusHint = "请求失败，可重试"
                self.currentTask = nil
            }
        }
    }

    func retry() {
        guard !isDismissed,
              let currentAction,
              let lastTurn = conversationTurns.last else {
            return
        }
        conversationTurns.removeLast()
        run(action: currentAction, followUp: lastTurn.question)
    }

    func submitFollowUp() {
        let text = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDismissed, let currentAction, !text.isEmpty else { return }
        run(action: currentAction, followUp: text)
    }

    func askSuggestion(_ suggestion: String) {
        guard !isDismissed, let currentAction else { return }
        run(action: currentAction, followUp: suggestion)
    }

    func copyOriginalText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    func copyResult() {
        guard let lastAnswer = conversationTurns.last?.answer, !lastAnswer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    func toggleOriginalExpanded() {
        isOriginalExpanded.toggle()
    }

    @discardableResult
    func prepareForDismissal() -> Bool {
        guard !isDismissed else { return false }
        isDismissed = true
        invalidateCurrentRequest()
        isLoading = false
        return true
    }

    func close() {
        onClose()
    }

    private func invalidateCurrentRequest() {
        requestGeneration += 1
        currentTask?.cancel()
        currentTask = nil
    }
}
