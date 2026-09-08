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

    func testMarkdownUsesLibraryRendererAndSizesAfterParse() async throws {
        let rendered = expectation(description: "Down parse completed")
        let markdown = MarkdownWithCodeBlocksView(
            text: """
            ## 示例

            - 第一项
            - 第二项

            ```swift
            let value = 42
            print(value)
            ```
            """,
            onLayoutChange: {
                rendered.fulfill()
            }
        )
        markdown.frame = NSRect(x: 0, y: 0, width: 420, height: 40)
        markdown.layoutSubtreeIfNeeded()

        await fulfillment(of: [rendered], timeout: 3)

        let textView = try XCTUnwrap(
            descendants(of: AutoHeightMarkdownTextView.self, in: markdown).first
        )
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 40)
        textView.layoutSubtreeIfNeeded()

        XCTAssertTrue(textView.string.contains("示例"))
        XCTAssertTrue(textView.string.contains("第一项"))
        XCTAssertTrue(textView.string.contains("let value = 42"))
        XCTAssertGreaterThan(textView.intrinsicContentSize.height, 40)
    }

    func testStreamingMarkdownUpdateKeepsOneLibraryTextView() async throws {
        let firstRendered = expectation(description: "first markdown snapshot rendered")
        let secondRendered = expectation(description: "second markdown snapshot rendered")
        var renderCount = 0

        let markdown = MarkdownWithCodeBlocksView(
            text: "第一段 **Markdown**",
            onLayoutChange: {
                renderCount += 1
                if renderCount == 1 {
                    firstRendered.fulfill()
                } else if renderCount == 2 {
                    secondRendered.fulfill()
                }
            }
        )
        markdown.frame = NSRect(x: 0, y: 0, width: 420, height: 40)
        markdown.layoutSubtreeIfNeeded()

        await fulfillment(of: [firstRendered], timeout: 3)
        let firstTextView = try XCTUnwrap(
            descendants(of: AutoHeightMarkdownTextView.self, in: markdown).first
        )

        XCTAssertTrue(markdown.update(text: "第一段 **Markdown**\n\n- 流式新增列表"))
        await fulfillment(of: [secondRendered], timeout: 3)

        let secondTextView = try XCTUnwrap(
            descendants(of: AutoHeightMarkdownTextView.self, in: markdown).first
        )
        XCTAssertTrue(firstTextView === secondTextView)
        XCTAssertTrue(secondTextView.string.contains("流式新增列表"))
    }

    func testCircleIconButtonDrawsTrueCircleEvenWithNonSquareControlBounds() throws {
        let button = CircleIconButton(
            symbolName: "xmark",
            accessibilityDescription: "关闭",
            size: 28,
            backgroundColor: .black,
            tintColor: .white,
            target: nil,
            action: nil
        )
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 31)
        button.layoutSubtreeIfNeeded()

        let circleLayer = try XCTUnwrap(
            button.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        )
        let bounds = try XCTUnwrap(circleLayer.path?.boundingBox)
        XCTAssertEqual(bounds.width, bounds.height, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 28, accuracy: 0.01)
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
