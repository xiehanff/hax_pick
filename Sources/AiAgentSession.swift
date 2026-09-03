import Combine
import Foundation

@MainActor
final class AiAgentSession: ObservableObject {
    typealias Stream = ([AiMessage]) -> AsyncThrowingStream<String, Error>
    typealias Complete = ([AiMessage]) async throws -> String

    @Published private(set) var messages: [AiMessage] = []
    @Published private(set) var currentAction: AiToolAction?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didStop = false

    private(set) var draftPublishCount = 0

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

    private let stream: Stream
    private let publishIntervalNanoseconds: UInt64
    private var generation = 0
    private var currentTask: Task<Void, Never>?
    private var retryPlan: RetryPlan?
    private var activeRequest: ActiveRequest?
    private var activeDraftContent = ""

    init(service: DeepSeekService) {
        self.stream = { messages in
            service.stream(messages: messages)
        }
        self.publishIntervalNanoseconds = 40_000_000
    }

    init(
        stream: @escaping Stream,
        publishIntervalNanoseconds: UInt64 = 40_000_000
    ) {
        self.stream = stream
        self.publishIntervalNanoseconds = publishIntervalNanoseconds
    }

    init(complete: @escaping Complete) {
        self.stream = { messages in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        continuation.yield(try await complete(messages))
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

    var lastAssistantContent: String? {
        guard let lastMessage = messages.last,
              lastMessage.role == .assistant,
              lastMessage.isVisible,
              !lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return lastMessage.content
    }

    var canRetry: Bool {
        !isLoading && currentAction != nil && (retryPlan != nil || lastAssistantContent != nil)
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

    func stopGeneration() {
        guard isLoading, let activeRequest else { return }

        generation += 1
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        errorMessage = nil
        didStop = true

        let partial = activeDraftContent
        if partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rollback(activeRequest)
            retryPlan = activeRequest.failurePlan
        } else {
            publishDraft(
                assistantID: activeRequest.draftAssistantID,
                content: partial,
                originalAssistant: activeRequest.originalAssistant
            )
            retryPlan = nil
        }

        self.activeRequest = nil
        activeDraftContent = ""
    }

    func runToolAction(_ action: AiToolAction, sourceText: String) {
        guard action != .copy else { return }

        abortActiveRequest(rollback: true, preserveRetryPlan: false)
        currentAction = action
        errorMessage = nil
        didStop = false
        retryPlan = nil
        messages = [
            AiMessage(
                role: .system,
                content: AiPrompts.systemPrompt(for: action),
                isVisible: false
            ),
            AiMessage(
                role: .user,
                content: AiPrompts.initialUserPrompt(for: action, text: sourceText),
                isVisible: false
            ),
        ]

        startRequest(rollbackUserID: nil, failurePlan: .currentContext)
    }

    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              currentAction != nil,
              lastAssistantContent != nil,
              !isLoading else {
            return false
        }

        let userMessage = AiMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        startRequest(
            rollbackUserID: userMessage.id,
            failurePlan: .appendUser(trimmed)
        )
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
                startRequest(
                    rollbackUserID: userMessage.id,
                    failurePlan: .appendUser(text)
                )
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
              lastMessage.isVisible else {
            return
        }

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

        let requestGeneration = generation
        let requestMessages = explicitRequestMessages ?? messages
        let performer = stream
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
        draftPublishCount = 0
        isLoading = true
        errorMessage = nil
        didStop = false
        retryPlan = nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            var lastPublish = DispatchTime.now().uptimeNanoseconds

            do {
                for try await chunk in performer(requestMessages) {
                    guard !Task.isCancelled, self.generation == requestGeneration else {
                        return
                    }

                    accumulated += chunk
                    self.activeDraftContent = accumulated

                    let now = DispatchTime.now().uptimeNanoseconds
                    if self.publishIntervalNanoseconds == 0 ||
                        now &- lastPublish >= self.publishIntervalNanoseconds {
                        self.publishDraft(
                            assistantID: draftAssistantID,
                            content: accumulated,
                            originalAssistant: originalAssistant
                        )
                        lastPublish = now
                    }
                }

                guard !Task.isCancelled,
                      self.generation == requestGeneration else {
                    return
                }

                let finalContent = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !finalContent.isEmpty else {
                    throw DeepSeekError.emptyResult
                }

                self.publishDraft(
                    assistantID: draftAssistantID,
                    content: finalContent,
                    originalAssistant: originalAssistant
                )
                self.isLoading = false
                self.currentTask = nil
                self.errorMessage = nil
                self.didStop = false
                self.retryPlan = nil
                self.activeRequest = nil
                self.activeDraftContent = ""
            } catch {
                guard !Task.isCancelled,
                      self.generation == requestGeneration else {
                    return
                }

                self.rollback(request)
                self.isLoading = false
                self.currentTask = nil
                self.errorMessage = error.localizedDescription
                self.didStop = false
                self.retryPlan = failurePlan
                self.activeRequest = nil
                self.activeDraftContent = ""
            }
        }
    }

    private func publishDraft(
        assistantID: UUID,
        content: String,
        originalAssistant: AiMessage?
    ) {
        draftPublishCount += 1

        let updated = AiMessage(
            id: assistantID,
            role: .assistant,
            content: content
        )

        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index] = updated
        } else if originalAssistant == nil {
            messages.append(updated)
        }
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

        if shouldRollback, let activeRequest {
            rollback(activeRequest)
        }

        isLoading = false
        activeRequest = nil
        activeDraftContent = ""
        if !preserveRetryPlan {
            retryPlan = nil
        }
    }
}
