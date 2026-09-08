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
        addSubview(scrollView)
        addSubview(inputBar)
        addSubview(returnToLatestButton)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            header.heightAnchor.constraint(equalToConstant: 38),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 11),
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
        // Bounds notifications are synchronous. Hopping into a Task loses
        // isUpdatingDocumentLayout/isProgrammaticScroll and the actual offset
        // that caused the notification, misclassifying layout as user input.
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        scrollView.onUserScrollPositionChanged = { [weak self] in
            self?.userScrollPositionDidChange()
        }
        scrollView.onUserScrollEnded = { [weak self] in
            guard let self, self.followTailState.isFollowingTail else { return }
            self.scheduleDocumentLayout()
        }
        lastObservedOffsetY = scrollView.contentView.bounds.origin.y
    }

    private func render() {
        let requestRevision = viewModel.requestRevision
        if requestRevision != lastRequestRevision {
            lastRequestRevision = requestRevision
            followTailState.requestDidStart()
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
        // Markdown 文本替换与 documentView 增高必须在同一次
        // Core Animation 提交中完成。延迟到下一轮 main queue 会先显示
        // “新文本 + 旧文档高度”，底部被裁剪一帧后再跳到新尾部。
        guard !isUpdatingDocumentLayout,
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0 else {
            scheduleDocumentLayout()
            return
        }
        updateDocumentLayout()
    }

    private func scheduleDocumentLayout() {
        guard !isDocumentLayoutScheduled else { return }
        isDocumentLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDocumentLayoutScheduled = false
            self.updateDocumentLayout()
        }
    }

    private func updateDocumentLayout() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        let oldOrigin = scrollView.contentView.bounds.origin
        // 文档高度变化与滚动位置校正在同一个事务内提交，
        // 避免流式更新露出“先变高、后跟尾”的中间帧。
        CATransaction.begin()
        CATransaction.setValue(true, forKey: kCATransactionDisableActions)
        defer {
            isUpdatingDocumentLayout = false
            CATransaction.commit()
        }
        isUpdatingDocumentLayout = true
        documentView.updateLayout(
            viewportWidth: scrollView.contentSize.width,
            minimumHeight: scrollView.contentSize.height
        )
        scrollView.layoutSubtreeIfNeeded()

        let maxY = maxOffsetY
        let targetY = followTailState.isFollowingTail && !scrollView.isUserScrolling
            ? maxY
            : min(max(0, oldOrigin.y), maxY)
        if abs(scrollView.contentView.bounds.origin.y - targetY) > 0.5 {
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isProgrammaticScroll = false
        }
        lastObservedOffsetY = targetY
        updateReturnToLatestVisibility()
    }

    private var maxOffsetY: CGFloat {
        max(0, documentView.frame.height - scrollView.contentSize.height)
    }

    @objc private func clipBoundsDidChange() {
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

        userScrollPositionDidChange()
    }

    private func userScrollPositionDidChange() {
        guard !isUpdatingDocumentLayout, !isProgrammaticScroll else { return }
        let extentAfter = max(0, maxOffsetY - scrollView.contentView.bounds.origin.y)
        switch followTailState.userScrollPositionDidChange(extentAfter: extentAfter) {
        case .paused:
            break
        case .resumed:
            if !scrollView.isUserScrolling { scheduleDocumentLayout() }
        case .none:
            break
        }
        updateReturnToLatestVisibility()
    }

    private func updateReturnToLatestVisibility() {
        returnToLatestButton.isHidden = followTailState.isFollowingTail
    }

    @objc private func returnToLatest() {
        followTailState.resume()
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

    // Do not snap the last few lines away merely because the user is near the
    // bottom. One point only absorbs fractional AppKit scroll coordinates.
    static let tailTolerance: CGFloat = 1

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

/// Streaming changes the document on the main thread. Keep scrolling on that
/// same geometry instead of letting responsive scrolling use a pre-rendered
/// surface with an older document height at the top/bottom boundary.
private final class ConversationScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    private(set) var isUserScrolling = false
    var onUserScrollPositionChanged: (() -> Void)?
    var onUserScrollEnded: (() -> Void)?
    private var isLiveScrollSession = false
    private var scrollEndTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(liveScrollBegan),
            name: NSScrollView.willStartLiveScrollNotification, object: self)
        center.addObserver(self, selector: #selector(liveScrollMoved),
            name: NSScrollView.didLiveScrollNotification, object: self)
        center.addObserver(self, selector: #selector(liveScrollEnded),
            name: NSScrollView.didEndLiveScrollNotification, object: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        // Claim ownership BEFORE AppKit changes bounds, including legacy
        // wheels and events at a boundary that produce no bounds notification.
        beginUserScroll()
        super.scrollWheel(with: event)
        onUserScrollPositionChanged?()
        if !isLiveScrollSession { scheduleScrollEnd() }
    }

    private func beginUserScroll() {
        scrollEndTimer?.invalidate()
        scrollEndTimer = nil
        isUserScrolling = true
    }

    @objc private func liveScrollBegan() {
        isLiveScrollSession = true
        beginUserScroll()
    }

    @objc private func liveScrollMoved() {
        beginUserScroll()
        onUserScrollPositionChanged?()
        if !isLiveScrollSession { scheduleScrollEnd() }
    }

    @objc private func liveScrollEnded() {
        isLiveScrollSession = false
        scheduleScrollEnd()
    }

    private func scheduleScrollEnd() {
        scrollEndTimer?.invalidate()
        // Bridge finger-up -> momentum-start; also group legacy wheel ticks.
        // Use common modes so this works during AppKit's event tracking.
        let timer = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isUserScrolling = false
                self.scrollEndTimer = nil
                self.onUserScrollEnded?()
            }
        }
        scrollEndTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

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
