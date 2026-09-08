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

    func testCompletedMarkdownUsesLibraryRendererAndSizesAfterParse() async throws {
        let rendered = expectation(description: "CDMarkdownKit parse completed")
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
        // Reproduce AppKit's historical borderless-control behaviour where the
        // cell can end up a few points taller than the requested visual size.
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
