import AppKit
import Combine

@MainActor
final class ResultPanelView: NSView {
    private let viewModel: PanelSessionViewModel
    private var observation: AnyCancellable?

    private let headerTitle = NSTextField.haxLabel("", font: AppFont.ui(ofSize: 13.5, weight: .semibold))
    private let statusDot = NSView()
    private let statusLabel = NSTextField.haxLabel("", font: AppFont.ui(ofSize: 9.5, weight: .medium), color: AppTheme.textSecondary)
    private lazy var closeButton = CircleIconButton(
        symbolName: "xmark",
        accessibilityDescription: "关闭",
        size: 28,
        backgroundColor: NSColor.black.withAlphaComponent(0.86),
        tintColor: .white,
        target: self,
        action: #selector(closePanel)
    )

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
    private var isDocumentLayoutScheduled = false
    private var lastScrollViewportSize = NSSize.zero
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
        let viewportSize = scrollView.bounds.size
        guard abs(viewportSize.width - lastScrollViewportSize.width) > 0.5 ||
                abs(viewportSize.height - lastScrollViewportSize.height) > 0.5 else {
            return
        }
        lastScrollViewportSize = viewportSize
        scheduleDocumentLayout()
    }

    private func buildUI() {
        wantsLayer = true
        // 同心圆角:内圆角 = 外圆角 - 玻璃外缘宽度
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
        // Rubber-band overscroll changes NSClipView.bounds beyond 0/max. During
        // streaming that used to fight follow-tail correction and caused the
        // entire conversation to flash at the top/bottom boundary.
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = documentView

        returnToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        returnToLatestButton.appearance = AppTheme.windowAppearance
        returnToLatestButton.title = "↓  回到最新"
        returnToLatestButton.font = AppFont.ui(ofSize: 10.5, weight: .medium)
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
            returnToLatestButton.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -10),        ])
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
        let structureChanged = syncConversationRows()
        updateReturnToLatestVisibility()

        // Text snapshots now render through the persistent Markdown view. Its
        // async parse callback schedules layout only when the actual attributed
        // geometry changes; a normal 40ms token notification no longer forces a
        // redundant document pass.
        if structureChanged {
            scheduleDocumentLayout()
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

    @discardableResult
    private func syncConversationRows() -> Bool {
        let messages = viewModel.conversationMessages
        let visibleMessages = messages.filter { $0.role != .system }
        let validIDs = Set(visibleMessages.map(\.id))
        messageViews = messageViews.filter { validIDs.contains($0.key) }

        var structure: [String] = []

        for message in visibleMessages {
            let isStreaming = message.id == viewModel.streamingAssistantID
            let opacity: CGFloat = viewModel.currentAction == .deepDive ? 0.78 : 1
            if let existing = messageViews[message.id] {
                existing.update(
                    message: message,
                    isStreaming: isStreaming,
                    assistantContentOpacity: opacity
                )
            } else {
                let bubble = AiMessageBubble(
                    message: message,
                    isStreaming: isStreaming,
                    assistantContentOpacity: opacity,
                    onLayoutChange: { [weak self] in
                        self?.messageLayoutDidChange()
                    }
                )
                messageViews[message.id] = bubble
            }
            structure.append("message:\(message.id.uuidString)")
        }

        if viewModel.isLoading && viewModel.streamingAssistantID == nil {
            structure.append("thinking")
        }
        if let error = viewModel.errorMessage {
            structure.append("error:\(error)")
        }
        if !viewModel.isLoading && !viewModel.suggestions.isEmpty {
            structure.append("suggestions:\(viewModel.suggestions.joined(separator: "|"))")
        }
        if !viewModel.isLoading && (viewModel.lastAssistantContent != nil || viewModel.canRetry) {
            structure.append("actions:\(viewModel.canRetry):\(viewModel.lastAssistantContent != nil)")
        }

        guard structure != currentStructure else { return false }
        currentStructure = structure

        var desiredViews: [NSView] = []
        for message in visibleMessages {
            if let bubble = messageViews[message.id] {
                desiredViews.append(bubble)
            }
        }
        if viewModel.isLoading && viewModel.streamingAssistantID == nil {
            desiredViews.append(PanelThinkingView())
        }
        if let error = viewModel.errorMessage {
            desiredViews.append(ErrorBubbleView(text: error))
        }
        if !viewModel.isLoading && !viewModel.suggestions.isEmpty {
            desiredViews.append(FollowUpSuggestionsView(suggestions: viewModel.suggestions) { [weak self] text in
                self?.viewModel.askSuggestion(text)
            })
        }
        if !viewModel.isLoading && (viewModel.lastAssistantContent != nil || viewModel.canRetry) {
            desiredViews.append(AssistantActionsView(viewModel: viewModel))
        }
        documentView.setRows(desiredViews)
        return true
    }

    private func messageLayoutDidChange() {
        scheduleDocumentLayout()
    }

    private func scheduleDocumentLayout() {
        guard !isDocumentLayoutScheduled else { return }
        isDocumentLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDocumentLayoutScheduled = false
            self.updateDocumentLayout(preserveUserOffset: !self.followTailState.isFollowingTail)
            if self.followTailState.isFollowingTail {
                self.scrollToBottom()
            }
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
            if abs(scrollView.contentView.bounds.origin.y - clamped) > 0.5 {
                isProgrammaticScroll = true
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                isProgrammaticScroll = false
            }
            lastObservedOffsetY = clamped
        }
        isUpdatingDocumentLayout = false
    }

    private var maxOffsetY: CGFloat {
        max(0, documentView.frame.height - scrollView.contentSize.height)
    }

    private func clipBoundsDidChange() {
        let rawY = scrollView.contentView.bounds.origin.y
        let maxY = maxOffsetY
        let newY = min(max(0, rawY), maxY)
        let oldY = lastObservedOffsetY
        lastObservedOffsetY = newY

        guard !isProgrammaticScroll,
              !isUpdatingDocumentLayout,
              abs(newY - oldY) > 0.5 else {
            return
        }

        let extentAfter = max(0, maxY - newY)
        switch followTailState.userScrollPositionDidChange(extentAfter: extentAfter) {
        case .paused:
            viewModel.pauseStreamingPresentation()
        case .resumed:
            viewModel.resumeStreamingPresentation()
            scheduleDocumentLayout()
        case .none:
            break
        }
        updateReturnToLatestVisibility()
    }

    private func scrollToBottom() {
        guard followTailState.isFollowingTail else { return }
        let y = maxOffsetY
        let currentY = min(max(0, scrollView.contentView.bounds.origin.y), y)

        if abs(currentY - y) > 0.5 {
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isProgrammaticScroll = false
        }
        lastObservedOffsetY = y
        updateReturnToLatestVisibility()
    }

    private func updateReturnToLatestVisibility() {
        returnToLatestButton.isHidden = followTailState.isFollowingTail
    }

    @objc private func returnToLatest() {
        followTailState.resume()
        viewModel.resumeStreamingPresentation()
        scheduleDocumentLayout()
        updateReturnToLatestVisibility()
    }

    @objc private func closePanel() {
        viewModel.close()
    }
}

enum ChatFollowTailTransition: Equatable {
    case none
    case paused
    case resumed
}

struct ChatFollowTailState: Equatable {
    private(set) var isFollowingTail = true

    static let tailTolerance: CGFloat = 32

    mutating func requestDidStart() {
        isFollowingTail = true
    }

    mutating func resume() {
        isFollowingTail = true
    }

    @discardableResult
    mutating func userScrollPositionDidChange(extentAfter: CGFloat) -> ChatFollowTailTransition {
        guard extentAfter.isFinite else { return .none }
        let isAtTail = max(0, extentAfter) <= Self.tailTolerance

        if isAtTail {
            guard !isFollowingTail else { return .none }
            isFollowingTail = true
            return .resumed
        }

        guard isFollowingTail else { return .none }
        isFollowingTail = false
        return .paused
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
        // documentView 以 frame 驱动宽度,创建瞬间宽度为 0;required 的双边边距
        // 在 0 宽度下不可满足,降到 999 避免 Autolayout 冲突日志。
        let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        // 右侧多留 12pt 给覆盖式垂直滚动条,内容不被 scroller 挡住
        let trailing = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28)
        leading.priority = .init(999)
        trailing.priority = .init(999)
        NSLayoutConstraint.activate([
            leading,
            trailing,
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
        row.addArrangedSubview(NSTextField.haxLabel("正在思考…", font: AppFont.ui(ofSize: 12), color: AppTheme.textSecondary))
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
        stack.addArrangedSubview(NSTextField.haxLabel("⚠ 请求失败", font: AppFont.ui(ofSize: 11.5, weight: .semibold), color: .systemOrange))
        stack.addArrangedSubview(NSTextField.haxLabel(text, font: AppFont.ui(ofSize: 11.5), color: AppTheme.textSecondary))
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
        stack.addArrangedSubview(NSTextField.haxLabel("继续追问", font: AppFont.ui(ofSize: 10, weight: .semibold), color: AppTheme.textSecondary))

        for suggestion in suggestions {
            let button = SuggestionPill(title: suggestion, action: { onTap(suggestion) })
            stack.addArrangedSubview(button)
            // 文本过长时按钮最宽到容器宽度,超出部分尾部省略号
            button.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 建议追问胶囊:背景由外层 view 绘制,内部 NSButton 两侧各留 11pt 内边距,
/// 文本超宽时在按钮宽度内以尾部省略号截断。
private final class SuggestionPill: NSView {
    private var onAction: (() -> Void)?

    init(title: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = AppTheme.windowAppearance
        wantsLayer = true
        layer?.backgroundColor = AppTheme.mutedBg.withAlphaComponent(0.64).cgColor
        layer?.cornerRadius = 13
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = AppTheme.windowAppearance
        button.isBordered = false
        button.focusRingType = .none
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                // 与 Markdown 正文同款:英文 Google Sans Mono、中文 OPPO Sans
                .font: AppFont.body(ofSize: 10.5),
                .foregroundColor: AppTheme.textSecondary,
                .paragraphStyle: paragraph,
            ]
        )
        button.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        onAction = action
        button.target = self
        button.action = #selector(runHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        onAction?()
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
        appearance = AppTheme.windowAppearance
        self.title = title
        isBordered = false
        focusRingType = .none
        font = AppFont.ui(ofSize: 10.5, weight: .medium)
        setHaxTitle(title, color: AppTheme.textSecondary, font: AppFont.ui(ofSize: 10.5, weight: .medium))
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

