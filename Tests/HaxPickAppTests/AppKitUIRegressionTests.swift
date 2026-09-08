import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class AppKitUIRegressionTests: XCTestCase {
    func testToolbarHeightIncludesGlassInsetsAndTextMetrics() {
        let expectedMinimum = FloatingPanelLayout.toolbarContentHeight
            + AppTheme.glassContentInset * 2

        XCTAssertGreaterThanOrEqual(FloatingPanelLayout.toolbarSize.height, expectedMinimum)
        XCTAssertEqual(
            FloatingPanelLayout.toolbarSize.height,
            expectedMinimum,
            accuracy: 0.01,
            "工具栏窗口高度应由内容行高加上下玻璃内边距决定"
        )
        XCTAssertGreaterThanOrEqual(
            FloatingPanelLayout.toolbarContentHeight,
            FloatingPanelLayout.toolbarTextFont.ascender - FloatingPanelLayout.toolbarTextFont.descender,
            "按钮字体增大时，内容区域必须仍能容纳完整字形"
        )
    }

    func testDeepDiveDoesNotFadeCodeBlockThroughAncestorOpacity() async throws {
        let bubble = AiMessageBubble(
            message: AiMessage(role: .assistant, content: "正文\n\n```swift\nlet value = 42\n```"),
            assistantContentOpacity: 0.78
        )
        bubble.frame = NSRect(x: 0, y: 0, width: 420, height: 200)
        for _ in 0..<10 {
            bubble.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let text = try XCTUnwrap(descendants(of: AutoHeightMarkdownTextView.self, in: bubble).first)
        var ancestor: NSView? = text
        while let view = ancestor {
            XCTAssertEqual(view.alphaValue, 1, "代码块黑底不能随正文一起降低透明度")
            ancestor = view.superview
        }
        // Verify the actual Down drawing, not just a palette constant. Sample
        // blank space to the right of a code line, away from glyphs/corners.
        let layout = try XCTUnwrap(text.layoutManager)
        let container = try XCTUnwrap(text.textContainer)
        let codeRange = (text.string as NSString).range(of: "let value")
        XCTAssertNotEqual(codeRange.location, NSNotFound)
        let glyphRange = layout.glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
        let line = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        let bitmap = try XCTUnwrap(text.bitmapImageRepForCachingDisplay(in: text.bounds))
        text.cacheDisplay(in: text.bounds, to: bitmap)
        let color = try XCTUnwrap(bitmap.colorAt(
            x: Int((text.bounds.width - 30) * CGFloat(bitmap.pixelsWide) / text.bounds.width),
            y: Int(line.midY * CGFloat(bitmap.pixelsHigh) / text.bounds.height)
        )?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
    }

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

    func testStreamingTextStorageOnlyReplacesActiveParagraph() throws {
        let textView = AutoHeightMarkdownTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 40)
        let base = NSAttributedString(
            string: "稳定的第一段\n\n正在输出的末段",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        XCTAssertTrue(textView.setAttributedString(base))

        let observer = TextStorageEditObserver()
        textView.textStorage?.delegate = observer
        let updated = NSAttributedString(
            string: "稳定的第一段\n\n正在输出的末段，新增 token",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )

        XCTAssertTrue(textView.setAttributedString(updated))
        let editedRange = try XCTUnwrap(observer.lastEditedRange)
        let stableParagraphLength = ("稳定的第一段\n\n" as NSString).length
        XCTAssertGreaterThanOrEqual(
            editedRange.location,
            stableParagraphLength,
            "流式追加不应使已完成段落的 glyph/layout 缓存失效"
        )
    }

    func testConversationPanelHasNoHorizontalDividers() {
        let session = AiAgentSession(complete: { _ in "" })
        let viewModel = PanelSessionViewModel(aiSession: session, onClose: {})
        let panel = ResultPanelView(viewModel: viewModel)

        XCTAssertTrue(
            descendants(of: SoftDividerView.self, in: panel).isEmpty,
            "对话窗口头部和输入区不应保留横向分割线"
        )
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

private final class TextStorageEditObserver: NSObject, NSTextStorageDelegate {
    private(set) var lastEditedRange: NSRange?

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        lastEditedRange = editedRange
    }
}
