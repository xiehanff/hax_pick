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
    /// 重新划词后,上一个对话是否可通过工具栏气泡入口重新进入
    @Published private(set) var hasResumableConversation = false
    var onModeChanged: ((PanelMode) -> Void)?

    private var aiSession: AiAgentSession
    private var archivedConversation: (session: AiAgentSession, sourceText: String)?
    private let makeSession: () -> AiAgentSession
    private let onClose: () -> Void
    private var agentObservation: AnyCancellable?
    private var loadingObservation: AnyCancellable?
    private var isDismissed = false
    private var isStreamingPresentationPaused = false
    private var hasDeferredAgentUpdate = false

    init(service: DeepSeekService, onClose: @escaping () -> Void) {
        self.makeSession = { AiAgentSession(service: service) }
        self.aiSession = makeSession()
        self.onClose = onClose
        observeAgentSession()
    }

    init(
        aiSession: AiAgentSession,
        makeSession: (() -> AiAgentSession)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.aiSession = aiSession
        // 测试专用 init:可注入会话工厂;默认用空会话占位
        self.makeSession = makeSession ?? { AiAgentSession(complete: { _ in "" }) }
        self.onClose = onClose
        observeAgentSession()
    }

    var currentAction: AiToolAction? { aiSession.currentAction }

    var streamingAssistantID: UUID? {
        if let published = aiSession.streamingAssistantID {
            return published
        }
        guard aiSession.isLoading,
              let draft = aiSession.visibleMessages.last(where: { $0.role == .assistant }),
              draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        // New requests append an empty assistant draft before transport starts.
        // Expose that stable draft immediately so reasoning-aware modes can show
        // their disclosure/spinner before the first network token. Regeneration
        // keeps a non-empty previous answer, so it intentionally waits for the
        // first replacement chunk instead of turning old Markdown into a draft.
        return draft.id
    }

    var conversationMessages: [AiMessage] {
        let visible = aiSession.visibleMessages
        guard aiSession.isLoading,
              let streamingAssistantID,
              currentAction == .deepDive || currentAction == .explain else {
            return visible
        }

        return visible.map { message in
            guard message.id == streamingAssistantID,
                  message.role == .assistant else { return message }
            return AiMessage(
                id: message.id,
                role: message.role,
                content: message.content,
                reasoning: message.reasoning,
                followUpSuggestions: message.followUpSuggestions,
                isVisible: message.isVisible,
                expectsReasoning: true
            )
        }
    }

    var lastAssistantContent: String? { aiSession.lastAssistantContent }
    var suggestions: [String] { aiSession.lastAssistantSuggestions }
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
        archiveActiveConversationIfNeeded()
        isDismissed = false
        resetStreamingPresentationState()
        selectedText = text
        followUpInput = ""
        isOriginalExpanded = false
        mode = .toolbar
        onModeChanged?(.toolbar)
    }

    /// 重新划词不销毁正在进行的对话:有内容或仍在生成的会话被归档,
    /// 其请求任务继续在后台跑;空会话直接清空复用。
    private func archiveActiveConversationIfNeeded() {
        let worthKeeping = aiSession.isLoading ||
            aiSession.visibleMessages.contains { !$0.content.isEmpty }
        guard worthKeeping else {
            aiSession.clear()
            return
        }
        archivedConversation = (aiSession, selectedText)
        aiSession = makeSession()
        observeAgentSession()
        hasResumableConversation = true
    }

    /// 工具栏气泡入口:重新进入上一个对话窗,包括仍在生成的会话。
    func resumeArchivedConversation() {
        guard let archived = archivedConversation else { return }
        let currentWorthKeeping = aiSession.isLoading ||
            aiSession.visibleMessages.contains { !$0.content.isEmpty }
        if currentWorthKeeping {
            archivedConversation = (aiSession, selectedText)
        } else {
            archivedConversation = nil
            hasResumableConversation = false
        }
        aiSession = archived.session
        observeAgentSession()
        selectedText = archived.sourceText
        isDismissed = false
        resetStreamingPresentationState()
        mode = .result
        onModeChanged?(.result)
        objectWillChange.send()
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