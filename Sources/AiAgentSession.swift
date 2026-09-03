import Combine
import Foundation

@MainActor
final class AiAgentSession: ObservableObject {
    typealias Complete = ([AiMessage]) async throws -> String

    @Published private(set) var messages: [AiMessage] = []
    @Published private(set) var currentAction: AiToolAction?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private enum RetryPlan {
        case currentContext
        case appendUser(String)
        case regenerate(requestMessages: [AiMessage], replacingAssistantID: UUID)
    }

    private enum SuccessCommit {
        case appendAssistant
        case replaceAssistant(UUID)
    }

    private let complete: Complete
    private var generation = 0
    private var currentTask: Task<Void, Never>?
    private var retryPlan: RetryPlan?

    init(service: DeepSeekService) {
        self.complete = { messages in
            try await service.complete(messages: messages)
        }
    }

    init(complete: @escaping Complete) {
        self.complete = complete
    }

    var visibleMessages: [AiMessage] {
        messages.filter(\.isVisible)
    }

    var lastAssistantContent: String? {
        guard let lastMessage = messages.last,
              lastMessage.role == .assistant,
              lastMessage.isVisible else {
            return nil
        }
        return lastMessage.content
    }

    var canRetry: Bool {
        !isLoading && currentAction != nil && (errorMessage != nil || lastAssistantContent != nil)
    }

    func clear() {
        invalidateCurrentRequest()
        messages = []
        currentAction = nil
        errorMessage = nil
        retryPlan = nil
    }

    func cancel() {
        invalidateCurrentRequest()
    }

    func runToolAction(_ action: AiToolAction, sourceText: String) {
        guard action != .copy else { return }

        invalidateCurrentRequest()
        currentAction = action
        errorMessage = nil
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
            case .regenerate(let requestMessages, let replacingAssistantID):
                let plan = RetryPlan.regenerate(
                    requestMessages: requestMessages,
                    replacingAssistantID: replacingAssistantID
                )
                startRequest(
                    requestMessages: requestMessages,
                    rollbackUserID: nil,
                    failurePlan: plan,
                    successCommit: .replaceAssistant(replacingAssistantID)
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
            replacingAssistantID: lastMessage.id
        )
        startRequest(
            requestMessages: requestMessages,
            rollbackUserID: nil,
            failurePlan: plan,
            successCommit: .replaceAssistant(lastMessage.id)
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
        let performer = complete

        isLoading = true
        errorMessage = nil
        retryPlan = nil

        currentTask = Task { [weak self] in
            do {
                let output = try await performer(requestMessages)
                guard !Task.isCancelled,
                      let self,
                      self.generation == requestGeneration else {
                    return
                }

                switch successCommit {
                case .appendAssistant:
                    self.messages.append(
                        AiMessage(role: .assistant, content: output)
                    )
                case .replaceAssistant(let assistantID):
                    let replacement = AiMessage(
                        id: assistantID,
                        role: .assistant,
                        content: output
                    )
                    if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                        self.messages[index] = replacement
                    } else {
                        self.messages.append(replacement)
                    }
                }

                self.isLoading = false
                self.currentTask = nil
                self.errorMessage = nil
                self.retryPlan = nil
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.generation == requestGeneration else {
                    return
                }

                if let rollbackUserID {
                    self.messages.removeAll(where: { $0.id == rollbackUserID })
                }
                self.isLoading = false
                self.currentTask = nil
                self.errorMessage = error.localizedDescription
                self.retryPlan = failurePlan
            }
        }
    }

    private func invalidateCurrentRequest() {
        generation += 1
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
}
