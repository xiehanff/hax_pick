import XCTest
@testable import HaxPickApp

@MainActor
final class PanelSessionViewModelTests: XCTestCase {
    func testResetDiscardsLateResultFromPreviousSelection() async throws {
        let responder = DeferredPanelResponder()
        let viewModel = makeViewModel(responder: responder)

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: responder)

        viewModel.reset(with: "selection-b")
        responder.succeed("result-a")

        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: responder)
        responder.succeed("result-b")
        try await waitUntil { viewModel.conversationMessages.count == 1 }

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertEqual(viewModel.conversationMessages.map(\.content), ["result-b"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "生成完成")
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
        try await waitUntil { viewModel.conversationMessages.count == 1 }

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
        try await waitUntil { viewModel.conversationMessages.count == 1 }

        XCTAssertEqual(viewModel.conversationMessages.first?.content, "summary")
        XCTAssertEqual(viewModel.lastAssistantContent, "summary")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "生成完成")
    }

    private func makeViewModel(responder: DeferredPanelResponder) -> PanelSessionViewModel {
        let session = AiAgentSession { messages in
            try await responder.complete(messages)
        }
        return PanelSessionViewModel(aiSession: session, onClose: {})
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

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
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
