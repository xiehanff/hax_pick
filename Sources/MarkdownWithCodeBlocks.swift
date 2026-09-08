import AppKit
import CDMarkdownKit

/// Completed assistant messages are rendered entirely by CDMarkdownKit.
/// HaxPick only owns AppKit sizing/lifecycle around the library view; Markdown
/// parsing, fenced code blocks, lists, quotes, links and styled backgrounds are
/// delegated to the mature renderer.
@MainActor
final class MarkdownWithCodeBlocksView: NSView {
    private let markdownView = AutoHeightMarkdownTextView()
    private var renderTask: Task<Void, Never>?

    init(
        text: String,
        textColor: NSColor = AppTheme.textPrimary,
        fontSize: CGFloat = 13,
        onLayoutChange: @escaping () -> Void = {}
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        markdownView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(markdownView)
        markdownView.pinEdges(to: self)

        // Keep a lightweight plain-text fallback visible while the async parser
        // works. This avoids a blank assistant row on long completed responses.
        markdownView.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: textColor,
                ]
            )
        )

        let parser = CDMarkdownParser(
            theme: Self.makeTheme(textColor: textColor, fontSize: fontSize)
        )

        renderTask = Task { [weak self] in
            let rendered = await parser.parse(text)
            guard !Task.isCancelled, let self else { return }
            self.markdownView.setAttributedString(rendered)
            self.markdownView.invalidateIntrinsicContentSize()
            self.needsLayout = true
            onLayoutChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderTask?.cancel()
    }

    private static func makeTheme(textColor: NSColor, fontSize: CGFloat) -> CDMarkdownTheme {
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 4
        bodyParagraph.paragraphSpacing = 8

        let codeBackground = NSColor(hex: 0x2E3038, alpha: 0.96)
        let codeText = NSColor(hex: 0xF1F2F4)
        let mono = NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 1), weight: .regular)

        return CDMarkdownTheme(
            font: .systemFont(ofSize: fontSize),
            fontColor: textColor,
            backgroundColor: .clear,
            header: .init(
                color: textColor,
                paragraphStyle: bodyParagraph
            ),
            bold: .init(color: textColor),
            italic: .init(color: textColor),
            code: .init(
                font: mono,
                color: codeText,
                backgroundColor: codeBackground
            ),
            syntax: .init(
                font: mono,
                color: codeText,
                backgroundColor: codeBackground,
                paragraphStyle: bodyParagraph
            ),
            strikethrough: .init(color: textColor),
            quote: .init(
                color: AppTheme.textSecondary,
                paragraphStyle: bodyParagraph
            ),
            list: .init(
                color: textColor,
                paragraphStyle: bodyParagraph
            ),
            orderedList: .init(
                color: textColor,
                paragraphStyle: bodyParagraph
            ),
            link: .init(color: .systemBlue),
            linkReference: .init(color: .systemBlue),
            taskList: .init(
                color: textColor,
                paragraphStyle: bodyParagraph
            ),
            horizontalRule: .init(color: AppTheme.textSecondary)
        )
    }
}

/// Auto-height wrapper around CDMarkdownKit's AppKit NSTextView. The Markdown
/// renderer and text layout manager remain the library's; this subclass only
/// reports the library layout's used height back to HaxPick's NSStackView.
@MainActor
final class AutoHeightMarkdownTextView: CDMarkdownNSTextView {
    private var lastMeasuredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = AppTheme.windowAppearance
        drawsBackground = false
        isEditable = false
        isSelectable = true
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        roundAllCorners = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }

        let availableWidth = bounds.width
        guard availableWidth > 2 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 18)
        }

        lastMeasuredWidth = availableWidth
        textContainer.containerSize = NSSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        customLayoutManager.ensureLayout(for: textContainer)
        let used = customLayoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(18, ceil(used.height + textContainerInset.height * 2))
        )
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        if width > 2, abs(width - lastMeasuredWidth) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, newSize.width > 2 {
            invalidateIntrinsicContentSize()
        }
    }
}

/// Lightweight NSTextView used only while tokens are still streaming. It is not
/// a Markdown renderer; completed content is always handed to CDMarkdownKit.
final class AutoHeightTextView: NSTextView {
    private var lastMeasuredWidth: CGFloat = 0

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = AppTheme.windowAppearance
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isRichText = true
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainerInset = .zero
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }

        let availableWidth = bounds.width
        guard availableWidth > 2 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 18)
        }

        lastMeasuredWidth = availableWidth
        textContainer.containerSize = NSSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(18, ceil(used.height + textContainerInset.height * 2))
        )
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        if width > 2, abs(width - lastMeasuredWidth) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, newSize.width > 2 {
            invalidateIntrinsicContentSize()
        }
    }
}
