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
        let availableWidth = max(bounds.width, 1)
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

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
    }
}

private final class CodeBlockView: NSView {
    init(code: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyContinuousCornerRadius(8, background: NSColor(hex: 0x1E1E2E))
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor(hex: 0x333348).cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = NSColor(hex: 0xE0E0E0)
        text.string = code
        text.textContainerInset = NSSize(width: 10, height: 9)
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = false
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scroll.documentView = text

        addSubview(scroll)
        scroll.pinEdges(to: self)
        let lineCount = max(1, code.components(separatedBy: .newlines).count)
        heightAnchor.constraint(equalToConstant: min(240, max(42, CGFloat(lineCount) * 18 + 20))).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
