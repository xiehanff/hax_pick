import AppKit

/// AppKit-native Markdown/code renderer used by completed assistant messages.
/// Streaming paths intentionally use a lightweight plain text view elsewhere.
final class MarkdownWithCodeBlocksView: NSView {
    private enum Segment {
        case markdown(String)
        case code(String)
    }

    private let stack = NSStackView()

    init(text: String, textColor: NSColor = AppTheme.textPrimary, fontSize: CGFloat = 13) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)

        for segment in parseSegments(from: text) {
            let child: NSView
            switch segment {
            case .markdown(let markdown):
                child = makeMarkdownText(markdown, textColor: textColor, fontSize: fontSize)
            case .code(let code):
                child = CodeBlockView(code: code)
            }
            stack.addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func parseSegments(from text: String) -> [Segment] {
        let parts = text.components(separatedBy: "```")
        var segments: [Segment] = []
        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 2) {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(.markdown(trimmed))
                }
            } else {
                let pieces = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let code = pieces.count > 1 ? String(pieces[1]) : String(part)
                if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.code(code))
                }
            }
        }
        return segments
    }

    private func makeMarkdownText(_ text: String, textColor: NSColor, fontSize: CGFloat) -> NSView {
        let textView = AutoHeightTextView()
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.defaultParagraphStyle = Self.paragraphStyle(lineSpacing: 4)

        if let attributed = try? AttributedString(markdown: text) {
            let rendered = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
            let fullRange = NSRange(location: 0, length: rendered.length)
            rendered.addAttribute(.foregroundColor, value: textColor, range: fullRange)
            rendered.addAttribute(.paragraphStyle, value: Self.paragraphStyle(lineSpacing: 4), range: fullRange)
            textView.textStorage?.setAttributedString(rendered)
        } else {
            textView.string = text
        }
        return textView
    }

    private static func paragraphStyle(lineSpacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 8
        return style
    }
}

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

        // Auto Layout asks for intrinsic size before NSStackView has assigned the
        // final width. Measuring at width=1 wraps every glyph onto its own line and
        // can create a several-thousand-point phantom height. Return a compact
        // provisional height until a real width is available; setFrameSize/layout
        // invalidates us as soon as the actual width arrives.
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

private final class CodeBlockView: RoundedSurfaceView {
    private let scrollView = NSScrollView()
    private let codeTextView = NSTextView()
    private let contentWidth: CGFloat
    private let contentHeight: CGFloat

    init(code: String) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let lines = code.components(separatedBy: .newlines)
        let lineCount = max(1, lines.count)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let longestLineWidth = lines
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? 0
        self.contentWidth = max(80, longestLineWidth + 24)
        self.contentHeight = max(42, CGFloat(lineCount) * 18 + 20)

        super.init(
            cornerRadius: 8,
            backgroundColor: NSColor(hex: 0x1E1E2E),
            borderColor: NSColor(hex: 0x333348),
            borderWidth: 0.75
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.appearance = AppTheme.windowAppearance
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = contentHeight > 240
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        codeTextView.appearance = AppTheme.windowAppearance
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.drawsBackground = false
        codeTextView.font = font
        codeTextView.textColor = NSColor(hex: 0xE0E0E0)
        codeTextView.string = code
        codeTextView.textContainerInset = NSSize(width: 10, height: 9)
        codeTextView.isHorizontallyResizable = true
        codeTextView.isVerticallyResizable = true
        codeTextView.textContainer?.widthTracksTextView = false
        codeTextView.textContainer?.heightTracksTextView = false
        codeTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        codeTextView.frame = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: contentHeight
        )
        scrollView.documentView = codeTextView

        addSubview(scrollView)
        scrollView.pinEdges(to: self)
        heightAnchor.constraint(equalToConstant: min(240, contentHeight)).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let viewport = scrollView.contentSize
        codeTextView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(viewport.width, contentWidth),
            height: max(viewport.height, contentHeight)
        )
    }
}