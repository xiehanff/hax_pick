import XCTest
@testable import HaxPickApp

@MainActor
final class ConversationArchiveTests: XCTestCase {
    func testReselectionArchivesConversationAndBubbleEntryRestoresIt() async throws {
        let responder = ArchiveResponder()
        defer { responder.finish() }
        let session = AiAgentSession(
            stream: { _ in responder.stream() },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "第一段原文")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil { responder.hasContinuation }
        responder.yield("第一轮回答")
        responder.finish()
        try await waitUntil { !viewModel.isLoading }
        XCTAssertFalse(viewModel.hasResumableConversation)

        // 重新划词:面板回工具栏,但上一个对话被归档而不是销毁
        viewModel.reset(with: "第二段原文")
        XCTAssertTrue(viewModel.hasResumableConversation)
        XCTAssertTrue(viewModel.conversationMessages.isEmpty, "新会话应为空")
        XCTAssertEqual(viewModel.selectedText, "第二段原文")

        // 工具栏气泡入口:重新进入上一个对话
        viewModel.resumeArchivedConversation()
        XCTAssertEqual(viewModel.mode, .result)
        XCTAssertEqual(viewModel.selectedText, "第一段原文", "归档会话应带回自己的划词原文")
        XCTAssertTrue(
            viewModel.conversationMessages.contains { $0.content == "第一轮回答" },
            "归档的对话内容应完整恢复"
        )
    }

    func testReselectionDuringStreamingKeepsRequestAliveAndResumable() async throws {
        let responder = ArchiveResponder()
        defer { responder.finish() }
        let session = AiAgentSession(
            stream: { _ in responder.stream() },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "原文")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil { responder.hasContinuation }
        responder.yield("流式中的内容")

        // 生成中重新划词:会话归档,后台任务不被取消
        viewModel.reset(with: "新原文")
        XCTAssertTrue(viewModel.hasResumableConversation)
        XCTAssertFalse(viewModel.conversationMessages.contains { $0.content == "流式中的内容" })

        viewModel.resumeArchivedConversation()
        XCTAssertTrue(viewModel.isLoading, "归档会话的请求应仍在执行")
        XCTAssertEqual(viewModel.selectedText, "原文")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
private final class ArchiveResponder {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    var hasContinuation: Bool { continuation != nil }

    func stream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { self.continuation = $0 }
    }

    func yield(_ text: String) {
        continuation?.yield(text)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
