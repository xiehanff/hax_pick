import XCTest
@testable import HaxPickApp

@MainActor
final class AiAgentSessionTests: XCTestCase {
    func testMultiTurnRequestsContainCompleteConversationHistory() async throws {
        let responder = ScriptedResponder(outcomes: [
            .success("A0"),
            .success("A1"),
            .success("A2"),
            .success("A3"),
        ])
        let session = makeSession(responder: responder)

        session.runToolAction(.explain, sourceText: "source")
        try await waitUntil { session.lastAssistantContent == "A0" }

        XCTAssertTrue(session.sendMessage("Q1"))
        try await waitUntil { session.lastAssistantContent == "A1" }

        XCTAssertTrue(session.sendMessage("Q2"))
        try await waitUntil { session.lastAssistantContent == "A2" }

        XCTAssertTrue(session.sendMessage("Q3"))
        try await waitUntil { session.lastAssistantContent == "A3" }

        XCTAssertEqual(responder.requests.count, 4)
        XCTAssertEqual(
            responder.requests[0].map(\.role),
            [.system, .user]
        )
        XCTAssertEqual(
            responder.requests[1].map(\.role),
            [.system, .user, .assistant, .user]
        )
        XCTAssertEqual(
            responder.requests[2].map(\.role),
            [.system, .user, .assistant, .user, .assistant, .user]
        )
        XCTAssertEqual(
            responder.requests[3].map(\.role),
            [.system, .user, .assistant, .user, .assistant, .user, .assistant, .user]
        )
        XCTAssertTrue(responder.requests[0][1].content.contains("source"))
        XCTAssertEqual(responder.requests[1].last?.content, "Q1")
        XCTAssertEqual(responder.requests[2].last?.content, "Q2")
        XCTAssertEqual(responder.requests[3].last?.content, "Q3")
        XCTAssertEqual(
            session.visibleMessages.map(\.content),
            ["A0", "Q1", "A1", "Q2", "A2", "Q3", "A3"]
        )
    }

    func testStreamingChunksAreCoalescedUntilFinalFlushWhenThrottleWindowHasNotElapsed() async throws {
        let responder = DeferredStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: .max
        )

        session.runToolAction(.translate, sourceText: "hello")
        try await waitUntil { responder.hasPendingStream }

        responder.yield("你")
        responder.yield("好")
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(session.isLoading)
        XCTAssertEqual(session.visibleMessages.count, 1)
        XCTAssertEqual(session.visibleMessages.first?.content, "")

        responder.finish()
        try await waitUntil { !session.isLoading }

        XCTAssertEqual(session.lastAssistantContent, "你好")
        XCTAssertEqual(session.visibleMessages.map(\.content), ["你好"])
    }

    func testStopGenerationKeepsPublishedPartialResponse() async throws {
        let responder = DeferredStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )

        session.runToolAction(.summarize, sourceText: "source")
        try await waitUntil { responder.hasPendingStream }

        responder.yield("partial")
        try await waitUntil { session.lastAssistantContent == "partial" }

        session.stopGeneration()

        XCTAssertFalse(session.isLoading)
        XCTAssertTrue(session.didStop)
        XCTAssertEqual(session.lastAssistantContent, "partial")
        XCTAssertTrue(session.canRetry)
    }

    func testStopBeforeFirstChunkRollsBackDraftAndAllowsRetry() async throws {
        let responder = DeferredStreamResponder()
        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )

        session.runToolAction(.explain, sourceText: "source")
        try await waitUntil { responder.hasPendingStream }

        session.stopGeneration()

        XCTAssertFalse(session.isLoading)
        XCTAssertTrue(session.didStop)
        XCTAssertTrue(session.visibleMessages.isEmpty)
        XCTAssertTrue(session.canRetry)
        XCTAssertNil(session.lastAssistantContent)
    }

    func testInitialFailureRequiresRetryBeforeFollowUp() async throws {
        let responder = ScriptedResponder(outcomes: [
            .failure("temporary failure"),
            .success("recovered"),
        ])
        let session = makeSession(responder: responder)

        session.runToolAction(.explain, sourceText: "source")
        try await waitUntil { session.errorMessage != nil && !session.isLoading }

        XCTAssertTrue(session.visibleMessages.isEmpty)
        XCTAssertFalse(session.sendMessage("follow up"))
        XCTAssertEqual(session.messages.map(\.role), [.system, .user])
        XCTAssertEqual(responder.requests.count, 1)

        session.retry()
        try await waitUntil { session.lastAssistantContent == "recovered" }

        XCTAssertEqual(session.visibleMessages.map(\.content), ["recovered"])
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(responder.requests.count, 2)
        XCTAssertEqual(
            responder.requests[0].map(\.content),
            responder.requests[1].map(\.content)
        )
    }

    func testFailedFollowUpRollsBackUserAndDoesNotPolluteHistory() async throws {
        let responder = ScriptedResponder(outcomes: [
            .success("initial"),
            .failure("network down"),
            .success("retry answer"),
        ])
        let session = makeSession(responder: responder)

        session.runToolAction(.translate, sourceText: "hello")
        try await waitUntil { session.lastAssistantContent == "initial" }

        XCTAssertTrue(session.sendMessage("why"))
        try await waitUntil { session.errorMessage != nil && !session.isLoading }

        XCTAssertEqual(session.visibleMessages.map(\.content), ["initial"])
        XCTAssertEqual(session.lastAssistantContent, "initial")
        XCTAssertFalse(session.messages.contains(where: { $0.content == "network down" }))

        session.retry()
        try await waitUntil { session.lastAssistantContent == "retry answer" }

        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(
            session.visibleMessages.map(\.content),
            ["initial", "why", "retry answer"]
        )
        XCTAssertEqual(responder.requests.count, 3)
        XCTAssertEqual(responder.requests[1].last?.content, "why")
        XCTAssertEqual(responder.requests[2].last?.content, "why")
        XCTAssertEqual(responder.requests[1].count, responder.requests[2].count)
    }

    func testRegenerateDoesNotDuplicateSuccessfulUserMessage() async throws {
        let responder = ScriptedResponder(outcomes: [
            .success("initial"),
            .success("first answer"),
            .success("regenerated answer"),
        ])
        let session = makeSession(responder: responder)

        session.runToolAction(.explain, sourceText: "source")
        try await waitUntil { session.lastAssistantContent == "initial" }

        XCTAssertTrue(session.sendMessage("Q1"))
        try await waitUntil { session.lastAssistantContent == "first answer" }

        session.retry()
        try await waitUntil {
            session.visibleMessages.last?.content == "regenerated answer"
        }

        XCTAssertEqual(
            session.visibleMessages.map(\.content),
            ["initial", "Q1", "regenerated answer"]
        )
        XCTAssertEqual(
            session.visibleMessages.filter { $0.role == .user && $0.content == "Q1" }.count,
            1
        )
        XCTAssertEqual(responder.requests[2].last?.content, "Q1")
        XCTAssertFalse(responder.requests[2].contains(where: { $0.content == "first answer" }))
    }

    func testFailedRegenerationPreservesPreviousAssistantAndRetryUsesSameSnapshot() async throws {
        let responder = ScriptedResponder(outcomes: [
            .success("initial"),
            .success("first answer"),
            .failure("regenerate failed"),
            .success("regenerated answer"),
        ])
        let session = makeSession(responder: responder)

        session.runToolAction(.explain, sourceText: "source")
        try await waitUntil { session.lastAssistantContent == "initial" }

        XCTAssertTrue(session.sendMessage("Q1"))
        try await waitUntil { session.lastAssistantContent == "first answer" }

        session.retry()
        try await waitUntil { session.errorMessage != nil && !session.isLoading }

        XCTAssertEqual(
            session.visibleMessages.map(\.content),
            ["initial", "Q1", "first answer"]
        )
        XCTAssertEqual(session.lastAssistantContent, "first answer")
        XCTAssertEqual(responder.requests.count, 3)
        XCTAssertEqual(responder.requests[2].last?.content, "Q1")
        XCTAssertFalse(responder.requests[2].contains(where: { $0.content == "first answer" }))

        session.retry()
        try await waitUntil {
            session.visibleMessages.last?.content == "regenerated answer"
        }

        XCTAssertEqual(
            session.visibleMessages.map(\.content),
            ["initial", "Q1", "regenerated answer"]
        )
        XCTAssertEqual(responder.requests.count, 4)
        XCTAssertEqual(
            responder.requests[2].map(\.content),
            responder.requests[3].map(\.content)
        )
    }

    func testClearPreventsLateResultFromEnteringNewSession() async throws {
        let responder = DeferredResponder()
        let session = AiAgentSession(complete: { messages in
            try await responder.complete(messages)
        })

        session.runToolAction(.summarize, sourceText: "old")
        try await waitUntil { responder.pendingCount == 1 }

        session.clear()
        responder.succeed("old-result")

        session.runToolAction(.summarize, sourceText: "new")
        try await waitUntil { responder.pendingCount == 1 }
        responder.succeed("new-result")
        try await waitUntil { session.lastAssistantContent == "new-result" }

        XCTAssertEqual(session.visibleMessages.map(\.content), ["new-result"])
        XCTAssertFalse(session.messages.contains(where: { $0.content == "old-result" }))
    }

    private func makeSession(responder: ScriptedResponder) -> AiAgentSession {
        AiAgentSession(complete: { messages in
            try await responder.complete(messages)
        })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
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
private final class ScriptedResponder {
    enum Outcome {
        case success(String)
        case failure(String)
    }

    private(set) var requests: [[AiMessage]] = []
    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func complete(_ messages: [AiMessage]) async throws -> String {
        requests.append(messages)
        guard !outcomes.isEmpty else {
            throw StubError(message: "Missing scripted outcome")
        }

        switch outcomes.removeFirst() {
        case .success(let value):
            return value
        case .failure(let message):
            throw StubError(message: message)
        }
    }
}

private final class DeferredStreamResponder {
    private(set) var requests: [[AiMessage]] = []
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    var hasPendingStream: Bool {
        continuation != nil
    }

    func stream(_ messages: [AiMessage]) -> AsyncThrowingStream<String, Error> {
        requests.append(messages)
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ chunk: String) {
        continuation?.yield(chunk)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}

@MainActor
private final class DeferredResponder {
    private var continuations: [CheckedContinuation<String, Error>] = []

    var pendingCount: Int {
        continuations.count
    }

    func complete(_ messages: [AiMessage]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func succeed(_ value: String) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: value)
    }
}

private struct StubError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
