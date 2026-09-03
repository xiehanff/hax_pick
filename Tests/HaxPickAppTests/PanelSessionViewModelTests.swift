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

        viewModel.handlePrimaryAction(.translate)
        try await waitForPendingRequest(in: performer)
        await performer.succeed("result-b")
        try await waitUntil { viewModel.conversationTurns.count == 1 }

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertEqual(viewModel.conversationTurns.map(\.answer), ["result-b"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.statusHint, "生成完成")
    }

    func testDismissalDiscardsLateResultAfterSessionReuse() async throws {
        let performer = DeferredPerformer()
        let viewModel = makeViewModel(performer: performer)

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: performer)

        XCTAssertTrue(viewModel.prepareForDismissal())
        XCTAssertFalse(viewModel.prepareForDismissal())
        await performer.succeed("late-result-a")

        viewModel.reset(with: "selection-b")
        viewModel.handlePrimaryAction(.explain)
        try await waitForPendingRequest(in: performer)
        await performer.succeed("result-b")
        try await waitUntil { viewModel.conversationTurns.count == 1 }

        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertEqual(viewModel.conversationTurns.map(\.answer), ["result-b"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCurrentRequestStillCommitsNormally() async throws {
        let performer = DeferredPerformer()
        let viewModel = makeViewModel(performer: performer)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.summarize)
        try await waitForPendingRequest(in: performer)

        await performer.succeed("summary")
        try await waitUntil { viewModel.conversationTurns.count == 1 }

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
        for _ in 0..<100 {
            if await performer.pendingCount() > 0 {
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
