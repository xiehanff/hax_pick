import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class AppKitConversationScrollTests: XCTestCase {
    func testCompletedConversationCanReachTopAndBottom() async throws {
        let responder = AppKitStreamResponder()
        defer { responder.finish() }

        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})
        let panel = makePanel(viewModel: viewModel)

        viewModel.reset(with: "self.isEmp")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil("AI stream should start") { responder.hasContinuation }

        responder.yield(longAnswer(repetitions: 18))
        try await waitUntil("long assistant draft should be published") {
            (viewModel.lastAssistantContent?.count ?? 0) > 2_000
        }
        responder.finish()
        try await waitUntil("completed response should leave loading state") {
            !viewModel.isLoading
        }
        await settle(panel)

        let scrollView = try conversationScrollView(in: panel)
        let maxOffset = maximumOffset(of: scrollView)
        XCTAssertGreaterThan(maxOffset, 200, "测试内容必须实际超出视口")

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            0,
            accuracy: 1,
            "完成态向上滚动必须能真正到达顶部"
        )

        let refreshedMaxOffset = maximumOffset(of: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: refreshedMaxOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumOffset(of: scrollView),
            accuracy: 1,
            "完成态向下滚动必须能真正到达底部"
        )
    }

    func testStreamingHistoryPositionStaysFixedAndManualReturnResumesLatestOutput() async throws {
        let responder = AppKitStreamResponder()
        defer { responder.finish() }

        let session = AiAgentSession(
            stream: { messages in responder.stream(messages) },
            publishIntervalNanoseconds: 0
        )
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})
        let panel = makePanel(viewModel: viewModel)

        viewModel.reset(with: "selection")
        viewModel.handlePrimaryAction(.deepDive)
        try await waitUntil("AI stream should start") { responder.hasContinuation }

        let first = longAnswer(repetitions: 14)
        responder.yield(first)
        try await waitUntil("first visible assistant chunk should be published") {
            viewModel.lastAssistantContent == visibleContent(first)
        }
        await settle(panel)

        let scrollView = try conversationScrollView(in: panel)
        let initialMaxOffset = maximumOffset(of: scrollView)
        XCTAssertGreaterThan(initialMaxOffset, 300, "测试内容必须足够长，才能模拟阅读历史")

        let historyOffset = max(0, initialMaxOffset - 260)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: historyOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)
        let pinnedHistoryOffset = scrollView.contentView.bounds.origin.y

        let deferred = longAnswer(repetitions: 10)
        responder.yield(deferred)
        let accumulated = first + deferred
        try await waitUntil("deferred streaming chunk should reach the session model") {
            viewModel.lastAssistantContent == visibleContent(accumulated)
        }
        await settle(panel)

        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            pinnedHistoryOffset,
            accuracy: 1,
            "用户阅读历史时，后台流式增长不能改写真实 NSScrollView offset"
        )

        let visibleBottom = maximumOffset(of: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: visibleBottom))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)

        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumOffset(of: scrollView),
            accuracy: 1,
            "用户自己滚回当前底部后，应 flush deferred streaming UI 并贴到新的真实底部"
        )

        responder.yield("\n最后一个可见 chunk")
        try await waitUntil("following-tail should continue exposing new streaming chunks") {
            viewModel.lastAssistantContent?.hasSuffix("最后一个可见 chunk") == true
        }
        await settle(panel)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumOffset(of: scrollView),
            accuracy: 1,
            "恢复 following-tail 后，后续流式输出应持续可见"
        )

        responder.finish()
        try await waitUntil("finished stream should leave loading state") {
            !viewModel.isLoading
        }
    }

    private func makePanel(viewModel: PanelSessionViewModel) -> ResultPanelView {
        let panel = ResultPanelView(viewModel: viewModel)
        panel.frame = NSRect(x: 0, y: 0, width: 520, height: 640)
        panel.layoutSubtreeIfNeeded()
        return panel
    }

    private func conversationScrollView(in panel: ResultPanelView) throws -> NSScrollView {
        guard let scrollView = panel.subviews.compactMap({ $0 as? NSScrollView }).first else {
            XCTFail("ResultPanelView should contain an AppKit NSScrollView")
            throw ScrollTestError.missingScrollView
        }
        return scrollView
    }

    private func maximumOffset(of scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.frame.height - scrollView.contentSize.height)
    }

    private func visibleContent(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func settle(_ panel: ResultPanelView) async {
        for _ in 0..<8 {
            panel.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func waitUntil(
        _ description: String,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail(description)
        throw ScrollTestError.conditionNotMet
    }

    private func longAnswer(repetitions: Int) -> String {
        let paragraph = """
        这是用于验证 AppKit 原生滚动边界的长文本。内容会持续增长，包含足够多的行，\
        让 NSScrollView 产生稳定的垂直滚动范围。用户离开底部后，流式网络仍继续接收，\
        但界面不应该重排用户正在阅读的位置。回到底部时，才恢复最新内容。\n\n
        """
        return String(repeating: paragraph, count: repetitions)
    }
}

@MainActor
private final class AppKitStreamResponder {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    var hasContinuation: Bool { continuation != nil }

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

private enum ScrollTestError: Error {
    case missingScrollView
    case conditionNotMet
}
