import AppKit
import Combine

@MainActor
final class FloatingToolbarView: NSView {
    private let viewModel: PanelSessionViewModel
    private var observation: AnyCancellable?
    private var currentMode: PanelSessionViewModel.PanelMode?
    private var surface: HaxGlassView?
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
        let mode = viewModel.mode
        guard force || currentMode != mode else { return }
        currentMode = mode
        surface?.removeFromSuperview()

        let cornerRadius: CGFloat = mode == .toolbar
            ? FloatingPanelLayout.toolbarSize.height / 2
            : AppTheme.resultCorner

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
                FloatingPanelLayout.toolbarSize.height / 2,
                background: AppTheme.panelContent
            )
            toolbar.layer?.borderWidth = 0.75
            toolbar.layer?.borderColor = AppTheme.border.cgColor
            glass.contentView.addSubview(toolbar)
            toolbar.pinEdges(to: glass.contentView)
        case .result:
            glass.contentView.addSubview(resultPanel)
            NSLayoutConstraint.activate([
                resultPanel.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: AppTheme.glassContentInset),
                resultPanel.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -AppTheme.glassContentInset),
                resultPanel.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: AppTheme.glassContentInset),
                resultPanel.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -AppTheme.glassContentInset),
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
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let dragHandle = ToolbarDragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.widthAnchor.constraint(equalToConstant: 15).isActive = true
        dragHandle.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: AppTheme.textPrimary
        )
        polish.toolTip = "暂未实现"
        polish.isEnabled = false
        polish.alphaValue = 0.34
        row.addArrangedSubview(polish)
        return container
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
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        font = titleFont
        setHaxTitle(action.rawValue, color: AppTheme.textPrimary, font: titleFont)
        contentTintColor = AppTheme.textPrimary
        target = self
        self.action = #selector(runAction)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        handler(toolAction)
    }
}