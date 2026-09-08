import AppKit

@MainActor
final class AiMessageBubble: NSView {
    private var currentMessage: AiMessage
    private var isStreaming: Bool
    private var assistantContentOpacity: CGFloat
    private let onLayoutChange: () -> Void

    private var contentRoot: NSView?
    private var reasoningView: AiReasoningDisclosureView?
    private var assistantBodyView: NSView?
    private var assistantMarkdownView: MarkdownWithCodeBlocksView?

    init(
        message: AiMessage,
        isStreaming: Bool = false,
        assistantContentOpacity: CGFloat = 1,
        onLayoutChange: @escaping () -> Void = {}
    ) {
        self.currentMessage = message
        self.isStreaming = isStreaming
        self.assistantContentOpacity = assistantContentOpacity
        self.onLayoutChange = onLayoutChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rebuildRoleLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        message: AiMessage,
        isStreaming: Bool,
        assistantContentOpacity: CGFloat
    ) {
        let previousMessage = currentMessage
        let previousOpacity = self.assistantContentOpacity

        guard message != previousMessage ||
                isStreaming != self.isStreaming ||
                abs(assistantContentOpacity - previousOpacity) > 0.001 else {
            return
        }

        currentMessage = message
        self.isStreaming = isStreaming
        self.assistantContentOpacity = assistantContentOpacity

        guard message.role == previousMessage.role else {
            rebuildRoleLayout()
            return
        }

        switch message.role {
        case .assistant:
            updateAssistantContent(
                previousMessage: previousMessage,
                previousOpacity: previousOpacity
            )
        case .user:
            if message != previousMessage {
                rebuildRoleLayout()
            }
        case .system:
            break
        }
    }

    private func rebuildRoleLayout() {
        contentRoot?.removeFromSuperview()
        contentRoot = nil
        reasoningView = nil
        assistantBodyView = nil
        assistantMarkdownView = nil

        let root: NSView
        switch currentMessage.role {
        case .user:
            root = makeUserView()
        case .assistant:
            root = makeAssistantView()
        case .system:
            root = NSView()
        }
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        root.pinEdges(to: self)
        contentRoot = root
        onLayoutChange()
    }

    private func makeUserView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let bubble = RoundedSurfaceView(
            cornerRadius: 12,
            backgroundColor: AppTheme.mutedBg
        )

        let text = AutoHeightTextView()
        text.font = AppFont.body(ofSize: 13)
        text.textColor = AppTheme.textPrimary
        text.string = currentMessage.content
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        text.defaultParagraphStyle = paragraph

        bubble.addSubview(text)
        root.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: root.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 56),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.84),

            text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9),
        ])
        return root
    }

    private func shouldShowReasoning(for message: AiMessage, streaming: Bool) -> Bool {
        !message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (streaming && message.expectsReasoning)
    }

    /// 菊花表示"正在思考":请求仍在流式且回答正文尚未开始输出。
    /// 推理结束、正文开始流式后应停止,不等整个请求结束。
    private func isReasoningActive(for message: AiMessage) -> Bool {
        isStreaming && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeAssistantView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        stack.pinEdges(to: root)

        let showReasoning = shouldShowReasoning(for: currentMessage, streaming: isStreaming)
        if showReasoning {
            let disclosure = AiReasoningDisclosureView(
                text: currentMessage.reasoning,
                isThinkingActive: isReasoningActive(for: currentMessage),
                onLayoutChange: onLayoutChange
            )
            reasoningView = disclosure
            stack.addArrangedSubview(disclosure)
            disclosure.constrainWidth(to: stack)
        }

        if !currentMessage.content.isEmpty {
            let body = makeAssistantMarkdownBody()
            assistantBodyView = body
            assistantMarkdownView = body
            stack.addArrangedSubview(body)
            body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else if isStreaming && !showReasoning {
            let thinking = ThinkingIndicatorView()
            assistantBodyView = thinking
            stack.addArrangedSubview(thinking)
        }
        return root
    }

    private func updateAssistantContent(
        previousMessage: AiMessage,
        previousOpacity: CGFloat
    ) {
        guard let stack = contentRoot?.subviews.compactMap({ $0 as? NSStackView }).first else {
            rebuildRoleLayout()
            return
        }

        var needsImmediateLayout = false
        let showReasoning = shouldShowReasoning(for: currentMessage, streaming: isStreaming)

        if !showReasoning {
            if let reasoningView {
                stack.removeArrangedSubview(reasoningView)
                reasoningView.removeFromSuperview()
                self.reasoningView = nil
                needsImmediateLayout = true
            }
        } else if let reasoningView {
            if reasoningView.update(
                text: currentMessage.reasoning,
                isThinkingActive: isReasoningActive(for: currentMessage)
            ) {
                needsImmediateLayout = true
            }
        } else {
            let disclosure = AiReasoningDisclosureView(
                text: currentMessage.reasoning,
                isThinkingActive: isReasoningActive(for: currentMessage),
                onLayoutChange: onLayoutChange
            )
            reasoningView = disclosure
            stack.insertArrangedSubview(disclosure, at: 0)
            disclosure.constrainWidth(to: stack)
            needsImmediateLayout = true
        }

        let contentChanged = currentMessage.content != previousMessage.content
        let opacityChanged = abs(assistantContentOpacity - previousOpacity) > 0.001

        if currentMessage.content.isEmpty {
            if isStreaming && !showReasoning {
                if !(assistantBodyView is ThinkingIndicatorView) {
                    replaceAssistantBody(in: stack, with: ThinkingIndicatorView())
                    needsImmediateLayout = true
                }
            } else if let assistantBodyView {
                stack.removeArrangedSubview(assistantBodyView)
                assistantBodyView.removeFromSuperview()
                self.assistantBodyView = nil
                assistantMarkdownView = nil
                needsImmediateLayout = true
            }
        } else if let markdown = assistantMarkdownView,
                  assistantBodyView === markdown {
            if contentChanged {
                markdown.update(text: currentMessage.content)
            }
            if opacityChanged {
                markdown.alphaValue = assistantContentOpacity
            }
        } else {
            let body = makeAssistantMarkdownBody()
            replaceAssistantBody(in: stack, with: body)
            needsImmediateLayout = true
        }

        if needsImmediateLayout {
            onLayoutChange()
        }
    }

    private func replaceAssistantBody(in stack: NSStackView, with body: NSView) {
        if let assistantBodyView {
            stack.removeArrangedSubview(assistantBodyView)
            assistantBodyView.removeFromSuperview()
        }
        assistantBodyView = body
        assistantMarkdownView = body as? MarkdownWithCodeBlocksView
        body.alphaValue = assistantContentOpacity
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeAssistantMarkdownBody() -> MarkdownWithCodeBlocksView {
        let body = MarkdownWithCodeBlocksView(
            text: currentMessage.content,
            textColor: AppTheme.textPrimary,
            fontSize: 13,
            onLayoutChange: onLayoutChange
        )
        body.alphaValue = assistantContentOpacity
        return body
    }
}

@MainActor
private final class AiReasoningDisclosureView: NSView {
    private var text: String
    private var isThinkingActive: Bool
    private let onLayoutChange: () -> Void
    private var isExpanded = false

    private let stack = NSStackView()
    private let spinner = NSProgressIndicator()
    private var bodyView: NSView?
    private var markdownBodyView: MarkdownWithCodeBlocksView?
    private var collapseFooter: NSView?
    private var expandedWidthConstraint: NSLayoutConstraint?
    private var expandedStackTrailingConstraint: NSLayoutConstraint?

    init(text: String, isThinkingActive: Bool, onLayoutChange: @escaping () -> Void) {
        self.text = text
        self.isThinkingActive = isThinkingActive
        self.onLayoutChange = onLayoutChange
        super.init(frame: .zero)
        appearance = AppTheme.windowAppearance
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        buildUI()
        refreshHeader()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func constrainWidth(to parent: NSView) {
        widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor).isActive = true
        let expanded = widthAnchor.constraint(equalTo: parent.widthAnchor)
        expanded.priority = .required
        expanded.isActive = isExpanded
        expandedWidthConstraint = expanded
    }

    @discardableResult
    func update(text: String, isThinkingActive: Bool) -> Bool {
        let oldText = self.text
        let textChanged = text != oldText
        let emptyStateChanged = oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty !=
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        self.text = text
        self.isThinkingActive = isThinkingActive
        refreshHeader()

        guard isExpanded else { return false }

        if emptyStateChanged {
            rebuildExpandedBody()
            return true
        }

        if textChanged, let markdownBodyView {
            markdownBodyView.update(text: text)
        }
        return false
    }

    private func buildUI() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Only when expanded does the stack stretch to the full card width so
        // the reasoning body aligns with the assistant answer below it. While
        // collapsed the disclosure hugs the pill button plus spinner.
        expandedStackTrailingConstraint = stack.trailingAnchor
            .constraint(equalTo: trailingAnchor)

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 7
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.setContentHuggingPriority(.required, for: .horizontal)

        // 非按钮样式:无边框纯文字,灰色小字 + 箭头(SF Symbol,按钮内自动垂直居中),
        // spinner 是右侧独立 sibling。
        let button = NSButton(
            title: "思考过程",
            target: self,
            action: #selector(toggleExpanded)
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = AppTheme.windowAppearance
        button.isBordered = false
        button.font = AppFont.ui(ofSize: 11, weight: .medium)
        button.setHaxTitle(
            "思考过程",
            color: AppTheme.textSecondary.withAlphaComponent(0.72),
            font: AppFont.ui(ofSize: 11, weight: .medium)
        )
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageTrailing
        button.imageScaling = .scaleNone
        button.contentTintColor = AppTheme.textSecondary.withAlphaComponent(0.72)
        button.focusRingType = .none
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setAccessibilityLabel("思考过程")
        headerRow.addArrangedSubview(button)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 12).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 12).isActive = true

        headerRow.addArrangedSubview(spinner)
        stack.addArrangedSubview(headerRow)
    }

    private func refreshHeader() {
        if isThinkingActive {
            spinner.startAnimation(nil)
            spinner.isHidden = false
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        if let headerRow = stack.arrangedSubviews.first,
           let button = headerRow.subviews.compactMap({ $0 as? NSButton }).first {
            button.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )
        }
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        expandedWidthConstraint?.isActive = isExpanded
        expandedStackTrailingConstraint?.isActive = isExpanded
        refreshHeader()
        if isExpanded {
            rebuildExpandedBody()
        } else {
            removeExpandedBody()
        }
        onLayoutChange()
    }

    private func removeExpandedBody() {
        if let bodyView {
            stack.removeArrangedSubview(bodyView)
            bodyView.removeFromSuperview()
            self.bodyView = nil
        }
        markdownBodyView = nil
        if let collapseFooter {
            stack.removeArrangedSubview(collapseFooter)
            collapseFooter.removeFromSuperview()
            self.collapseFooter = nil
        }
    }

    private func rebuildExpandedBody() {
        removeExpandedBody()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: NSView

        if trimmed.isEmpty {
            body = NSTextField.haxLabel(
                isThinkingActive ? "正在思考…" : "暂无思考内容",
                font: AppFont.ui(ofSize: 11.5),
                color: AppTheme.textSecondary.withAlphaComponent(0.58)
            )
        } else {
            // 思考内容用深色圆角卡片承载,与正文输出明确区分;
            // 左侧竖条是"思考中"的视觉锚点
            let card = RoundedSurfaceView(
                cornerRadius: 10,
                backgroundColor: NSColor(hex: 0x1A1B1E)
            )

            let stripe = NSView()
            stripe.translatesAutoresizingMaskIntoConstraints = false
            stripe.wantsLayer = true
            stripe.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            stripe.layer?.cornerRadius = 1.5
            stripe.layer?.cornerCurve = .continuous
            card.addSubview(stripe)

            let markdown = MarkdownWithCodeBlocksView(
                text: text,
                textColor: NSColor.white.withAlphaComponent(0.72),
                fontSize: 11.5,
                onLayoutChange: onLayoutChange
            )
            card.addSubview(markdown)
            NSLayoutConstraint.activate([
                stripe.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
                stripe.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
                stripe.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
                stripe.widthAnchor.constraint(equalToConstant: 1),

                markdown.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                markdown.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                markdown.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
                markdown.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
            ])
            markdownBodyView = markdown
            body = card
        }

        bodyView = body
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 0
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addArrangedSubview(NSView())
        let collapse = NSButton.haxTextButton(
            "收起思考过程 ↑",
            target: self,
            action: #selector(toggleExpanded),
            font: AppFont.ui(ofSize: 10.5, weight: .medium),
            color: AppTheme.textSecondary.withAlphaComponent(0.70)
        )
        footer.addArrangedSubview(collapse)
        collapseFooter = footer
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

private final class ThinkingIndicatorView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = NSTextField.haxLabel("正在思考…", font: AppFont.ui(ofSize: 12), color: AppTheme.textSecondary)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
