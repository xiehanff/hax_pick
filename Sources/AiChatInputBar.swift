import AppKit
import Combine

@MainActor
final class AiChatInputBar: NSView, NSTextViewDelegate {
    private let viewModel: PanelSessionViewModel
    private var observation: AnyCancellable?

    private let inputScrollView = NSScrollView()
    private let inputTextView = NSTextView()
    private let placeholderLabel = NSTextField.haxLabel("", font: .systemFont(ofSize: 13), color: AppTheme.textSecondary.withAlphaComponent(0.45))
    private let newSessionButton = NSButton()
    private let actionButton = NSButton()

    init(viewModel: PanelSessionViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        observation = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor

        let divider = SoftDividerView()
        addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: topAnchor),
        ])

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.applyContinuousCornerRadius(12, background: NSColor.white.withAlphaComponent(0.88))
        card.layer?.borderWidth = 0.75
        card.layer?.borderColor = AppTheme.border.cgColor
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            card.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 9),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])

        inputScrollView.translatesAutoresizingMaskIntoConstraints = false
        inputScrollView.drawsBackground = false
        inputScrollView.borderType = .noBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.autohidesScrollers = true

        inputTextView.delegate = self
        inputTextView.drawsBackground = false
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.textColor = AppTheme.textPrimary
        inputTextView.isRichText = false
        inputTextView.isHorizontallyResizable = false
        inputTextView.isVerticallyResizable = true
        inputTextView.textContainerInset = NSSize(width: 0, height: 2)
        inputTextView.textContainer?.lineFragmentPadding = 0
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.containerSize = NSSize(width: 0, height: .greatestFiniteMagnitude)
        inputScrollView.documentView = inputTextView

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        newSessionButton.translatesAutoresizingMaskIntoConstraints = false
        newSessionButton.isBordered = false
        newSessionButton.focusRingType = .none
        newSessionButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建自由会话")
        newSessionButton.imagePosition = .imageOnly
        newSessionButton.contentTintColor = AppTheme.textSecondary
        newSessionButton.target = self
        newSessionButton.action = #selector(startNewSession)
        newSessionButton.toolTip = "新建自由会话"
        newSessionButton.wantsLayer = true
        newSessionButton.layer?.backgroundColor = AppTheme.mutedBg.withAlphaComponent(0.48).cgColor
        newSessionButton.layer?.cornerRadius = 8

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isBordered = false
        actionButton.focusRingType = .none
        actionButton.imagePosition = .imageOnly
        actionButton.contentTintColor = AppTheme.textPrimary
        actionButton.target = self
        actionButton.action = #selector(primaryAction)

        card.addSubview(inputScrollView)
        card.addSubview(placeholderLabel)
        card.addSubview(newSessionButton)
        card.addSubview(actionButton)

        NSLayoutConstraint.activate([
            inputScrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            inputScrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            inputScrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            inputScrollView.heightAnchor.constraint(equalToConstant: 42),

            placeholderLabel.leadingAnchor.constraint(equalTo: inputScrollView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: inputScrollView.topAnchor, constant: 3),

            newSessionButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            newSessionButton.topAnchor.constraint(equalTo: inputScrollView.bottomAnchor, constant: 6),
            newSessionButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            newSessionButton.widthAnchor.constraint(equalToConstant: 28),
            newSessionButton.heightAnchor.constraint(equalToConstant: 28),

            actionButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            actionButton.centerYAnchor.constraint(equalTo: newSessionButton.centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 28),
            actionButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func textDidChange(_ notification: Notification) {
        viewModel.followUpInput = inputTextView.string
        refreshActionButton()
        refreshPlaceholder()
    }

    private func refresh() {
        if inputTextView.string != viewModel.followUpInput {
            inputTextView.string = viewModel.followUpInput
        }
        inputTextView.isEditable = !viewModel.isLoading
        inputTextView.isSelectable = true
        newSessionButton.isEnabled = viewModel.canStartNewConversation
        refreshPlaceholder()
        refreshActionButton()
    }

    private func refreshPlaceholder() {
        placeholderLabel.stringValue = viewModel.isLoading
            ? "正在生成…"
            : (viewModel.isFreeChat ? "想聊什么都可以…" : "继续提问…")
        placeholderLabel.isHidden = !inputTextView.string.isEmpty
    }

    private func refreshActionButton() {
        if viewModel.isLoading {
            actionButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "停止生成")
            actionButton.contentTintColor = AppTheme.textPrimary
            actionButton.alphaValue = 1
            actionButton.isEnabled = viewModel.canStop
            actionButton.toolTip = "停止生成"
        } else {
            actionButton.image = HaxIconAsset.send.image
            actionButton.contentTintColor = AppTheme.textPrimary
            actionButton.isEnabled = viewModel.canSubmitFollowUp
            actionButton.alphaValue = viewModel.canSubmitFollowUp ? 1 : 0.32
            actionButton.toolTip = "发送"
        }
    }

    @objc private func startNewSession() {
        viewModel.startNewConversation()
        inputTextView.string = ""
        viewModel.followUpInput = ""
        refresh()
        window?.makeFirstResponder(inputTextView)
    }

    @objc private func primaryAction() {
        if viewModel.isLoading {
            viewModel.stopGeneration()
        } else {
            viewModel.submitFollowUp()
            inputTextView.string = viewModel.followUpInput
        }
        refresh()
    }
}
