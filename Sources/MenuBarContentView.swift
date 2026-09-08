import AppKit
import Combine

private func handleAPIKeyPaste(field: NSTextField, event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command),
          !flags.contains(.option),
          !flags.contains(.control),
          event.charactersIgnoringModifiers?.lowercased() == "v",
          let editor = field.currentEditor() else {
        return false
    }
    editor.paste(nil)
    return true
}

private final class APIKeyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleAPIKeyPaste(field: self, event: event) || super.performKeyEquivalent(with: event)
    }
}

private final class APIKeySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleAPIKeyPaste(field: self, event: event) || super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appState: AppState) {
        // 与对话窗口同款:borderless 玻璃窗口 + 白色内容层 + 圆形关闭按钮,
        // 不再使用系统标题栏 panel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = AppTheme.windowAppearance
        window.title = "HaxPick 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        // 先装内容再居中:内容视图加载会改窗口尺寸,borderless 窗口尺寸变化
        // 时锚定左下角,先 center() 会被拽偏到屏幕底部
        window.contentViewController = SettingsGlassViewController(
            content: SettingsViewController(appState: appState)
        )
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
    }
}

/// 玻璃外壳 + 白色内容层,顶部标题行 + 右上角圆形关闭按钮,对齐对话窗口 UI。
@MainActor
private final class SettingsGlassViewController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        addChild(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.appearance = AppTheme.windowAppearance
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        root.applyContinuousCornerRadius(AppTheme.resultCorner, background: .clear)

        let glass = HaxGlassView(style: .light, cornerRadius: AppTheme.resultCorner)
        glass.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(glass)
        glass.pinEdges(to: root)

        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.appearance = AppTheme.windowAppearance
        // 同心圆角:内圆角 = 外圆角 - 玻璃外缘宽度
        panel.applyContinuousCornerRadius(
            AppTheme.resultCorner - AppTheme.glassContentInset,
            background: AppTheme.panelContent
        )
        panel.layer?.borderWidth = 0.75
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor
        glass.contentView.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: AppTheme.glassContentInset),
            panel.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -AppTheme.glassContentInset),
            panel.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: AppTheme.glassContentInset),
            panel.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -AppTheme.glassContentInset),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView()
        titleRow.orientation = .vertical
        titleRow.alignment = .leading
        titleRow.spacing = 1
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addArrangedSubview(
            NSTextField.haxLabel(
                "HaxPick 设置",
                font: AppFont.ui(ofSize: 14, weight: .semibold)
            )
        )

        let close = CircleIconButton(
            symbolName: "xmark",
            accessibilityDescription: "关闭设置",
            size: 28,
            backgroundColor: NSColor.black.withAlphaComponent(0.86),
            tintColor: .white,
            target: self,
            action: #selector(closeWindow)
        )

        header.addArrangedSubview(AppBrandIconView(size: 28))
        header.addArrangedSubview(titleRow)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(close)

        let divider = SoftDividerView()

        content.view.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(header)
        panel.addSubview(divider)
        panel.addSubview(content.view)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: panel.topAnchor, constant: 11),
            header.heightAnchor.constraint(equalToConstant: 38),

            divider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),

            content.view.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 22),
            content.view.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -22),
            content.view.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 14),
            content.view.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -16),
        ])

        view = root
    }

    @objc private func closeWindow() {
        view.window?.close()
    }
}

@MainActor
final class SettingsViewController: NSViewController, NSTextFieldDelegate {
    private let appState: AppState
    private var observation: AnyCancellable?
    private var fieldObservation: AnyCancellable?
    private var apiKeyVisible = false

    private let permissionIcon = NSImageView()
    private let permissionLabel = NSTextField.haxLabel("", font: AppFont.ui(ofSize: 12))
    private let permissionButton = NSButton()
    private let permissionRepairButton = NSButton()
    private let modelPopup = NSPopUpButton()
    private let secureKeyField = APIKeySecureTextField()
    private let plainKeyField = APIKeyTextField()
    private let revealButton = NSButton()
    private let saveButton = NSButton()
    private let keyStatusLabel = NSTextField.haxLabel("", font: AppFont.ui(ofSize: 10.5), color: AppTheme.textSecondary)

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.appearance = AppTheme.windowAppearance
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -22),
        ])

        root.addArrangedSubview(makePermissionSection())
        root.addArrangedSubview(makeAISection())
        root.addArrangedSubview(makeAboutSection())

        for child in root.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        secureKeyField.stringValue = appState.apiKey
        plainKeyField.stringValue = appState.apiKey

        observation = appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }

        fieldObservation = NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)
            .sink { [weak self] notification in
                guard let self,
                      let field = notification.object as? NSTextField,
                      field === self.secureKeyField || field === self.plainKeyField else {
                    return
                }
                self.refreshSaveButtonState()
            }
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(apiKeyVisible ? plainKeyField : secureKeyField)
    }

    private func makePermissionSection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        permissionIcon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        permissionIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        permissionIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        permissionRepairButton.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(permissionIcon)
        row.addArrangedSubview(permissionLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(permissionRepairButton)
        row.addArrangedSubview(permissionButton)
        return section(title: "辅助功能权限", content: row)
    }

    private func makeAISection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let modelRow = NSStackView()
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 8
        let modelLabel = NSTextField.haxLabel("模型", font: AppFont.ui(ofSize: 12, weight: .medium))
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        modelRow.addArrangedSubview(modelLabel)
        modelRow.addArrangedSubview(NSView())
        modelRow.addArrangedSubview(modelPopup)

        let keyTitle = NSTextField.haxLabel("DeepSeek API Key", font: AppFont.ui(ofSize: 12, weight: .medium))

        // The API key field owns an entire row. The old field shared horizontal
        // space with two buttons, which made a long key effectively unreadable.
        let fieldContainer = NSView()
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        secureKeyField.translatesAutoresizingMaskIntoConstraints = false
        plainKeyField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(secureKeyField)
        fieldContainer.addSubview(plainKeyField)
        secureKeyField.pinEdges(to: fieldContainer)
        plainKeyField.pinEdges(to: fieldContainer)
        plainKeyField.isHidden = true

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 7
        keyStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.bezelStyle = .texturedRounded
        revealButton.imagePosition = .imageOnly
        revealButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.font = AppFont.ui(ofSize: 12, weight: .medium)
        saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true

        actionRow.addArrangedSubview(keyStatusLabel)
        actionRow.addArrangedSubview(NSView())
        actionRow.addArrangedSubview(revealButton)
        actionRow.addArrangedSubview(saveButton)

        stack.addArrangedSubview(modelRow)
        stack.addArrangedSubview(keyTitle)
        stack.addArrangedSubview(fieldContainer)
        stack.addArrangedSubview(actionRow)
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return section(title: "AI 设置", content: stack)
    }

    private func makeAboutSection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        let label = NSTextField.haxLabel("版本", font: AppFont.ui(ofSize: 12, weight: .medium))
        let value = NSTextField.haxLabel("v\(appState.appVersion)", font: AppFont.ui(ofSize: 12), color: AppTheme.textSecondary, alignment: .right)
        row.addArrangedSubview(label)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(value)
        return section(title: "关于", content: row)
    }

    private func section(title: String, content: NSView) -> NSView {
        let container = RoundedSurfaceView(
            cornerRadius: 12,
            backgroundColor: AppTheme.cardBg,
            borderColor: AppTheme.border,
            borderWidth: 0.75
        )

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField.haxLabel(title, font: AppFont.ui(ofSize: 11, weight: .semibold), color: AppTheme.textSecondary)
        content.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(content)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func configureControls() {
        for control in [permissionButton, permissionRepairButton, modelPopup, secureKeyField, plainKeyField, revealButton, saveButton] {
            control.appearance = AppTheme.windowAppearance
        }

        permissionButton.target = self
        permissionButton.action = #selector(permissionAction)
        permissionButton.bezelStyle = .rounded

        permissionRepairButton.title = "重置权限"
        permissionRepairButton.target = self
        permissionRepairButton.action = #selector(repairPermission)
        permissionRepairButton.bezelStyle = .rounded

        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: appState.availableModels().map(\.displayName))
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)

        for field in [secureKeyField, plainKeyField] {
            field.delegate = self
            field.isEditable = true
            field.isSelectable = true
            field.usesSingleLineMode = true
            field.placeholderString = "粘贴 API Key"
            field.focusRingType = .default
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.lineBreakMode = .byTruncatingMiddle
        }

        revealButton.target = self
        revealButton.action = #selector(toggleKeyVisibility)
        saveButton.target = self
        saveButton.action = #selector(saveAPIKey)
        refreshRevealIcon()
    }

    private var draftKey: String {
        apiKeyVisible ? plainKeyField.stringValue : secureKeyField.stringValue
    }

    private func refresh() {
        permissionIcon.image = NSImage(
            systemSymbolName: appState.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        permissionIcon.contentTintColor = appState.permissionGranted ? .systemGreen : .systemOrange

        if let repairError = appState.permissionRepairError, !repairError.isEmpty {
            permissionLabel.stringValue = "权限记录异常，可重置后重新授权"
            permissionLabel.toolTip = repairError
        } else {
            permissionLabel.stringValue = appState.permissionGranted
                ? "已开启，可以监听全局划词"
                : "当前进程未获得权限"
            permissionLabel.toolTip = nil
        }

        permissionButton.title = appState.permissionGranted ? "刷新" : "打开设置"
        permissionRepairButton.isHidden = appState.permissionGranted

        if let index = appState.availableModels().firstIndex(of: appState.selectedModel) {
            modelPopup.selectItem(at: index)
        }

        // Generic AppState changes must never overwrite the user's in-progress
        // API-key edit. Fields are synchronized only on initial load, visibility
        // toggle, and a successful save.
        refreshSaveButtonState()
        keyStatusLabel.stringValue = appState.apiKeyStorageError ?? appState.apiKeyStorageStatusMessage
        keyStatusLabel.textColor = appState.apiKeyStorageError == nil ? AppTheme.textSecondary : .systemOrange
    }

    private func refreshSaveButtonState() {
        // Product rule: only the current text matters. Any non-whitespace value is
        // Save the current local-cache value, including an unchanged key.
        let shouldEnable = !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        saveButton.isEnabled = shouldEnable
        saveButton.alphaValue = shouldEnable ? 1 : 0.48
        saveButton.setHaxTitle(
            "保存",
            color: shouldEnable ? AppTheme.textPrimary : AppTheme.textSecondary.withAlphaComponent(0.62),
            font: AppFont.ui(ofSize: 12, weight: .medium)
        )
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              field === secureKeyField || field === plainKeyField else { return }
        refreshSaveButtonState()
    }

    @objc private func permissionAction() {
        if appState.permissionGranted {
            appState.refreshPermissionStatus()
        } else {
            appState.openAccessibilitySettings()
        }
    }

    @objc private func repairPermission() {
        appState.repairAccessibilityPermission()
    }

    @objc private func modelChanged() {
        let models = appState.availableModels()
        guard modelPopup.indexOfSelectedItem >= 0, modelPopup.indexOfSelectedItem < models.count else { return }
        appState.selectedModel = models[modelPopup.indexOfSelectedItem]
    }

    @objc private func toggleKeyVisibility() {
        if apiKeyVisible {
            secureKeyField.stringValue = plainKeyField.stringValue
        } else {
            plainKeyField.stringValue = secureKeyField.stringValue
        }
        apiKeyVisible.toggle()
        secureKeyField.isHidden = apiKeyVisible
        plainKeyField.isHidden = !apiKeyVisible
        refreshRevealIcon()
        refreshSaveButtonState()
        view.window?.makeFirstResponder(apiKeyVisible ? plainKeyField : secureKeyField)
    }

    private func refreshRevealIcon() {
        revealButton.image = NSImage(
            systemSymbolName: apiKeyVisible ? "eye.slash" : "eye",
            accessibilityDescription: apiKeyVisible ? "隐藏 API Key" : "显示 API Key"
        )
    }

    @objc private func saveAPIKey() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            refreshSaveButtonState()
            return
        }

        if appState.saveAPIKey(draftKey) {
            secureKeyField.stringValue = appState.apiKey
            plainKeyField.stringValue = appState.apiKey
        }
        refresh()
    }
}
