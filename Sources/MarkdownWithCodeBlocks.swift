import AppKit
import CDMarkdownKit

/// Markdown view backed entirely by CDMarkdownKit. The same AppKit text view is
/// retained for the lifetime of a message, including while the model is still
/// streaming. New snapshots are parsed continuously and only the newest parse is
/// applied, so rendering never waits for the request to finish.
@MainActor
final class MarkdownWithCodeBlocksView: NSView {
    private let markdownView = AutoHeightMarkdownTextView()
    private let parser: CDMarkdownParser
    private let textColor: NSColor
    private let fontSize: CGFloat
    private let onLayoutChange: () -> Void

    private var currentText = ""
    private var requestedRevision = 0
    private var renderTask: Task<Void, Never>?

    init(
        text: String,
        textColor: NSColor = AppTheme.textPrimary,
        fontSize: CGFloat = 13,
        onLayoutChange: @escaping () -> Void = {}
    ) {
        self.textColor = textColor
        self.fontSize = fontSize
        self.onLayoutChange = onLayoutChange
        self.parser = Self.makeParser(textColor: textColor, fontSize: fontSize)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        markdownView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(markdownView)
        markdownView.pinEdges(to: self)

        update(text: text, showPlainFallback: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderTask?.cancel()
    }

    /// Updates the existing renderer instead of replacing the message body.
    /// Parsing is latest-wins: if several 40ms streaming snapshots arrive while
    /// one parse is running, stale results are skipped and the newest snapshot is
    /// parsed immediately afterwards.
    @discardableResult
    func update(text: String, showPlainFallback: Bool = false) -> Bool {
        guard text != currentText else { return false }
        currentText = text
        requestedRevision &+= 1

        if showPlainFallback || markdownView.string.isEmpty {
            showFallback(text)
        }
        startRenderLoopIfNeeded()
        return true
    }

    private func startRenderLoopIfNeeded() {
        guard renderTask == nil else { return }

        renderTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let revision = self.requestedRevision
                let snapshot = self.currentText
                let rendered = await self.parser.parse(snapshot)

                guard !Task.isCancelled else { break }
                guard revision == self.requestedRevision else {
                    // A newer streaming snapshot arrived while parsing. Do not
                    // flash an older render; immediately parse the latest text.
                    continue
                }

                self.apply(rendered)
                self.renderTask = nil
                return
            }

            self.renderTask = nil
        }
    }

    private func showFallback(_ text: String) {
        markdownView.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: textColor,
                    .paragraphStyle: Self.makeBodyParagraphStyle(),
                ]
            )
        )
        markdownView.invalidateIntrinsicContentSize()
    }

    private func apply(_ rendered: NSAttributedString) {
        let oldSelection = markdownView.selectedRange()
        markdownView.setAttributedString(rendered)

        if oldSelection.location != NSNotFound {
            let length = markdownView.string.utf16.count
            let location = min(oldSelection.location, length)
            let selectedLength = min(oldSelection.length, max(0, length - location))
            markdownView.setSelectedRange(NSRange(location: location, length: selectedLength))
        }

        markdownView.invalidateIntrinsicContentSize()
        needsLayout = true
        onLayoutChange()
    }

    private static func makeBodyParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 12
        paragraph.paragraphSpacingBefore = 2
        return paragraph
    }

    private static func makeParser(textColor: NSColor, fontSize: CGFloat) -> CDMarkdownParser {
        let paragraph = makeBodyParagraphStyle()
        let parser = CDMarkdownParser(
            font: .systemFont(ofSize: fontSize),
            fontColor: textColor,
            backgroundColor: .clear,
            paragraphStyle: paragraph,
            automaticLinkDetectionEnabled: true,
            squashNewlines: false
        )

        let codeBackground = NSColor(hex: 0x2E3038, alpha: 0.96)
        let codeText = NSColor(hex: 0xF1F2F4)
        let mono = NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 1), weight: .regular)

        parser.header.color = textColor
        parser.bold.color = textColor
        parser.italic.color = textColor
        parser.strikethrough.color = textColor
        parser.quote.color = AppTheme.textSecondary
        parser.list.color = textColor
        parser.orderedList.color = textColor
        parser.taskList.color = textColor
        parser.link.color = .systemBlue
        parser.linkReference.color = .systemBlue
        parser.automaticLink.color = .systemBlue

        parser.code.font = mono
        parser.code.color = codeText
        parser.code.backgroundColor = codeBackground

        let codeParagraph = makeBodyParagraphStyle()
        codeParagraph.lineSpacing = 5
        codeParagraph.paragraphSpacing = 10
        parser.syntax.font = mono
        parser.syntax.color = codeText
        parser.syntax.backgroundColor = codeBackground
        parser.syntax.paragraphStyle = codeParagraph

        return parser
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

/// Lightweight auto-height NSTextView used by non-Markdown UI such as the source
/// card and user bubbles.
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
