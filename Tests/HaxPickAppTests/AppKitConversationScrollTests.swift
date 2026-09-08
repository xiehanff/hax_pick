import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class AppKitConversationScrollTests: XCTestCase {
    func testStreamingDoesNotTakeScrollOwnershipDuringLiveGesture() async throws {
        let responder = AppKitStreamResponder()
        defer { responder.finish() }
        let session = AiAgentSession(
            stream: { responder.stream($0) }, publishIntervalNanoseconds: 0
        )
        let model = PanelSessionViewModel(aiSession: session, onClose: {})
        let panel = makePanel(viewModel: model)
        let window = hostWindow(panel)
        defer { window.close() }
        model.reset(with: "selection")
        model.handlePrimaryAction(.deepDive)
        try await waitUntil("stream starts") { responder.hasContinuation }
        responder.yield(longAnswer(repetitions: 14))
        try await waitUntil("initial content") { (model.lastAssistantContent?.count ?? 0) > 1_000 }
        await settle(panel)
        let scroll = try conversationScrollView(in: panel)

        // Repeat both boundaries. Observe every bounds notification, not just
        // the offset after pending layout/scroll work has settled.
        for boundary in [false, true, false, true] {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            let position = boundary ? maximumOffset(of: scroll) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: position))
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            let trace = ClipPositionTrace(clip: scroll.contentView)
            let previous = model.lastAssistantContent
            responder.yield(longAnswer(repetitions: 2))
            try await waitUntil("new content during gesture") { model.lastAssistantContent != previous }
            await settle(panel)
            window.displayIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.origin.y, position, accuracy: 0.5)
            XCTAssertTrue(trace.positions.allSatisfy { abs($0 - position) <= 0.5 },
                          "流式布局不可在用户手势中途改写 offset: \(trace.positions)")
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            try await Task.sleep(nanoseconds: 180_000_000)
            await settle(panel)
            XCTAssertEqual(scroll.contentView.bounds.origin.y,
                           boundary ? maximumOffset(of: scroll) : 0, accuracy: 0.5)
        }

        // Exercise the real scrollWheel override as well: old wheel mice do
        // not necessarily send paired live-scroll notifications.
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0))
        let wheelPosition = scroll.contentView.bounds.origin.y
        let trace = ClipPositionTrace(clip: scroll.contentView)
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cgEvent)))
        responder.yield(longAnswer(repetitions: 2))
        await settle(panel)
        try await Task.sleep(nanoseconds: 180_000_000)
        await settle(panel)
        // AppKit animates a legacy wheel tick over multiple run-loop passes.
        // Its own upward motion is allowed; a streaming follow-tail jump in
        // the opposite direction is not, even if it later corrects itself.
        let positions = [wheelPosition] + trace.positions
        XCTAssertLessThan(scroll.contentView.bounds.origin.y, wheelPosition)
        XCTAssertTrue(zip(positions, positions.dropFirst()).allSatisfy { $1 <= $0 + 0.5 },
                      "向上滚轮期间不应被流式跟尾反向拉动: \(positions)")
    }

    func testExpandedReasoningKeepsBothBoundariesStableDuringLiveScroll() async throws {
        let responder = AppKitStreamResponder()
        defer { responder.finish() }
        let session = AiAgentSession(stream: { responder.stream($0) }, publishIntervalNanoseconds: 0)
        let model = PanelSessionViewModel(aiSession: session, onClose: {})
        let panel = makePanel(viewModel: model)
        let window = hostWindow(panel)
        defer { window.close() }
        model.reset(with: "selection")
        model.handlePrimaryAction(.deepDive)
        try await waitUntil("stream starts") { responder.hasContinuation }
        responder.yield("placeholder")
        try await waitUntil("draft exists") { model.lastAssistantContent == "placeholder" }
        await settle(panel)
        let bubble = try XCTUnwrap(descendants(of: AiMessageBubble.self, in: panel).last)
        let id = try XCTUnwrap(model.streamingAssistantID)
        var reasoning = longAnswer(repetitions: 14)
        func updateReasoning() {
            bubble.update(message: AiMessage(id: id, role: .assistant, content: "", reasoning: reasoning),
                          isStreaming: true, assistantContentOpacity: 0.78)
        }
        updateReasoning()
        let disclosure = try XCTUnwrap(descendants(of: NSButton.self, in: bubble)
            .first { $0.title.contains("思考过程") })
        disclosure.performClick(nil)
        await settle(panel)
        let scroll = try conversationScrollView(in: panel)
        XCTAssertGreaterThan(maximumOffset(of: scroll), 300)

        for atBottom in [false, true, false, true] {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            let position = atBottom ? maximumOffset(of: scroll) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: position))
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            let trace = ClipPositionTrace(clip: scroll.contentView)
            reasoning += longAnswer(repetitions: 2)
            updateReasoning()
            await settle(panel)
            window.displayIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.origin.y, position, accuracy: 0.5)
            XCTAssertTrue(trace.positions.allSatisfy { abs($0 - position) <= 0.5 }, "\(trace.positions)")
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            // Simulate finger-up -> momentum-start within the quiet interval.
            try await Task.sleep(nanoseconds: 30_000_000)
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            reasoning += "\n\n惯性滚动期间仍然输出。"
            updateReasoning()
            await settle(panel)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, position, accuracy: 0.5)
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            try await Task.sleep(nanoseconds: 180_000_000)
            await settle(panel)
            XCTAssertEqual(scroll.contentView.bounds.origin.y,
                           atBottom ? maximumOffset(of: scroll) : 0, accuracy: 0.5)
        }
    }

    private func hostWindow(_ panel: ResultPanelView) -> NSWindow {
        let window = NSWindow(contentRect: panel.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = panel
        window.layoutIfNeeded()
        return window
    }

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

    func testStreamingHistoryKeepsRenderingAtFixedOffsetAndManualReturnFollowsTail() async throws {
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

        let continued = longAnswer(repetitions: 10) + "\n后台流式内容已经持续渲染。"
        responder.yield(continued)
        let accumulated = first + continued
        try await waitUntil("continued streaming chunk should reach the session model") {
            viewModel.lastAssistantContent == visibleContent(accumulated)
        }
        await settle(panel)

        let renderedMarkdown = descendants(
            of: AutoHeightMarkdownTextView.self,
            in: panel
        ).map(\.string).joined(separator: "\n")
        XCTAssertTrue(
            renderedMarkdown.contains("后台流式内容已经持续渲染"),
            "离开底部时 UI 应继续消费快照，不得把内容积压到再次到底时突然刷新"
        )

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
            "用户自己滚回当前底部后，应直接贴到新的真实底部"
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

        let secondHistoryOffset = max(0, maximumOffset(of: scrollView) - 180)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: secondHistoryOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)
        let secondPinnedOffset = scrollView.contentView.bounds.origin.y

        responder.yield("\n第二次离开底部后的流式 chunk")
        try await waitUntil("second history-reading chunk should reach the model") {
            viewModel.lastAssistantContent?.hasSuffix("第二次离开底部后的流式 chunk") == true
        }
        await settle(panel)
        XCTAssertTrue(
            descendants(of: AutoHeightMarkdownTextView.self, in: panel)
                .map(\.string)
                .joined(separator: "\n")
                .contains("第二次离开底部后的流式 chunk")
        )
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            secondPinnedOffset,
            accuracy: 1,
            "第二次阅读历史时也必须持续渲染且保持 offset"
        )

        scrollView.contentView.scroll(
            to: NSPoint(x: 0, y: maximumOffset(of: scrollView))
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(panel)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumOffset(of: scrollView),
            accuracy: 1,
            "反复离开并回到底部也应保持稳定"
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

    private func descendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        for child in root.subviews {
            if let match = child as? T {
                matches.append(match)
            }
            matches.append(contentsOf: descendants(of: type, in: child))
        }
        return matches
    }
}

@MainActor
private final class ClipPositionTrace: NSObject {
    private let clip: NSClipView
    private(set) var positions: [CGFloat] = []

    init(clip: NSClipView) {
        self.clip = clip
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
            name: NSView.boundsDidChangeNotification, object: clip)
    }

    @objc private func changed() { positions.append(clip.bounds.origin.y) }
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
