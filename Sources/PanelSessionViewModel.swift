import SwiftUI

@MainActor
final class PanelSessionViewModel: ObservableObject {
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

    private let service: DeepSeekService
    private let onClose: () -> Void

    init(service: DeepSeekService, onClose: @escaping () -> Void) {
        self.service = service
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
        guard !isLoading else { return }
        currentAction = action
        isLoading = true
        statusHint = "正在生成..."

        let priorResult = conversationTurns.last?.answer
        Task {
            do {
                let output = try await service.perform(
                    action: action,
                    text: selectedText,
                    previousResult: priorResult,
                    followUp: followUp
                )
                await MainActor.run {
                    let turn = ConversationTurn(question: followUp, answer: output)
                    self.conversationTurns.append(turn)
                    self.isLoading = false
                    self.statusHint = "生成完成"
                    if followUp != nil {
                        self.followUpInput = ""
                    }
                }
            } catch {
                await MainActor.run {
                    let errorMessage = error.localizedDescription
                    let turn = ConversationTurn(question: followUp, answer: errorMessage)
                    self.conversationTurns.append(turn)
                    self.isLoading = false
                    self.statusHint = "请求失败，可重试"
                }
            }
        }
    }

    func retry() {
        guard let currentAction, let lastTurn = conversationTurns.last else { return }
        conversationTurns.removeLast()
        run(action: currentAction, followUp: lastTurn.question)
    }

    func submitFollowUp() {
        let text = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentAction, !text.isEmpty else { return }
        run(action: currentAction, followUp: text)
    }

    func askSuggestion(_ suggestion: String) {
        guard let currentAction else { return }
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

    func close() {
        onClose()
    }
}
