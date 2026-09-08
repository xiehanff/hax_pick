import AppKit
import Combine

@MainActor
final class FloatingToolbarView: NSView {
    private let viewModel: PanelSessionViewModel
    private var observation: AnyCancellable?
    private var currentMode: PanelSessionViewModel.PanelMode?
    private var surface: HaxGlassView?
    private weak var resumeChatButton: NSButton?
    private lazy var resultPanel = ResultPanelView(viewModel: viewModel)

    init(viewModel: PanelSessionViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        appearance = AppTheme.windowAppearance
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        observation = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshModeIfNeeded() }
        }
        refreshModeIfNeeded(force: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshModeIfNeeded(force: Bool = false) {
        // 气泡入口的可见性跟随归档状态,与 mode 切换解耦
        resumeChatButton?.isHidden = !viewModel.hasResumableConversation
        let mode = viewModel.mode
        guard force || currentMode != mode else { return }
        window?.invalidateCursorRects(for: self)
        currentMode = mode
        surface?.removeFromSuperview()

        let cornerRadius: CGFloat = AppTheme.resultCorner

        // The borderless window itself is transparent. Clip the root content
        // view as well as the glass view so the system never exposes square
        // corners around the custom surface.
        applyContinuousCornerRadius(cornerRadius, background: .clear)

        let glass = HaxGlassView(style: .light, cornerRadius: cornerRadius)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.pinEdges(to: self)
        surface = glass

        switch mode {
        case .toolbar:
            let toolbar = makeToolbar()
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            toolbar.applyContinuousCornerRadius(
                AppTheme.resultCorner - AppTheme.glassContentInset,
                background: AppTheme.panelContent
            )
            toolbar.layer?.borderWidth = 1.25
            toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor
            glass.contentView.addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(
                    equalTo: glass.contentView.leadingAnchor, constant: AppTheme.glassContentInset),
                toolbar.trailingAnchor.constraint(
                    equalTo: glass.contentView.trailingAnchor, constant: -AppTheme.glassContentInset
                ),
                toolbar.topAnchor.constraint(
                    equalTo: glass.contentView.topAnchor, constant: AppTheme.glassContentInset),
                toolbar.bottomAnchor.constraint(
                    equalTo: glass.contentView.bottomAnchor, constant: -AppTheme.glassContentInset),
            ])
        case .result:
            glass.contentView.addSubview(resultPanel)
            NSLayoutConstraint.activate([
                resultPanel.leadingAnchor.constraint(
                    equalTo: glass.contentView.leadingAnchor, constant: AppTheme.glassContentInset),
                resultPanel.trailingAnchor.constraint(
                    equalTo: glass.contentView.trailingAnchor, constant: -AppTheme.glassContentInset
                ),
                resultPanel.topAnchor.constraint(
                    equalTo: glass.contentView.topAnchor, constant: AppTheme.glassContentInset),
                resultPanel.bottomAnchor.constraint(
                    equalTo: glass.contentView.bottomAnchor, constant: -AppTheme.glassContentInset),
            ])
        }
    }

    private func makeToolbar() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.appearance = AppTheme.windowAppearance

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let dragHandle = ToolbarDragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.widthAnchor.constraint(equalToConstant: 15).isActive = true
        dragHandle.heightAnchor.constraint(equalToConstant: FloatingPanelLayout.toolbarContentHeight).isActive = true
        row.addArrangedSubview(dragHandle)
        row.addArrangedSubview(AppBrandIconView(size: 34))

        row.addArrangedSubview(makeActionButton(.copy, toolTip: "复制原文"))
        for action in AiToolAction.primaryActions {
            row.addArrangedSubview(makeActionButton(action, toolTip: action.rawValue))
        }

        let polish = NSButton.haxTextButton(
            "润色",
            target: nil,
            action: nil,
            font: FloatingPanelLayout.toolbarTextFont,
            color: AppTheme.textPrimary
        )
        polish.toolTip = "暂未实现"
        polish.isEnabled = false
        polish.alphaValue = 0.34
        row.addArrangedSubview(polish)

        let resume = ClosureIconButton(symbolName: "bubble.left", toolTip: "回到上一个对话") {
            [weak viewModel] in
            viewModel?.resumeArchivedConversation()
        }
        resume.isHidden = !viewModel.hasResumableConversation
        row.addArrangedSubview(resume)
        resumeChatButton = resume
        return container
    }

    // MARK: - 窗口边缘缩放

    private enum ResizeEdge {
        case left, right, top, bottom
    }

    private var resizeBand: CGFloat { AppTheme.glassContentInset }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        let nearLeft = point.x < resizeBand
        let nearRight = point.x > bounds.width - resizeBand
        let nearBottom = point.y < resizeBand
        let nearTop = point.y > bounds.height - resizeBand

        // Corners deliberately do not resize two axes at once. A resize
        // gesture owns either width or height, which prevents the borderless
        // window from submitting competing frame/layout updates.
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return nil
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: UInt
            switch edge {
            case .top: position = 1 << 0
            case .left: position = 1 << 1
            case .bottom: position = 1 << 2
            case .right: position = 1 << 3
            }
            let selector = Selector(("frameResizeCursorFromPosition:inDirections:"))
            if let cursor = NSCursor.perform(
                selector,
                with: NSNumber(value: position),
                with: NSNumber(value: 3)
            )?.takeUnretainedValue() as? NSCursor {
                return cursor
            }
        }
        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        }
    }

    override func resetCursorRects() {
        guard viewModel.mode == .result else { return }
        let band = resizeBand
        let size = bounds.size

        let regions: [(NSRect, ResizeEdge)] = [
            (NSRect(x: 0, y: 0, width: band, height: size.height), .left),
            (NSRect(x: size.width - band, y: 0, width: band, height: size.height), .right),
            (NSRect(x: 0, y: size.height - band, width: size.width, height: band), .top),
            (NSRect(x: 0, y: 0, width: size.width, height: band), .bottom),
        ]

        for (rect, edge) in regions {
            addCursorRect(rect, cursor: cursor(for: edge))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard viewModel.mode == .result, let window,
            let edge = resizeEdge(at: convert(event.locationInWindow, from: nil))
        else {
            super.mouseDown(with: event)
            return
        }
        performWindowResize(edge: edge, in: window)
    }

    /// 手动边缘缩放循环:borderless 窗口没有系统缩放,按锚点方向更新窗口 frame。
    private func performWindowResize(edge: ResizeEdge, in window: NSWindow) {
        let minSize = NSSize(
            width: FloatingPanelLayout.resultMinimumWidth,
            height: 400
        )
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let visibleFrame = window.screen?.visibleFrame ?? startFrame

        while true {
            guard
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp, .otherMouseUp, .rightMouseUp]
                )
            else { break }

            if next.type == .leftMouseUp || next.type != .leftMouseDragged {
                break
            }

            let delta = NSPoint(
                x: NSEvent.mouseLocation.x - startMouse.x,
                y: NSEvent.mouseLocation.y - startMouse.y
            )

            var x = startFrame.minX
            var y = startFrame.minY
            var width = startFrame.width
            var height = startFrame.height

            switch edge {
            case .left:
                width = min(max(minSize.width, startFrame.width - delta.x), visibleFrame.width)
                x = startFrame.maxX - width
            case .right:
                width = min(max(minSize.width, startFrame.width + delta.x), visibleFrame.width)
            case .top:
                height = min(max(minSize.height, startFrame.height + delta.y), visibleFrame.height)
            case .bottom:
                height = min(max(minSize.height, startFrame.height - delta.y), visibleFrame.height)
                y = startFrame.maxY - height
            }

            // 取整 + 跳过无变化帧 + 拖拽中免同步重绘:亚像素 frame 逐帧
            // 摆动与每事件强制 display 是窗口抖动的两个来源
            let newFrame = NSRect(
                x: x.rounded(),
                y: y.rounded(),
                width: width.rounded(),
                height: height.rounded()
            ).integral
            guard newFrame != window.frame else { continue }

            window.setFrame(newFrame, display: false)
        }
    }

    private func makeActionButton(_ action: AiToolAction, toolTip: String) -> NSButton {
        let button = ToolbarActionButton(action: action) { [weak viewModel] action in
            viewModel?.handlePrimaryAction(action)
        }
        button.toolTip = toolTip
        return button
    }
}

private final class ToolbarActionButton: NSButton {
    private let toolAction: AiToolAction
    private let handler: (AiToolAction) -> Void

    init(action: AiToolAction, handler: @escaping (AiToolAction) -> Void) {
        self.toolAction = action
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = AppTheme.windowAppearance
        title = action.rawValue
        isBordered = false
        focusRingType = .none
        let titleFont = FloatingPanelLayout.toolbarTextFont
        font = titleFont
        setHaxTitle(action.rawValue, color: AppTheme.textPrimary, font: titleFont)
        contentTintColor = AppTheme.textPrimary
        target = self
        self.action = #selector(runAction)
        heightAnchor.constraint(equalToConstant: FloatingPanelLayout.toolbarContentHeight).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        handler(toolAction)
    }
}
private final class ClosureIconButton: NSButton {
    private let handler: () -> Void

    init(symbolName: String, toolTip: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = AppTheme.windowAppearance
        isBordered = false
        focusRingType = .none
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = AppTheme.textPrimary
        self.toolTip = toolTip
        target = self
        action = #selector(runHandler)
        heightAnchor.constraint(equalToConstant: FloatingPanelLayout.toolbarContentHeight).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}
