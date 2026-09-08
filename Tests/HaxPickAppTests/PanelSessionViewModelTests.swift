import Combine
import XCTest
@testable import HaxPickApp

@MainActor
final class PanelSessionViewModelTests: XCTestCase {
    func testToolbarExposesPrimaryAIActions() {
        XCTAssertEqual(
            AiToolAction.primaryActions.map(\.rawValue),
            [
                AiToolAction.translate.rawValue,
                AiToolAction.explain.rawValue,
                AiToolAction.deepDive.rawValue,
                AiToolAction.chat.rawValue,
            ]
        )
    }

    func testFreeChatStartsWithoutSelectionAndAcceptsFirstQuestion() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selected source")
        viewModel.handlePrimaryAction(.chat)

        XCTAssertEqual(viewModel.currentAction, .chat)
        XCTAssertEqual(viewModel.statusHint, "等待提问")
        XCTAssertTrue(viewModel.conversationMessages.isEmpty)

        viewModel.followUpInput = "今天想聊点别的"
        XCTAssertTrue(viewModel.canSubmitFollowUp)
        viewModel.submitFollowUp()
        try await waitForPendingRequest(in: responder)

        XCTAssertEqual(responder.requests.last?.map(\.role), [.system, .user])
        XCTAssertEqual(responder.requests.last?.last?.content, "今天想聊点别的")

        responder.succeed("当然可以。")
        try await waitForCompletedAssistant(viewModel, content: "当然可以。")
        XCTAssertEqual(viewModel.conversationMessages.map(\.content), ["今天想聊点别的", "当然可以。"])
    }

    func testPlusCancelsActiveRequestAndStartsFreshFreeChat() async throws {
        let responder = DeferredPanelStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.explain)
        try await waitUntil { responder.hasPendingStream }

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.canStartNewConversation)

        viewModel.startNewConversation()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.currentAction, .chat)
        XCTAssertTrue(viewModel.conversationMessages.isEmpty)
        XCTAssertEqual(viewModel.statusHint, "等待提问")
        XCTAssertEqual(viewModel.followUpInput, "")
    }

    func testResetArchivesLateResultIntoPreviousConversation() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: responder)

        // 重新划词:上一个仍在请求中的对话被归档,迟到结果不进入新会话
        viewModel.reset(with: "selection-b")
        XCTAssertTrue(viewModel.hasResumableConversation)
        responder.succeed("result-a")

        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: responder)
        responder.succeed("result-b")
        try await waitForCompletedAssistant(viewModel, content: "result-b")

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertEqual(viewModel.conversationMessages.map(\.content), ["result-b"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "已完成")

        // 气泡入口应能找回迟到的 result-a
        try await waitUntil { viewModel.hasResumableConversation || true }
        viewModel.resumeArchivedConversation()
        try await waitUntil {
            viewModel.conversationMessages.contains { $0.content == "result-a" }
        }
        XCTAssertEqual(viewModel.selectedText, "selection-a")
    }

    func testDismissalDiscardsLateResultAfterSessionReuse() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: responder)

        XCTAssertTrue(viewModel.prepareForDismissal())
        XCTAssertFalse(viewModel.prepareForDismissal())
        responder.succeed("late-result-a")

        viewModel.reset(with: "selection-b")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: responder)
        responder.succeed("result-b")
        try await waitForCompletedAssistant(viewModel, content: "result-b")

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertEqual(viewModel.conversationMessages.map(\.content), ["result-b"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCurrentRequestStillCommitsNormally() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.summarize)
        try await waitForPendingRequest(in: responder)

        responder.succeed("summary")
        try await waitForCompletedAssistant(viewModel, content: "summary")

        XCTAssertEqual(viewModel.conversationMessages.first?.content, "summary")
        XCTAssertEqual(viewModel.lastAssistantContent, "summary")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "已完成")
    }

    func testDynamicSuggestionsComeFromAssistantResponse() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: responder)
        responder.succeed(
            """
            这是回答。
            <hax_follow_up_suggestions>
            ["给我一个例子", "为什么这里容易误解？"]
            </hax_follow_up_suggestions>
            """
        )
        try await waitForCompletedAssistant(viewModel, content: "这是回答。")

        XCTAssertEqual(viewModel.suggestions, ["给我一个例子", "为什么这里容易误解？"])
        XCTAssertEqual(viewModel.conversationMessages.last?.content, "这是回答。")
    }

    func testStreamingPresentationForwardsEveryPublishedSnapshot() async throws {
        let responder = DeferredPanelStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.explain)
        try await waitUntil { responder.hasPendingStream }

        responder.yield("A")
        try await waitUntil { viewModel.lastAssistantContent == "A" }

        var forwardedUpdates = 0
        let observation = viewModel.objectWillChange.sink {
            forwardedUpdates += 1
        }

        let baseline = forwardedUpdates

        responder.yield("B")
        responder.yield("C")
        try await waitUntil { viewModel.lastAssistantContent == "ABC" }
        await Task.yield()

        XCTAssertGreaterThan(
            forwardedUpdates,
            baseline,
            "阅读历史时仍应持续渲染流式快照，避免回到底部时一次性补齐闪烁"
        )

        responder.finish()
        try await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.lastAssistantContent, "ABC")
        _ = observation
    }

    func testStopBeforeFirstChunkShowsStoppedState() async throws {
        let responder = DeferredPanelStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.explain)
        try await waitUntil { responder.hasPendingStream }

        viewModel.stopGeneration()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.didStop)
        XCTAssertNil(viewModel.lastAssistantContent)
        XCTAssertTrue(viewModel.canRetry)
        XCTAssertEqual(viewModel.statusHint, "已停止")
    }

    private func makeViewModel(responder: DeferredPanelResponder) -> PanelSessionViewModel {
        let session = AiAgentSession(complete: { messages in
            try await responder.complete(messages)
        })
        return PanelSessionViewModel(
            aiSession: session,
            makeSession: {
                AiAgentSession(complete: { messages in
                    try await responder.complete(messages)
                })
            },
            onClose: {}
        )
    }

    private func waitForPendingRequest(in responder: DeferredPanelResponder) async throws {
        for _ in 0..<100 {
            if responder.pendingCount > 0 {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected an AI request to become pending")
        throw TestError.conditionNotMet
    }

    private func waitForCompletedAssistant(
        _ viewModel: PanelSessionViewModel,
        content: String
    ) async throws {
        try await waitUntil {
            !viewModel.isLoading && viewModel.lastAssistantContent == content
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected asynchronous condition to become true")
        throw TestError.conditionNotMet
    }
}

private enum TestError: Error {
    case conditionNotMet
}

@MainActor
private final class DeferredPanelResponder {
    private(set) var requests: [[AiMessage]] = []
    private var continuations: [CheckedContinuation<String, Error>] = []

    var pendingCount: Int {
        continuations.count
    }

    func complete(_ messages: [AiMessage]) async throws -> String {
        requests.append(messages)
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func succeed(_ value: String) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: value)
    }
}

private final class DeferredPanelStreamResponder {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    var hasPendingStream: Bool {
        continuation != nil
    }

    func stream(_ messages: [AiMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ value: String) {
        continuation?.yield(value)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
