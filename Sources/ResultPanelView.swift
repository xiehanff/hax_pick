import AppKit
import Combine

@MainActor
final class ResultPanelView: NSView {
    private let viewModel: PanelSessionViewModel
    private var observation: AnyCancellable?

    private let headerTitle = NSTextField.haxLabel("", font: .systemFont(ofSize: 13.5, weight: .semibold))
    private let statusDot = NSView()
    private let statusLabel = NSTextField.haxLabel("", font: .systemFont(ofSize: 9.5, weight: .medium), color: AppTheme.textSecondary)
    private let closeButton = NSButton()

    private let scrollView = ConversationScrollView()
    private let documentView = ConversationDocumentView()
    private let returnToLatestButton = NSButton()
    private let inputBar: AiChatInputBar

    private var followTailState = ChatFollowTailState()
    private var messageViews: [UUID: AiMessageBubble] = [:]
    private var currentStructure: [String] = []
    private var lastRequestRevision: Int
    private var isProgrammaticScroll = false
    private var isUpdatingDocumentLayout = false
    private var lastObservedOffsetY: CGFloat = 0
    private var boundsObserver: NSObjectProtocol?

    init(viewModel: PanelSessionViewModel) {
        self.viewModel = viewModel
        self.inputBar = AiChatInputBar(viewModel: viewModel)
        self.lastRequestRevision = viewModel.requestRevision
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        installScrollObservation()
        observation = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func layout() {
        super.layout()
        updateDocumentLayout(preserveUserOffset: !followTailState.isFollowingTail)
    }

    private func buildUI() {
        wantsLayer = true
        applyContinuousCornerRadius(
            AppTheme.resultCorner - AppTheme.glassContentInset,
            background: AppTheme.panelContent
        )
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor

        let header = makeHeader()
        let divider = SoftDividerView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        returnToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        returnToLatestButton.title = "↓  回到最新"
        returnToLatestButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        returnToLatestButton.bezelStyle = .rounded
        returnToLatestButton.target = self
        returnToLatestButton.action = #selector(returnToLatest)
        returnToLatestButton.isHidden = true

        addSubview(header)
        addSubview(divider)
        addSubview(scrollView)
        addSubview(inputBar)
        addSubview(returnToLatestButton)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            header.heightAnchor.constraint(equalToConstant: 38),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            returnToLatestButton.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            returnToLatestButton.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -10),
        ])
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(AppBrandIconView(size: 28))

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.addArrangedSubview(headerTitle)

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 2.75
        statusDot.widthAnchor.constraint(equalToConstant: 5.5).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 5.5).isActive = true
        statusRow.addArrangedSubview(statusDot)
        statusRow.addArrangedSubview(statusLabel)
        textStack.addArrangedSubview(statusRow)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.focusRingType = .none
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        closeButton.layer?.cornerRadius = 14
        closeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        row.addArrangedSubview(closeButton)
        return row
    }

    private func installScrollObservation() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clipBoundsDidChange()
            }
        }
        lastObservedOffsetY = scrollView.contentView.bounds.origin.y
    }

    private func render() {
        let requestRevision = viewModel.requestRevision
        if requestRevision != lastRequestRevision {
            lastRequestRevision = requestRevision
            followTailState.requestDidStart()
            viewModel.resumeStreamingPresentation()
        }

        refreshHeader()
        syncConversationRows()
        updateReturnToLatestVisibility()
        updateDocumentLayout(preserveUserOffset: !followTailState.isFollowingTail)

        if followTailState.isFollowingTail {
            scrollToBottom()
        }
    }

    private func refreshHeader() {
        headerTitle.stringValue = viewModel.currentAction?.rawValue ?? "AI 对话"
        headerTitle.textColor = viewModel.currentAction == .deepDive
            ? AppTheme.textPrimary.withAlphaComponent(0.78)
            : AppTheme.textPrimary
        statusLabel.stringValue = viewModel.statusHint
        let color: NSColor
        if viewModel.errorMessage != nil {
            color = .systemOrange
        } else if viewModel.isLoading {
            color = AppTheme.accent
        } else if viewModel.didStop {
            color = .systemOrange
        } else {
            color = AppTheme.success
        }
        statusDot.layer?.backgroundColor = color.cgColor
    }

    private func syncConversationRows() {
        let messages = viewModel.conversationMessages
        let validIDs = Set(messages.map(\.id))
        messageViews = messageViews.filter { validIDs.contains($0.key) }

        var desiredViews: [NSView] = []
        var structure: [String] = []

        if viewModel.showsSourceTurn {
            desiredViews.append(SourceTurnView(viewModel: viewModel))
            structure.append("source:\(viewModel.requestRevision):\(viewModel.isOriginalExpanded)")
        }

        for message in messages where message.role != .system {
            let isStreaming = message.id == viewModel.streamingAssistantID
            let opacity: CGFloat = viewModel.currentAction == .deepDive ? 0.78 : 1
            let bubble: AiMessageBubble
            if let existing = messageViews[message.id] {
                existing.update(
                    message: message,
                    isStreaming: isStreaming,
                    assistantContentOpacity: opacity
                )
                bubble = existing
            } else {
                bubble = AiMessageBubble(
                    message: message,
                    isStreaming: isStreaming,
                    assistantContentOpacity: opacity,
                    onLayoutChange: { [weak self] in
                        DispatchQueue.main.async { self?.messageLayoutDidChange() }
                    }
                )
                messageViews[message.id] = bubble
            }
            desiredViews.append(bubble)
            structure.append("message:\(message.id.uuidString)")
        }

        if viewModel.isLoading && viewModel.streamingAssistantID == nil {
            desiredViews.append(PanelThinkingView())
            structure.append("thinking")
        }

        if let error = viewModel.errorMessage {
            desiredViews.append(ErrorBubbleView(text: error))
            structure.append("error:\(error)")
        }

        if !viewModel.isLoading && !viewModel.suggestions.isEmpty {
            desiredViews.append(FollowUpSuggestionsView(suggestions: viewModel.suggestions) { [weak self] text in
                self?.viewModel.askSuggestion(text)
            })
            structure.append("suggestions:\(viewModel.suggestions.joined(separator: "|"))")
        }

        if !viewModel.isLoading && (viewModel.lastAssistantContent != nil || viewModel.canRetry) {
            desiredViews.append(AssistantActionsView(viewModel: viewModel))
            structure.append("actions:\(viewModel.canRetry):\(viewModel.lastAssistantContent != nil)")
        }

        if structure != currentStructure {
            currentStructure = structure
            documentView.setRows(desiredViews)
        }
    }

    private func messageLayoutDidChange() {
        updateDocumentLayout(preserveUserOffset: !followTailState.isFollowingTail)
        if followTailState.isFollowingTail {
            scrollToBottom()
        }
    }

    private func updateDocumentLayout(preserveUserOffset: Bool) {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        let oldOrigin = scrollView.contentView.bounds.origin
        isUpdatingDocumentLayout = true
        documentView.updateLayout(
            viewportWidth: scrollView.contentSize.width,
            minimumHeight: scrollView.contentSize.height
        )
        scrollView.layoutSubtreeIfNeeded()

        if preserveUserOffset {
            let maxY = maxOffsetY
            let clamped = min(max(0, oldOrigin.y), maxY)
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isProgrammaticScroll = false
            lastObservedOffsetY = clamped
        }
        isUpdatingDocumentLayout = false
    }

    private var maxOffsetY: CGFloat {
        max(0, documentView.frame.height - scrollView.contentSize.height)
    }

    private func clipBoundsDidChange() {
        let newY = scrollView.contentView.bounds.origin.y
        let oldY = lastObservedOffsetY
        lastObservedOffsetY = newY
        guard !isProgrammaticScroll, !isUpdatingDocumentLayout, abs(newY - oldY) > 0.5 else {
            return
        }

        followTailState.userDidScroll()
        viewModel.pauseStreamingPresentation()

        let movingTowardTail = newY > oldY
        let extentAfter = max(0, maxOffsetY - newY)
        if followTailState.tailPositionDidChange(
            extentAfter: extentAfter,
            movingTowardTail: movingTowardTail
        ) {
            viewModel.resumeStreamingPresentation()
            scrollToBottom()
        }
        updateReturnToLatestVisibility()
    }

    private func scrollToBottom() {
        guard followTailState.isFollowingTail else { return }
        updateDocumentLayout(preserveUserOffset: false)
        let y = maxOffsetY
        isProgrammaticScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
        lastObservedOffsetY = y
        updateReturnToLatestVisibility()
    }

    private func updateReturnToLatestVisibility() {
        returnToLatestButton.isHidden = followTailState.isFollowingTail
    }

    @objc private func returnToLatest() {
        followTailState.resume()
        viewModel.resumeStreamingPresentation()
        render()
        scrollToBottom()
    }

    @objc private func closePanel() {
        viewModel.close()
    }
}

struct ChatFollowTailState: Equatable {
    private(set) var isFollowingTail = true
    static let resumeThreshold: CGFloat = 80

    mutating func userDidScroll() {
        guard isFollowingTail else { return }
        isFollowingTail = false
    }

    mutating func requestDidStart() {
        isFollowingTail = true
    }

    mutating func resume() {
        isFollowingTail = true
    }

    @discardableResult
    mutating func tailPositionDidChange(
        extentAfter: CGFloat,
        movingTowardTail: Bool
    ) -> Bool {
        guard !isFollowingTail,
              movingTowardTail,
              extentAfter.isFinite,
              extentAfter <= Self.resumeThreshold else {
            return false
        }
        isFollowingTail = true
        return true
    }
}

private final class ConversationScrollView: NSScrollView {}

private final class ConversationDocumentView: NSView {
    private let stack = NSStackView()
    private var rowWidthConstraints: [NSLayoutConstraint] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRows(_ rows: [NSView]) {
        NSLayoutConstraint.deactivate(rowWidthConstraints)
        rowWidthConstraints.removeAll()
        for old in stack.arrangedSubviews {
            stack.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            rowWidthConstraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(rowWidthConstraints)
    }

    func updateLayout(viewportWidth: CGFloat, minimumHeight: CGFloat) {
        let width = max(1, viewportWidth)
        if abs(frame.width - width) > 0.5 {
            frame.size.width = width
        }
        layoutSubtreeIfNeeded()
        let contentHeight = stack.fittingSize.height + 28
        let height = max(minimumHeight, contentHeight)
        if abs(frame.height - height) > 0.5 {
            frame.size.height = height
            layoutSubtreeIfNeeded()
        }
    }
}

@MainActor
private final class SourceTurnView: NSView {
    private let viewModel: PanelSessionViewModel

    init(viewModel: PanelSessionViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyContinuousCornerRadius(12, background: NSColor(hex: 0x303136, alpha: 0.96))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        let action = NSTextField.haxLabel(
            viewModel.currentAction?.rawValue ?? "原文",
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.56)
        )
        stack.addArrangedSubview(action)

        let text = AutoHeightTextView()
        text.font = .systemFont(ofSize: 12.5)
        text.textColor = NSColor.white.withAlphaComponent(0.82)
        let source = viewModel.selectedText
        if !viewModel.isOriginalExpanded && source.count > 360 {
            text.string = String(source.prefix(360)) + "…"
        } else {
            text.string = source
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        text.defaultParagraphStyle = paragraph
        stack.addArrangedSubview(text)
        text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if source.count > 180 {
            let button = NSButton(
                title: viewModel.isOriginalExpanded ? "收起" : "展开原文",
                target: self,
                action: #selector(toggleOriginal)
            )
            button.isBordered = false
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.contentTintColor = NSColor.white.withAlphaComponent(0.70)
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleOriginal() {
        viewModel.toggleOriginalExpanded()
    }
}

private final class PanelThinkingView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        row.addArrangedSubview(spinner)
        row.addArrangedSubview(NSTextField.haxLabel("正在思考…", font: .systemFont(ofSize: 12), color: AppTheme.textSecondary))
        addSubview(row)
        row.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ErrorBubbleView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyContinuousCornerRadius(10, background: AppTheme.mutedBg)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(NSTextField.haxLabel("⚠ 请求失败", font: .systemFont(ofSize: 11.5, weight: .semibold), color: .systemOrange))
        stack.addArrangedSubview(NSTextField.haxLabel(text, font: .systemFont(ofSize: 11.5), color: AppTheme.textSecondary))
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class FollowUpSuggestionsView: NSView {
    init(suggestions: [String], onTap: @escaping (String) -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(NSTextField.haxLabel("继续追问", font: .systemFont(ofSize: 10, weight: .semibold), color: AppTheme.textSecondary))

        for suggestion in suggestions {
            let button = SuggestionButton(title: suggestion, action: { onTap(suggestion) })
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SuggestionButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 10.5)
        contentTintColor = AppTheme.textSecondary
        alignment = .left
        target = self
        self.action = #selector(runHandler)
        wantsLayer = true
        layer?.backgroundColor = AppTheme.mutedBg.withAlphaComponent(0.64).cgColor
        layer?.cornerRadius = 13
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}

@MainActor
private final class AssistantActionsView: NSView {
    init(viewModel: PanelSessionViewModel) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let retry = ClosureButton(title: "↻ 重新生成") { [weak viewModel] in
            viewModel?.retry()
        }
        retry.isEnabled = viewModel.canRetry
        let copy = ClosureButton(title: "复制回答") { [weak viewModel] in
            viewModel?.copyResult()
        }
        copy.image = HaxIconAsset.copy.image
        copy.imagePosition = .imageLeading
        copy.isEnabled = viewModel.lastAssistantContent != nil

        row.addArrangedSubview(retry)
        row.addArrangedSubview(copy)
        row.addArrangedSubview(NSView())
        addSubview(row)
        row.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 10.5, weight: .medium)
        contentTintColor = AppTheme.textSecondary
        target = self
        action = #selector(runHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}
