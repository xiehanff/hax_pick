import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class AiMessageBubblePerformanceTests: XCTestCase {
    func testUnchangedCompletedAssistantKeepsRenderedMarkdownView() throws {
        let message = AiMessage(role: .assistant, content: "**稳定回答**")
        let bubble = AiMessageBubble(message: message, isStreaming: false)
        let original = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))

        bubble.update(
            message: message,
            isStreaming: false,
            assistantContentOpacity: 1
        )

        let updated = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))
        XCTAssertTrue(original === updated, "未变化的历史回答不能在流式刷新时重建 Markdown 视图")
    }

    func testUnchangedUserMessageKeepsTextViewIdentity() throws {
        let message = AiMessage(role: .user, content: "保持我的选择")
        let bubble = AiMessageBubble(message: message)
        let original = try XCTUnwrap(firstTextView(with: message.content, in: bubble))

        bubble.update(
            message: message,
            isStreaming: false,
            assistantContentOpacity: 1
        )

        let updated = try XCTUnwrap(firstTextView(with: message.content, in: bubble))
        XCTAssertTrue(original === updated, "未变化的用户消息不应被 teardown/rebuild")
    }

    func testStreamingAssistantUpdatesMarkdownViewInPlace() throws {
        let id = UUID()
        let first = AiMessage(id: id, role: .assistant, content: "第一段")
        let bubble = AiMessageBubble(message: first, isStreaming: true)
        let original = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))

        let second = AiMessage(id: id, role: .assistant, content: "第一段第二段")
        bubble.update(
            message: second,
            isStreaming: true,
            assistantContentOpacity: 1
        )

        let updated = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))
        XCTAssertTrue(original === updated, "同一条流式回答必须原地更新 Markdown 视图")
    }

    func testStreamingCompletionKeepsMarkdownViewIdentity() throws {
        let id = UUID()
        let streaming = AiMessage(id: id, role: .assistant, content: "**完成**")
        let bubble = AiMessageBubble(message: streaming, isStreaming: true)
        let streamingView = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))

        bubble.update(
            message: streaming,
            isStreaming: false,
            assistantContentOpacity: 1
        )
        let completed = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))
        XCTAssertTrue(streamingView === completed, "完成态不应重建 Markdown 视图")

        bubble.update(
            message: streaming,
            isStreaming: false,
            assistantContentOpacity: 1
        )
        let unchanged = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))
        XCTAssertTrue(completed === unchanged, "完成态 Markdown 不应在重复刷新时重建")
    }

    func testExpandedStreamingReasoningUpdatesMarkdownViewInPlace() throws {
        let id = UUID()
        let first = AiMessage(
            id: id,
            role: .assistant,
            content: "回答",
            reasoning: "第一步"
        )
        let bubble = AiMessageBubble(message: first, isStreaming: true)
        let disclosureButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: bubble)
                .first(where: { $0.title.contains("思考过程") })
        )
        disclosureButton.performClick(nil)
        let original = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))

        let second = AiMessage(
            id: id,
            role: .assistant,
            content: "回答",
            reasoning: "第一步，第二步"
        )
        bubble.update(
            message: second,
            isStreaming: true,
            assistantContentOpacity: 1
        )

        let updated = try XCTUnwrap(firstDescendant(of: MarkdownWithCodeBlocksView.self, in: bubble))
        XCTAssertTrue(original === updated, "展开的流式 reasoning 也应原地更新 Markdown 视图")
    }

    private func firstTextView(with text: String, in root: NSView) -> AutoHeightTextView? {
        descendants(of: AutoHeightTextView.self, in: root).first(where: { $0.string == text })
    }

    private func firstDescendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        descendants(of: type, in: root).first
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
