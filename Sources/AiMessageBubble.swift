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
    private var streamingAssistantTextView: AutoHeightTextView?

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
        let wasStreaming = self.isStreaming
        let previousOpacity = self.assistantContentOpacity

        guard message != previousMessage ||
                isStreaming != wasStreaming ||
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
                wasStreaming: wasStreaming,
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
        streamingAssistantTextView = nil

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
        text.font = .systemFont(ofSize: 13)
        text.textColor = AppTheme.textPrimary
        text.string = currentMessage.content
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
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
                isStreaming: isStreaming,
                onLayoutChange: onLayoutChange
            )
            reasoningView = disclosure
            stack.addArrangedSubview(disclosure)
            disclosure.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if !currentMessage.content.isEmpty {
            let body = makeAssistantBody()
            assistantBodyView = body
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
        wasStreaming: Bool,
        previousOpacity: CGFloat
    ) {
        guard let stack = contentRoot?.subviews.compactMap({ $0 as? NSStackView }).first else {
            rebuildRoleLayout()
            return
        }

        var needsLayout = false
        let showReasoning = shouldShowReasoning(for: currentMessage, streaming: isStreaming)

        if !showReasoning {
            if let reasoningView {
                stack.removeArrangedSubview(reasoningView)
                reasoningView.removeFromSuperview()
                self.reasoningView = nil
                needsLayout = true
            }
        } else if let reasoningView {
            if reasoningView.update(text: currentMessage.reasoning, isStreaming: isStreaming) {
                needsLayout = true
            }
        } else {
            let disclosure = AiReasoningDisclosureView(
                text: currentMessage.reasoning,
                isStreaming: isStreaming,
                onLayoutChange: onLayoutChange
            )
            reasoningView = disclosure
            stack.insertArrangedSubview(disclosure, at: 0)
            disclosure.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            needsLayout = true
        }

        let contentChanged = currentMessage.content != previousMessage.content
        let streamingChanged = isStreaming != wasStreaming
        let opacityChanged = abs(assistantContentOpacity - previousOpacity) > 0.001

        if currentMessage.content.isEmpty {
            if isStreaming && !showReasoning {
                if !(assistantBodyView is ThinkingIndicatorView) {
                    replaceAssistantBody(in: stack, with: ThinkingIndicatorView())
                    needsLayout = true
                }
            } else if let assistantBodyView {
                stack.removeArrangedSubview(assistantBodyView)
                assistantBodyView.removeFromSuperview()
                self.assistantBodyView = nil
                streamingAssistantTextView = nil
                needsLayout = true
            }
        } else if isStreaming {
            if let textView = streamingAssistantTextView,
               assistantBodyView === textView,
               !streamingChanged {
                if contentChanged {
                    textView.string = currentMessage.content
                    textView.invalidateIntrinsicContentSize()
                    needsLayout = true
                }
                if opacityChanged {
                    textView.alphaValue = assistantContentOpacity
                }
            } else {
                let textView = makeStreamingAssistantBody()
                replaceAssistantBody(in: stack, with: textView)
                needsLayout = true
            }
        } else if wasStreaming || contentChanged || assistantBodyView == nil {
            let body = makeCompletedAssistantBody()
            replaceAssistantBody(in: stack, with: body)
            needsLayout = true
        } else if opacityChanged {
            assistantBodyView?.alphaValue = assistantContentOpacity
        }

        if needsLayout {
            onLayoutChange()
        }
    }

    private func replaceAssistantBody(in stack: NSStackView, with body: NSView) {
        if let assistantBodyView {
            stack.removeArrangedSubview(assistantBodyView)
            assistantBodyView.removeFromSuperview()
        }
        assistantBodyView = body
        if let textView = body as? AutoHeightTextView {
            streamingAssistantTextView = textView
        } else {
            streamingAssistantTextView = nil
        }
        body.alphaValue = assistantContentOpacity
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeAssistantBody() -> NSView {
        if isStreaming {
            return makeStreamingAssistantBody()
        }
        return makeCompletedAssistantBody()
    }

    private func makeStreamingAssistantBody() -> AutoHeightTextView {
        let text = AutoHeightTextView()
        text.font = .systemFont(ofSize: 13)
        text.textColor = AppTheme.textPrimary
        text.string = currentMessage.content
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 7
        text.defaultParagraphStyle = paragraph
        text.alphaValue = assistantContentOpacity
        streamingAssistantTextView = text
        return text
    }

    private func makeCompletedAssistantBody() -> MarkdownWithCodeBlocksView {
        let body = MarkdownWithCodeBlocksView(
            text: currentMessage.content,
            textColor: AppTheme.textPrimary,
            fontSize: 13
        )
        body.alphaValue = assistantContentOpacity
        return body
    }
}

@MainActor
private final class AiReasoningDisclosureView: RoundedSurfaceView {
    private var text: String
    private var isStreaming: Bool
    private let onLayoutChange: () -> Void
    private var isExpanded = false

    private let stack = NSStackView()
    private let spinner = NSProgressIndicator()
    private let chevron = NSImageView()
    private var bodyView: NSView?
    private var streamingTextView: AutoHeightTextView?
    private var collapseFooter: NSView?

    init(text: String, isStreaming: Bool, onLayoutChange: @escaping () -> Void) {
        self.text = text
        self.isStreaming = isStreaming
        self.onLayoutChange = onLayoutChange
        super.init(
            cornerRadius: 10,
            backgroundColor: AppTheme.mutedBg.withAlphaComponent(0.62),
            borderColor: AppTheme.border.withAlphaComponent(0.62),
            borderWidth: 0.75
        )
        buildUI()
        refreshHeader()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func update(text: String, isStreaming: Bool) -> Bool {
        let oldText = self.text
        let textChanged = text != oldText
        let streamingChanged = isStreaming != self.isStreaming
        let emptyStateChanged = oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty !=
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        self.text = text
        self.isStreaming = isStreaming
        refreshHeader()

        guard isExpanded else { return false }

        if streamingChanged || emptyStateChanged {
            rebuildExpandedBody()
            return true
        }

        if isStreaming, let streamingTextView {
            guard textChanged else { return false }
            streamingTextView.string = text
            streamingTextView.invalidateIntrinsicContentSize()
            return true
        }

        if textChanged {
            rebuildExpandedBody()
            return true
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
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField.haxLabel(
            "思考过程",
            font: .systemFont(ofSize: 11.5, weight: .medium),
            color: AppTheme.textSecondary.withAlphaComponent(0.72)
        )
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 12).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 12).isActive = true
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.contentTintColor = AppTheme.textSecondary.withAlphaComponent(0.72)
        chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 10).isActive = true

        row.addArrangedSubview(title)
        row.addArrangedSubview(spinner)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(chevron)
        header.addSubview(row)
        row.pinEdges(to: header)

        let button = NSButton(title: "", target: self, action: #selector(toggleExpanded))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = AppTheme.windowAppearance
        button.isBordered = false
        button.focusRingType = .none
        button.setAccessibilityLabel("思考过程")
        header.addSubview(button)
        button.pinEdges(to: header)

        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func refreshHeader() {
        if isStreaming {
            spinner.startAnimation(nil)
            spinner.isHidden = false
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        chevron.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
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
        streamingTextView = nil
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
                isStreaming ? "正在思考…" : "暂无思考内容",
                font: .systemFont(ofSize: 11.5),
                color: AppTheme.textSecondary.withAlphaComponent(0.58)
            )
        } else if isStreaming {
            let textView = AutoHeightTextView()
            textView.font = .systemFont(ofSize: 11.5)
            textView.textColor = AppTheme.textSecondary.withAlphaComponent(0.66)
            textView.string = text
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 5
            textView.defaultParagraphStyle = paragraph
            streamingTextView = textView
            body = textView
        } else {
            body = MarkdownWithCodeBlocksView(
                text: text,
                textColor: AppTheme.textSecondary.withAlphaComponent(0.66),
                fontSize: 11.5
            )
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
            "收起 ↑",
            target: self,
            action: #selector(toggleExpanded),
            font: .systemFont(ofSize: 10.5, weight: .medium),
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
        let label = NSTextField.haxLabel("正在思考…", font: .systemFont(ofSize: 12), color: AppTheme.textSecondary)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}