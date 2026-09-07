import Combine
import Foundation

@MainActor
final class AiAgentSession: ObservableObject {
    typealias Stream = ([AiMessage]) -> AsyncThrowingStream<String, Error>
    typealias Complete = ([AiMessage]) async throws -> String
    typealias ModeAwareStream = ([AiMessage], DeepSeekService.RequestMode) -> AsyncThrowingStream<AiStreamChunk, Error>

    @Published private(set) var messages: [AiMessage] = []
    @Published private(set) var currentAction: AiToolAction?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didStop = false

    private(set) var draftRevision = 0
    private(set) var requestRevision = 0

    private enum RetryPlan {
        case currentContext
        case appendUser(String)
        case regenerate(requestMessages: [AiMessage], replacingAssistant: AiMessage)
    }

    private enum SuccessCommit {
        case appendAssistant
        case replaceAssistant(AiMessage)
    }

    private struct ActiveRequest {
        let draftAssistantID: UUID
        let rollbackUserID: UUID?
        let failurePlan: RetryPlan
        let originalAssistant: AiMessage?
    }

    private let streamWithMode: ModeAwareStream
    private let publishIntervalNanoseconds: UInt64
    private var generation = 0
    private var currentTask: Task<Void, Never>?
    private var pendingDraftPublishTask: Task<Void, Never>?
    private var retryPlan: RetryPlan?
    private var activeRequest: ActiveRequest?
    private var activeDraftContent = ""
    private var activeDraftReasoning = ""
    private var lastDraftPublishNanoseconds: UInt64?

    init(
        service: DeepSeekService,
        historyWindow: AiHistoryWindow = .standard
    ) {
        self.streamWithMode = { messages, mode in
            service.stream(
                messages: historyWindow.requestMessages(from: messages),
                mode: mode
            )
        }
        self.publishIntervalNanoseconds = 40_000_000
    }

    /// 保留文本流测试 seam；生产 transport 使用包含 content/reasoning 的 chunk。
    init(
        stream: @escaping Stream,
        publishIntervalNanoseconds: UInt64 = 40_000_000
    ) {
        self.streamWithMode = { messages, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await text in stream(messages) {
                            continuation.yield(AiStreamChunk(content: text))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        self.publishIntervalNanoseconds = publishIntervalNanoseconds
    }

    init(complete: @escaping Complete) {
        self.streamWithMode = { messages, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        continuation.yield(AiStreamChunk(content: try await complete(messages)))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        self.publishIntervalNanoseconds = 0
    }

    var visibleMessages: [AiMessage] {
        messages.filter(\.isVisible)
    }

    var lastAssistantMessage: AiMessage? {
        messages.last(where: {
            $0.role == .assistant &&
            $0.isVisible &&
            (!$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             !$0.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        })
    }

    var lastAssistantContent: String? {
        guard let lastAssistantMessage,
              !lastAssistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return lastAssistantMessage.content
    }

    var lastAssistantSuggestions: [String] {
        guard !isLoading else { return [] }
        return lastAssistantMessage?.followUpSuggestions ?? []
    }

    var streamingAssistantID: UUID? {
        guard isLoading,
              !activeDraftContent.isEmpty || !activeDraftReasoning.isEmpty else {
            return nil
        }
        return activeRequest?.draftAssistantID
    }

    var canSendMessage: Bool {
        guard !isLoading, let currentAction else { return false }
        return currentAction == .chat || lastAssistantContent != nil
    }

    var canRetry: Bool {
        !isLoading && currentAction != nil && (retryPlan != nil || lastAssistantMessage != nil)
    }

    var canStop: Bool {
        isLoading && activeRequest != nil
    }

    func clear() {
        abortActiveRequest(rollback: true, preserveRetryPlan: false)
        messages = []
        currentAction = nil
        errorMessage = nil
        didStop = false
        retryPlan = nil
    }

    func cancel() {
        abortActiveRequest(rollback: true, preserveRetryPlan: false)
    }

    /// 开启完全独立的自由问答会话。若当前仍有请求，先取消并丢弃其未完成上下文。
    func startFreeChat() {
        abortActiveRequest(rollback: true, preserveRetryPlan: false)
        currentAction = .chat
        errorMessage = nil
        didStop = false
        retryPlan = nil
        messages = [
            AiMessage(
                role: .system,
                content: AiPrompts.systemPrompt(for: .chat),
                isVisible: false
            ),
        ]
    }

    func stopGeneration() {
        guard isLoading, let activeRequest else { return }

        generation += 1
        currentTask?.cancel()
        currentTask = nil
        cancelPendingDraftPublish()
        isLoading = false
        errorMessage = nil
        didStop = true

        let parsed = AiResponseParser.parse(activeDraftContent)
        let hasVisiblePartial =
            !parsed.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !activeDraftReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasVisiblePartial {
            rollback(activeRequest)
            retryPlan = activeRequest.failurePlan
        } else {
            publishDraft(
                assistantID: activeRequest.draftAssistantID,
                rawContent: activeDraftContent,
                reasoning: activeDraftReasoning,
                originalAssistant: activeRequest.originalAssistant
            )
            retryPlan = nil
        }

        self.activeRequest = nil
        activeDraftContent = ""
        activeDraftReasoning = ""
        lastDraftPublishNanoseconds = nil
    }

    func runToolAction(_ action: AiToolAction, sourceText: String) {
        guard action != .copy else { return }
        if action == .chat {
            startFreeChat()
            return
        }

        abortActiveRequest(rollback: true, preserveRetryPlan: false)
        currentAction = action
        errorMessage = nil
        didStop = false
        retryPlan = nil
        messages = [
            AiMessage(role: .system, content: AiPrompts.systemPrompt(for: action), isVisible: false),
            AiMessage(role: .user, content: AiPrompts.initialUserPrompt(for: action, text: sourceText), isVisible: false),
        ]
        startRequest(rollbackUserID: nil, failurePlan: .currentContext)
    }

    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSendMessage else { return false }

        let userMessage = AiMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        startRequest(rollbackUserID: userMessage.id, failurePlan: .appendUser(trimmed))
        return true
    }

    func retry() {
        guard !isLoading, currentAction != nil else { return }

        if let retryPlan {
            switch retryPlan {
            case .currentContext:
                startRequest(rollbackUserID: nil, failurePlan: .currentContext)
            case .appendUser(let text):
                let userMessage = AiMessage(role: .user, content: text)
                messages.append(userMessage)
                startRequest(rollbackUserID: userMessage.id, failurePlan: .appendUser(text))
            case .regenerate(let requestMessages, let replacingAssistant):
                let plan = RetryPlan.regenerate(
                    requestMessages: requestMessages,
                    replacingAssistant: replacingAssistant
                )
                startRequest(
                    requestMessages: requestMessages,
                    rollbackUserID: nil,
                    failurePlan: plan,
                    successCommit: .replaceAssistant(replacingAssistant)
                )
            }
            return
        }

        regenerateLastResponse()
    }

    private func regenerateLastResponse() {
        guard let lastMessage = messages.last,
              lastMessage.role == .assistant,
              lastMessage.isVisible else { return }

        let requestMessages = Array(messages.dropLast())
        let plan = RetryPlan.regenerate(
            requestMessages: requestMessages,
            replacingAssistant: lastMessage
        )
        startRequest(
            requestMessages: requestMessages,
            rollbackUserID: nil,
            failurePlan: plan,
            successCommit: .replaceAssistant(lastMessage)
        )
    }

    private func startRequest(
        requestMessages explicitRequestMessages: [AiMessage]? = nil,
        rollbackUserID: UUID?,
        failurePlan: RetryPlan,
        successCommit: SuccessCommit = .appendAssistant
    ) {
        guard !isLoading else { return }

        requestRevision += 1
        let requestGeneration = generation
        let requestMessages = explicitRequestMessages ?? messages
        let performer = streamWithMode
        let requestMode = requestMode(for: currentAction)
        let draftAssistantID: UUID
        let originalAssistant: AiMessage?

        switch successCommit {
        case .appendAssistant:
            let draft = AiMessage(role: .assistant, content: "")
            draftAssistantID = draft.id
            originalAssistant = nil
            messages.append(draft)
        case .replaceAssistant(let assistant):
            draftAssistantID = assistant.id
            originalAssistant = assistant
        }

        let request = ActiveRequest(
            draftAssistantID: draftAssistantID,
            rollbackUserID: rollbackUserID,
            failurePlan: failurePlan,
            originalAssistant: originalAssistant
        )
        activeRequest = request
        activeDraftContent = ""
        activeDraftReasoning = ""
        lastDraftPublishNanoseconds = nil
        cancelPendingDraftPublish()
        isLoading = true
        errorMessage = nil
        didStop = false
        retryPlan = nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            var accumulatedContent = ""
            var accumulatedReasoning = ""

            do {
                for try await chunk in performer(requestMessages, requestMode) {
                    guard !Task.isCancelled,
                          self.generation == requestGeneration else { return }
                    accumulatedContent += chunk.content
                    accumulatedReasoning += chunk.reasoning
                    self.activeDraftContent = accumulatedContent
                    self.activeDraftReasoning = accumulatedReasoning
                    self.queueDraftPublish(for: requestGeneration)
                }

                guard !Task.isCancelled,
                      self.generation == requestGeneration else { return }

                let parsed = AiResponseParser.parse(accumulatedContent)
                let finalContent = parsed.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !finalContent.isEmpty else { throw DeepSeekError.emptyResult }

                self.cancelPendingDraftPublish()
                self.publishDraft(
                    assistantID: draftAssistantID,
                    rawContent: accumulatedContent,
                    reasoning: accumulatedReasoning,
                    originalAssistant: originalAssistant
                )
                self.finishRequestSuccessfully()
            } catch {
                guard !Task.isCancelled,
                      self.generation == requestGeneration else { return }

                self.cancelPendingDraftPublish()
                self.rollback(request)
                self.isLoading = false
                self.currentTask = nil
                self.errorMessage = error.localizedDescription
                self.didStop = false
                self.retryPlan = failurePlan
                self.activeRequest = nil
                self.activeDraftContent = ""
                self.activeDraftReasoning = ""
                self.lastDraftPublishNanoseconds = nil
            }
        }
    }

    private func requestMode(for action: AiToolAction?) -> DeepSeekService.RequestMode {
        switch action {
        case .translate:
            return .translation
        case .explain:
            return .lowReasoning
        case .deepDive:
            return .deepDive
        default:
            return .standard
        }
    }

    private func queueDraftPublish(for requestGeneration: Int) {
        guard let activeRequest else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        if publishIntervalNanoseconds == 0 || lastDraftPublishNanoseconds == nil {
            cancelPendingDraftPublish()
            publishDraft(
                assistantID: activeRequest.draftAssistantID,
                rawContent: activeDraftContent,
                reasoning: activeDraftReasoning,
                originalAssistant: activeRequest.originalAssistant
            )
            lastDraftPublishNanoseconds = now
            return
        }

        guard pendingDraftPublishTask == nil,
              let lastDraftPublishNanoseconds else { return }

        let elapsed = now &- lastDraftPublishNanoseconds
        if elapsed >= publishIntervalNanoseconds {
            publishDraft(
                assistantID: activeRequest.draftAssistantID,
                rawContent: activeDraftContent,
                reasoning: activeDraftReasoning,
                originalAssistant: activeRequest.originalAssistant
            )
            self.lastDraftPublishNanoseconds = now
            return
        }

        let delay = publishIntervalNanoseconds - elapsed
        let draftAssistantID = activeRequest.draftAssistantID
        let originalAssistant = activeRequest.originalAssistant

        pendingDraftPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.generation == requestGeneration,
                  self.isLoading,
                  self.activeRequest?.draftAssistantID == draftAssistantID else { return }

            self.pendingDraftPublishTask = nil
            self.publishDraft(
                assistantID: draftAssistantID,
                rawContent: self.activeDraftContent,
                reasoning: self.activeDraftReasoning,
                originalAssistant: originalAssistant
            )
            self.lastDraftPublishNanoseconds = DispatchTime.now().uptimeNanoseconds
        }
    }

    private func publishDraft(
        assistantID: UUID,
        rawContent: String,
        reasoning: String,
        originalAssistant: AiMessage?
    ) {
        let parsed = AiResponseParser.parse(rawContent)
        let updated = AiMessage(
            id: assistantID,
            role: .assistant,
            content: parsed.content,
            reasoning: reasoning,
            followUpSuggestions: parsed.followUpSuggestions
        )

        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            guard messages[index] != updated else { return }
            draftRevision += 1
            messages[index] = updated
        } else if originalAssistant == nil {
            draftRevision += 1
            messages.append(updated)
        }
    }

    private func finishRequestSuccessfully() {
        isLoading = false
        currentTask = nil
        errorMessage = nil
        didStop = false
        retryPlan = nil
        activeRequest = nil
        activeDraftContent = ""
        activeDraftReasoning = ""
        lastDraftPublishNanoseconds = nil
    }

    private func rollback(_ request: ActiveRequest) {
        if let originalAssistant = request.originalAssistant,
           let index = messages.firstIndex(where: { $0.id == originalAssistant.id }) {
            messages[index] = originalAssistant
        } else {
            messages.removeAll(where: { $0.id == request.draftAssistantID })
        }

        if let rollbackUserID = request.rollbackUserID {
            messages.removeAll(where: { $0.id == rollbackUserID })
        }
    }

    private func abortActiveRequest(
        rollback shouldRollback: Bool,
        preserveRetryPlan: Bool
    ) {
        generation += 1
        currentTask?.cancel()
        currentTask = nil
        cancelPendingDraftPublish()

        if shouldRollback, let activeRequest { rollback(activeRequest) }

        isLoading = false
        activeRequest = nil
        activeDraftContent = ""
        activeDraftReasoning = ""
        lastDraftPublishNanoseconds = nil
        if !preserveRetryPlan { retryPlan = nil }
    }

    private func cancelPendingDraftPublish() {
        pendingDraftPublishTask?.cancel()
        pendingDraftPublishTask = nil
    }
}
