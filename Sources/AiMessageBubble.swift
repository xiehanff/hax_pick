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
        let roleChanged = message.role != currentMessage.role
        currentMessage = message
        self.isStreaming = isStreaming
        self.assistantContentOpacity = assistantContentOpacity
        if roleChanged {
            rebuildRoleLayout()
            return
        }

        switch message.role {
        case .assistant:
            updateAssistantContent()
        case .user:
            rebuildRoleLayout()
        case .system:
            break
        }
    }

    private func rebuildRoleLayout() {
        contentRoot?.removeFromSuperview()
        contentRoot = nil
        reasoningView = nil
        assistantBodyView = nil

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

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.applyContinuousCornerRadius(12, background: AppTheme.mutedBg)

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

        let reasoning = currentMessage.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasoning.isEmpty {
            let disclosure = AiReasoningDisclosureView(
                text: reasoning,
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
        } else if isStreaming && reasoning.isEmpty {
            let thinking = ThinkingIndicatorView()
            assistantBodyView = thinking
            stack.addArrangedSubview(thinking)
        }
        return root
    }

    private func updateAssistantContent() {
        guard let stack = contentRoot?.subviews.compactMap({ $0 as? NSStackView }).first else {
            rebuildRoleLayout()
            return
        }

        let reasoning = currentMessage.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if reasoning.isEmpty {
            if let reasoningView {
                stack.removeArrangedSubview(reasoningView)
                reasoningView.removeFromSuperview()
                self.reasoningView = nil
            }
        } else if let reasoningView {
            reasoningView.update(text: reasoning, isStreaming: isStreaming)
        } else {
            let disclosure = AiReasoningDisclosureView(
                text: reasoning,
                isStreaming: isStreaming,
                onLayoutChange: onLayoutChange
            )
            reasoningView = disclosure
            stack.insertArrangedSubview(disclosure, at: 0)
            disclosure.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if let assistantBodyView {
            stack.removeArrangedSubview(assistantBodyView)
            assistantBodyView.removeFromSuperview()
            self.assistantBodyView = nil
        }

        if !currentMessage.content.isEmpty {
            let body = makeAssistantBody()
            assistantBodyView = body
            stack.addArrangedSubview(body)
            body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else if isStreaming && reasoning.isEmpty {
            let thinking = ThinkingIndicatorView()
            assistantBodyView = thinking
            stack.addArrangedSubview(thinking)
        }
        onLayoutChange()
    }

    private func makeAssistantBody() -> NSView {
        let body: NSView
        if isStreaming {
            let text = AutoHeightTextView()
            text.font = .systemFont(ofSize: 13)
            text.textColor = AppTheme.textPrimary
            text.string = currentMessage.content
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 7
            text.defaultParagraphStyle = paragraph
            body = text
        } else {
            body = MarkdownWithCodeBlocksView(
                text: currentMessage.content,
                textColor: AppTheme.textPrimary,
                fontSize: 13
            )
        }
        body.alphaValue = assistantContentOpacity
        return body
    }
}

@MainActor
private final class AiReasoningDisclosureView: NSView {
    private var text: String
    private var isStreaming: Bool
    private let onLayoutChange: () -> Void
    private var isExpanded = false

    private let stack = NSStackView()
    private let spinner = NSProgressIndicator()
    private let chevron = NSImageView()
    private var bodyView: NSView?
    private var collapseButton: NSButton?

    init(text: String, isStreaming: Bool, onLayoutChange: @escaping () -> Void) {
        self.text = text
        self.isStreaming = isStreaming
        self.onLayoutChange = onLayoutChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyContinuousCornerRadius(10, background: AppTheme.mutedBg.withAlphaComponent(0.72))
        layer?.borderWidth = 0.75
        layer?.borderColor = AppTheme.border.withAlphaComponent(0.75).cgColor
        buildUI()
        refreshHeader()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
        refreshHeader()
        if isExpanded {
            rebuildExpandedBody()
        }
    }

    private func buildUI() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
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
            color: AppTheme.textSecondary.withAlphaComponent(0.82)
        )
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 12).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 12).isActive = true
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.contentTintColor = AppTheme.textSecondary.withAlphaComponent(0.82)
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
        if let collapseButton {
            stack.removeArrangedSubview(collapseButton)
            collapseButton.removeFromSuperview()
            self.collapseButton = nil
        }
    }

    private func rebuildExpandedBody() {
        removeExpandedBody()
        let body: NSView
        if isStreaming {
            let textView = AutoHeightTextView()
            textView.font = .systemFont(ofSize: 11.5)
            textView.textColor = AppTheme.textSecondary.withAlphaComponent(0.72)
            textView.string = text
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 5
            textView.defaultParagraphStyle = paragraph
            body = textView
        } else {
            body = MarkdownWithCodeBlocksView(
                text: text,
                textColor: AppTheme.textSecondary.withAlphaComponent(0.72),
                fontSize: 11.5
            )
        }
        bodyView = body
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let collapse = NSButton(title: "收起思考过程  ↑", target: self, action: #selector(toggleExpanded))
        collapse.translatesAutoresizingMaskIntoConstraints = false
        collapse.isBordered = false
        collapse.focusRingType = .none
        collapse.font = .systemFont(ofSize: 10.5, weight: .medium)
        collapse.contentTintColor = AppTheme.textSecondary.withAlphaComponent(0.78)
        collapseButton = collapse
        stack.addArrangedSubview(collapse)
        collapse.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        onLayoutChange()
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
