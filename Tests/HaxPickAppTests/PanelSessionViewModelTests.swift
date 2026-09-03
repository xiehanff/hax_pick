import XCTest
@testable import HaxPickApp

@MainActor
final class PanelSessionViewModelTests: XCTestCase {
    func testResetDiscardsLateResultFromPreviousSelection() async throws {
        let performer = DeferredPerformer()
        let viewModel = makeViewModel(performer: performer)

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: performer)

        viewModel.reset(with: "selection-b")
        await performer.succeed("result-a")
        await Task.yield()

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertTrue(viewModel.conversationTurns.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "请选择动作")
    }

    func testDismissalDiscardsLateResult() async throws {
        let performer = DeferredPerformer()
        let viewModel = makeViewModel(performer: performer)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: performer)

        viewModel.prepareForDismissal()
        await performer.succeed("late-result")
        await Task.yield()

        XCTAssertTrue(viewModel.conversationTurns.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCurrentRequestStillCommitsNormally() async throws {
        let performer = DeferredPerformer()
        let viewModel = makeViewModel(performer: performer)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.summarize)
        try await waitForPendingRequest(in: performer)

        await performer.succeed("summary")
        await Task.yield()

        XCTAssertEqual(viewModel.conversationTurns.count, 1)
        XCTAssertEqual(viewModel.conversationTurns.first?.answer, "summary")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "生成完成")
    }

    private func makeViewModel(performer: DeferredPerformer) -> PanelSessionViewModel {
        PanelSessionViewModel(
            performAction: { action, text, previousResult, followUp in
                try await performer.perform(
                    action: action,
                    text: text,
                    previousResult: previousResult,
                    followUp: followUp
                )
            },
            onClose: {}
        )
    }

    private func waitForPendingRequest(in performer: DeferredPerformer) async throws {
        for _ in 0..<50 {
            if await performer.pendingCount() > 0 {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected an AI request to become pending")
        throw TestError.requestDidNotStart
    }
}

private enum TestError: Error {
    case requestDidNotStart
}

private actor DeferredPerformer {
    private var continuations: [CheckedContinuation<String, Error>] = []

    func perform(
        action: DeepSeekService.ToolAction,
        text: String,
        previousResult: String?,
        followUp: String?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func pendingCount() -> Int {
        continuations.count
    }

    func succeed(_ value: String) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: value)
    }
}
