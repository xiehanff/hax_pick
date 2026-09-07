import AppKit
import Combine

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
    private var loadingObservation: AnyCancellable?
    private var isDismissed = false
    private var isStreamingPresentationPaused = false
    private var hasDeferredAgentUpdate = false

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

    var currentAction: AiToolAction? { aiSession.currentAction }
    var conversationMessages: [AiMessage] { aiSession.visibleMessages }
    var lastAssistantContent: String? { aiSession.lastAssistantContent }
    var suggestions: [String] { aiSession.lastAssistantSuggestions }
    var streamingAssistantID: UUID? { aiSession.streamingAssistantID }
    var isLoading: Bool { aiSession.isLoading }
    var errorMessage: String? { aiSession.errorMessage }
    var didStop: Bool { aiSession.didStop }
    var canRetry: Bool { aiSession.canRetry }
    var canStop: Bool { aiSession.canStop }
    var draftRevision: Int { aiSession.draftRevision }
    var requestRevision: Int { aiSession.requestRevision }

    var isFreeChat: Bool {
        currentAction == .chat
    }

    var showsSourceTurn: Bool {
        !isFreeChat && !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var titleText: String {
        currentAction?.resultTitle ?? "AI 对话"
    }

    var statusHint: String {
        if isLoading { return "正在生成" }
        if didStop { return "已停止" }
        if errorMessage != nil { return "请求失败" }
        if lastAssistantContent != nil { return "已完成" }
        if isFreeChat { return "等待提问" }
        return "等待开始"
    }

    var canSubmitFollowUp: Bool {
        aiSession.canSendMessage &&
            !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStartNewConversation: Bool {
        currentAction != nil
    }

    func reset(with text: String) {
        aiSession.clear()
        isDismissed = false
        resetStreamingPresentationState()
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
        case .chat:
            resetStreamingPresentationState()
            followUpInput = ""
            isOriginalExpanded = false
            mode = .result
            onModeChanged?(.result)
            aiSession.startFreeChat()
        default:
            resumeStreamingPresentation()
            mode = .result
            onModeChanged?(.result)
            aiSession.runToolAction(action, sourceText: selectedText)
        }
    }

    func retry() {
        guard !isDismissed else { return }
        resumeStreamingPresentation()
        aiSession.retry()
    }

    func stopGeneration() {
        guard !isDismissed else { return }
        aiSession.stopGeneration()
    }

    func startNewConversation() {
        guard !isDismissed else { return }
        resetStreamingPresentationState()
        followUpInput = ""
        isOriginalExpanded = false
        aiSession.startFreeChat()
    }

    func submitFollowUp() {
        let text = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDismissed, !text.isEmpty else { return }
        resumeStreamingPresentation()
        if aiSession.sendMessage(text) {
            followUpInput = ""
        }
    }

    func askSuggestion(_ suggestion: String) {
        guard !isDismissed else { return }
        resumeStreamingPresentation()
        _ = aiSession.sendMessage(suggestion)
    }

    func pauseStreamingPresentation() {
        guard aiSession.isLoading, !isStreamingPresentationPaused else { return }
        isStreamingPresentationPaused = true
        hasDeferredAgentUpdate = false
    }

    func resumeStreamingPresentation() {
        guard isStreamingPresentationPaused else { return }
        isStreamingPresentationPaused = false
        guard hasDeferredAgentUpdate else { return }
        hasDeferredAgentUpdate = false
        objectWillChange.send()
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

    private func resetStreamingPresentationState() {
        isStreamingPresentationPaused = false
        hasDeferredAgentUpdate = false
    }

    private func observeAgentSession() {
        agentObservation = aiSession.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            if self.isStreamingPresentationPaused {
                self.hasDeferredAgentUpdate = true
                return
            }
            self.objectWillChange.send()
        }

        loadingObservation = aiSession.$isLoading
            .removeDuplicates()
            .sink { [weak self] isLoading in
                guard let self, !isLoading, self.isStreamingPresentationPaused else { return }
                self.isStreamingPresentationPaused = false
                guard self.hasDeferredAgentUpdate else { return }
                self.hasDeferredAgentUpdate = false
                self.objectWillChange.send()
            }
    }
}
