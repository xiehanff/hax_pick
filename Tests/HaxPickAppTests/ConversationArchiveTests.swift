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

    func testThirdReselectionCancelsSupersededArchivedRequest() async throws {
        let firstResponder = ArchiveResponder()
        let secondResponder = ArchiveResponder()
        defer {
            firstResponder.finish()
            secondResponder.finish()
        }

        let firstSession = AiAgentSession(
            stream: { _ in firstResponder.stream() },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(
            aiSession: firstSession,
            makeSession: {
                AiAgentSession(
                    stream: { _ in secondResponder.stream() },
                    publishIntervalNanoseconds: 0
                )
            },
            onClose: {}
        )

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil { firstResponder.hasContinuation }
        XCTAssertTrue(firstSession.isLoading)

        viewModel.reset(with: "selection-b")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil { secondResponder.hasContinuation }

        // 第三次划词会用 B 覆盖归档槽位；A 已无法从 UI 恢复，因此必须立即取消。
        viewModel.reset(with: "selection-c")
        XCTAssertFalse(firstSession.isLoading, "被覆盖的旧归档请求必须取消")
        XCTAssertTrue(viewModel.hasResumableConversation)

        // B 仍应是唯一可恢复的归档会话，并继续生成。
        viewModel.resumeArchivedConversation()
        XCTAssertEqual(viewModel.selectedText, "selection-b")
        XCTAssertTrue(viewModel.isLoading)
    }

    func testDismissalCancelsArchivedBackgroundRequest() async throws {
        let responder = ArchiveResponder()
        defer { responder.finish() }
        let archivedSession = AiAgentSession(
            stream: { _ in responder.stream() },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(
            aiSession: archivedSession,
            makeSession: { AiAgentSession(complete: { _ in "" }) },
            onClose: {}
        )

        viewModel.reset(with: "selection-a")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil { responder.hasContinuation }
        viewModel.reset(with: "selection-b")

        XCTAssertTrue(archivedSession.isLoading)
        XCTAssertTrue(viewModel.hasResumableConversation)
        XCTAssertTrue(viewModel.prepareForDismissal())
        XCTAssertFalse(archivedSession.isLoading, "关闭面板时归档请求也必须停止")
        XCTAssertFalse(viewModel.hasResumableConversation)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Expected asynchronous condition to become true")
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
