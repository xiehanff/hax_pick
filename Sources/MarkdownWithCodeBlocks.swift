import AppKit
import Down
import Splash

/// Down styler with HaxPick's light-content palette. Inline code gets a light
/// chip treatment (the library default has no background and would be
/// invisible on the white reading layer); fenced code blocks keep Down's dark
/// card and get token colors from Splash.
final class HaxMarkdownStyler: DownStyler {
    private let inlineCodeColor: NSColor
    private let codeHighlighter: SyntaxHighlighter<AttributedStringOutputFormat>

    init(
        configuration: DownStylerConfiguration,
        inlineCodeColor: NSColor,
        codeHighlighter: SyntaxHighlighter<AttributedStringOutputFormat>
    ) {
        self.inlineCodeColor = inlineCodeColor
        self.codeHighlighter = codeHighlighter
        super.init(configuration: configuration)
    }

    override func style(code str: NSMutableAttributedString) {
        // No chip background: inline code is distinguished purely by the
        // purple highlight color, per product decision.
        str.setAttributes([
            .font: fonts.code,
            .foregroundColor: inlineCodeColor,
        ], range: NSRange(location: 0, length: str.length))
    }

    override func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        super.style(codeBlock: str, fenceInfo: fenceInfo)

        let highlighted = codeHighlighter.highlight(str.string)
        let full = NSRange(location: 0, length: str.length)
        guard highlighted.string == str.string else { return }

        highlighted.enumerateAttributes(in: full) { attrs, range, _ in
            var tokenAttributes: [NSAttributedString.Key: Any] = [:]
            if let font = attrs[.font] { tokenAttributes[.font] = font }
            if let color = attrs[.foregroundColor] {
                tokenAttributes[.foregroundColor] = color
            }
            guard !tokenAttributes.isEmpty else { return }
            str.addAttributes(tokenAttributes, range: range)
        }
    }
}

/// Markdown view backed entirely by Down (cmark / CommonMark). The same AppKit
/// text view is retained for the lifetime of a message, including while the
/// model is still streaming. New snapshots are parsed continuously and only the
/// newest parse is applied, so rendering never waits for the request to finish.
@MainActor
final class MarkdownWithCodeBlocksView: NSView {
    private let markdownView = AutoHeightMarkdownTextView()
    private let styler: DownStyler
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
        self.styler = Self.makeStyler(textColor: textColor, fontSize: fontSize)
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
                await Task.yield()
                guard !Task.isCancelled else { break }
                guard revision == self.requestedRevision else {
                    continue
                }

                if let rendered = try? Down(markdownString: snapshot)
                    .toAttributedString(styler: self.styler) {
                    guard revision == self.requestedRevision else {
                        continue
                    }
                    self.apply(rendered)
                }
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

    private static func makeStyler(textColor: NSColor, fontSize: CGFloat) -> HaxMarkdownStyler {
        // Let Down own paragraph metrics. HaxPick only customizes the product
        // palette and type scale; line/paragraph spacing stays with the library
        // so headings, lists, prose and code keep coherent defaults.
        let mono = NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 1), weight: .regular)

        let fonts = StaticFontCollection(
            heading1: .boldSystemFont(ofSize: fontSize + 6),
            heading2: .boldSystemFont(ofSize: fontSize + 4),
            heading3: .boldSystemFont(ofSize: fontSize + 2),
            heading4: .boldSystemFont(ofSize: fontSize + 1),
            heading5: .boldSystemFont(ofSize: fontSize),
            heading6: .boldSystemFont(ofSize: fontSize),
            body: .systemFont(ofSize: fontSize),
            code: mono,
            listItemPrefix: .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        )

        let colors = StaticColorCollection(
            heading1: textColor,
            heading2: textColor,
            heading3: textColor,
            heading4: textColor,
            heading5: textColor,
            heading6: textColor,
            body: textColor,
            code: NSColor(hex: 0xF1F2F4),
            link: .systemBlue,
            quote: AppTheme.textSecondary,
            quoteStripe: AppTheme.border,
            thematicBreak: AppTheme.border,
            listItemPrefix: AppTheme.textSecondary,
            codeBlockBackground: NSColor(hex: 0x2E3038, alpha: 0.96)
        )

        return HaxMarkdownStyler(
            configuration: DownStylerConfiguration(
                fonts: fonts,
                colors: colors,
                paragraphStyles: Self.makeParagraphStyles()
            ),
            inlineCodeColor: NSColor(hex: 0x7C3AED),
            codeHighlighter: Self.makeCodeHighlighter(font: mono)
        )
    }

    /// Down 的默认 code 段落样式没有行距,代码行在卡片里挤在一起;
    /// 这里给 code 段落补行距、卡内左右边距和与上下文的间距,
    /// 其余样式继续沿用 Down 默认。(inset(by:) 还会在此基础上 +8)
    private static func makeParagraphStyles() -> StaticParagraphStyleCollection {
        var styles = StaticParagraphStyleCollection()
        let codeStyle = NSMutableParagraphStyle()
        codeStyle.paragraphSpacingBefore = 12
        codeStyle.paragraphSpacing = 12
        codeStyle.lineSpacing = 3
        codeStyle.headIndent = 8
        codeStyle.firstLineHeadIndent = 8
        codeStyle.tailIndent = 8
        styles.code = codeStyle
        return styles
    }

    private static func makeCodeHighlighter(font: NSFont) -> SyntaxHighlighter<AttributedStringOutputFormat> {
        // Palette matches the previous CDMarkdownKit highlighting: magenta
        // keywords, green comments, orange strings, light-green numbers.
        let tokenColors: [TokenType: NSColor] = [
            .keyword: NSColor(hex: 0xFF7AB2),
            .string: NSColor(hex: 0xFFB86C),
            .type: NSColor(hex: 0x8BE9FD),
            .call: NSColor(hex: 0x82AAFF),
            .number: NSColor(hex: 0xB5E890),
            .comment: NSColor(hex: 0x7FDB8F),
            .property: NSColor(hex: 0xF1FA8C),
            .dotAccess: NSColor(hex: 0xF1FA8C),
            .preprocessing: NSColor(hex: 0xFF7AB2),
        ]
        var codeFont = Font(size: font.pointSize)
        codeFont.resource = .preloaded(font)
        let theme = Theme(
            font: codeFont,
            plainTextColor: NSColor(hex: 0xF1F2F4),
            tokenColors: tokenColors
        )
        return SyntaxHighlighter(format: AttributedStringOutputFormat(theme: theme))
    }
}

/// Auto-height wrapper around Down's AppKit NSTextView. The Markdown renderer,
/// custom layout manager (code block backgrounds, quote stripes) and text layout
/// remain the library's; this subclass only reports the library layout's used
/// height back to HaxPick's NSStackView.
@MainActor
final class AutoHeightMarkdownTextView: DownTextView {
    private var lastMeasuredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero, styler: DownStyler(), layoutManager: DownLayoutManager())
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
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the text storage directly. Setting `string` would route through
    /// DownTextView.render(), but HaxPick parses via its own latest-wins loop.
    func setAttributedString(_ attributedString: NSAttributedString) {
        textStorage?.setAttributedString(attributedString)
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
