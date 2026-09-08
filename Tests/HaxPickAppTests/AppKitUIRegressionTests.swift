import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class AppKitUIRegressionTests: XCTestCase {
    func testDeepDivePublishesReasoningDraftBeforeFirstToken() throws {
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        let session = AiAgentSession(stream: { _ in
            AsyncThrowingStream { streamContinuation in
                continuation = streamContinuation
            }
        })
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})

        viewModel.reset(with: "测试文本")
        viewModel.handlePrimaryAction(.deepDive)

        let streamingID = try XCTUnwrap(viewModel.streamingAssistantID)
        let draft = try XCTUnwrap(
            viewModel.conversationMessages.first(where: { $0.id == streamingID })
        )
        XCTAssertTrue(draft.expectsReasoning)
        XCTAssertTrue(draft.reasoning.isEmpty)
        XCTAssertTrue(viewModel.isLoading)

        viewModel.stopGeneration()
        continuation?.finish()
    }

    func testAutoHeightTextDoesNotExplodeBeforeWidthIsAssigned() {
        let textView = AutoHeightTextView()
        textView.string = String(repeating: "reasoning 内容 ", count: 120)

        XCTAssertLessThanOrEqual(textView.intrinsicContentSize.height, 20)

        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 20)
        textView.layoutSubtreeIfNeeded()
        let measured = textView.intrinsicContentSize.height
        XCTAssertGreaterThan(measured, 20)
        XCTAssertLessThan(measured, 2_000)
    }

    func testMarkdownCodeBlockCreatesVisibleTextView() throws {
        let markdown = MarkdownWithCodeBlocksView(
            text: """
            示例：
            ```swift
            let value = 42
            print(value)
            ```
            完成。
            """
        )

        let codeText = try XCTUnwrap(
            descendants(of: NSTextView.self, in: markdown)
                .first(where: { $0.string.contains("let value = 42") })
        )
        XCTAssertGreaterThan(codeText.frame.width, 0)
        XCTAssertGreaterThan(codeText.frame.height, 0)
    }

    func testCircleIconButtonUsesHalfHeightCornerRadius() {
        let button = CircleIconButton(
            symbolName: "xmark",
            accessibilityDescription: "关闭",
            size: 28,
            backgroundColor: .black,
            tintColor: .white,
            target: nil,
            action: nil
        )
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.layoutSubtreeIfNeeded()

        XCTAssertEqual(button.bounds.width, button.bounds.height, accuracy: 0.01)
        XCTAssertEqual(button.layer?.cornerRadius ?? 0, 14, accuracy: 0.01)
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
