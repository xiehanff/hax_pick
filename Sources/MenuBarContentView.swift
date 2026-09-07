import AppKit
import Combine

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let controller = SettingsViewController(appState: appState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HaxPick 设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class SettingsViewController: NSViewController {
    private let appState: AppState
    private var observation: AnyCancellable?
    private var lastCommittedAPIKey = ""
    private var apiKeyVisible = false

    private let permissionIcon = NSImageView()
    private let permissionLabel = NSTextField.haxLabel("", font: .systemFont(ofSize: 12))
    private let permissionButton = NSButton()
    private let modelPopup = NSPopUpButton()
    private let secureKeyField = NSSecureTextField()
    private let plainKeyField = NSTextField()
    private let revealButton = NSButton()
    private let saveButton = NSButton()
    private let keyStatusLabel = NSTextField.haxLabel("", font: .systemFont(ofSize: 10.5), color: AppTheme.textSecondary)

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = AppTheme.background.cgColor

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

        let title = NSTextField.haxLabel("HaxPick 设置", font: .systemFont(ofSize: 18, weight: .bold))
        root.addArrangedSubview(title)
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
        lastCommittedAPIKey = appState.apiKey
        secureKeyField.stringValue = appState.apiKey
        plainKeyField.stringValue = appState.apiKey
        observation = appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    private func makePermissionSection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        permissionIcon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        permissionIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        permissionIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(permissionIcon)
        row.addArrangedSubview(permissionLabel)
        row.addArrangedSubview(NSView())
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
        let modelLabel = NSTextField.haxLabel("模型", font: .systemFont(ofSize: 12, weight: .medium))
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        modelRow.addArrangedSubview(modelLabel)
        modelRow.addArrangedSubview(NSView())
        modelRow.addArrangedSubview(modelPopup)

        let keyTitle = NSTextField.haxLabel("DeepSeek API Key", font: .systemFont(ofSize: 12, weight: .medium))
        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 7

        let fieldContainer = NSView()
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.heightAnchor.constraint(equalToConstant: 26).isActive = true
        secureKeyField.translatesAutoresizingMaskIntoConstraints = false
        plainKeyField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(secureKeyField)
        fieldContainer.addSubview(plainKeyField)
        secureKeyField.pinEdges(to: fieldContainer)
        plainKeyField.pinEdges(to: fieldContainer)
        plainKeyField.isHidden = true

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.bezelStyle = .texturedRounded
        revealButton.imagePosition = .imageOnly
        revealButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded

        keyRow.addArrangedSubview(fieldContainer)
        keyRow.addArrangedSubview(revealButton)
        keyRow.addArrangedSubview(saveButton)
        fieldContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        fieldContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(modelRow)
        stack.addArrangedSubview(keyTitle)
        stack.addArrangedSubview(keyRow)
        stack.addArrangedSubview(keyStatusLabel)
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return section(title: "AI 设置", content: stack)
    }

    private func makeAboutSection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        let label = NSTextField.haxLabel("版本", font: .systemFont(ofSize: 12, weight: .medium))
        let value = NSTextField.haxLabel("v\(appState.appVersion)", font: .systemFont(ofSize: 12), color: AppTheme.textSecondary, alignment: .right)
        row.addArrangedSubview(label)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(value)
        return section(title: "关于", content: row)
    }

    private func section(title: String, content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.applyContinuousCornerRadius(12, background: AppTheme.cardBg)
        container.layer?.borderWidth = 0.75
        container.layer?.borderColor = AppTheme.border.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField.haxLabel(title, font: .systemFont(ofSize: 11, weight: .semibold), color: AppTheme.textSecondary)
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
        permissionButton.target = self
        permissionButton.action = #selector(permissionAction)
        permissionButton.bezelStyle = .rounded

        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: appState.availableModels().map(\.displayName))
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)

        secureKeyField.placeholderString = "粘贴 API Key"
        plainKeyField.placeholderString = "粘贴 API Key"

        revealButton.target = self
        revealButton.action = #selector(toggleKeyVisibility)
        saveButton.target = self
        saveButton.action = #selector(saveOrRetry)
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
        permissionLabel.stringValue = appState.permissionGranted
            ? "已开启，可以监听全局划词"
            : "开启后才能读取其他应用中的选中文本"
        permissionButton.title = appState.permissionGranted ? "刷新" : "去开启"

        if let index = appState.availableModels().firstIndex(of: appState.selectedModel) {
            modelPopup.selectItem(at: index)
        }

        let currentDraft = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDraft == lastCommittedAPIKey {
            secureKeyField.stringValue = appState.apiKey
            plainKeyField.stringValue = appState.apiKey
        }
        lastCommittedAPIKey = appState.apiKey

        saveButton.title = appState.canRetryAPIKeyStorage ? "重试" : "保存"
        saveButton.isEnabled = appState.canRetryAPIKeyStorage || currentDraft != appState.apiKey || appState.apiKeyStorageError != nil
        keyStatusLabel.stringValue = appState.apiKeyStorageError ?? appState.apiKeyStorageStatusMessage
        keyStatusLabel.textColor = appState.apiKeyStorageError == nil ? AppTheme.textSecondary : .systemOrange
    }

    @objc private func permissionAction() {
        if appState.permissionGranted {
            appState.refreshPermissionStatus()
        } else {
            appState.showPermissionGuide()
        }
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
        view.window?.makeFirstResponder(apiKeyVisible ? plainKeyField : secureKeyField)
    }

    private func refreshRevealIcon() {
        revealButton.image = NSImage(
            systemSymbolName: apiKeyVisible ? "eye.slash" : "eye",
            accessibilityDescription: apiKeyVisible ? "隐藏 API Key" : "显示 API Key"
        )
    }

    @objc private func saveOrRetry() {
        if appState.canRetryAPIKeyStorage {
            let oldCommitted = appState.apiKey
            let unmodified = draftKey.trimmingCharacters(in: .whitespacesAndNewlines) == oldCommitted
            _ = appState.retryAPIKeyStorage()
            if unmodified {
                secureKeyField.stringValue = appState.apiKey
                plainKeyField.stringValue = appState.apiKey
            }
        } else if appState.saveAPIKey(draftKey) {
            secureKeyField.stringValue = appState.apiKey
            plainKeyField.stringValue = appState.apiKey
        }
        refresh()
    }
}
