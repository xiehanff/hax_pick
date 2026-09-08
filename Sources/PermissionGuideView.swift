import AppKit
import Combine

@MainActor
final class PermissionGuideViewController: NSViewController {
    private let appState: AppState
    private let onClose: () -> Void
    private var observation: AnyCancellable?

    private let subtitle = NSTextField.haxLabel("", font: .systemFont(ofSize: 12), color: AppTheme.textSecondary)
    private let statusDot = NSView()
    private let repairButton = NSButton()

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootSurface = RoundedSurfaceView(
            cornerRadius: AppTheme.permissionCorner,
            backgroundColor: AppTheme.background,
            borderColor: AppTheme.border,
            borderWidth: 0.75
        )
        rootSurface.translatesAutoresizingMaskIntoConstraints = true
        rootSurface.autoresizingMask = [.width, .height]
        rootSurface.frame = NSRect(x: 0, y: 0, width: 480, height: 420)
        view = rootSurface

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
        ])

        root.addArrangedSubview(makeHeader())
        root.addArrangedSubview(makeSteps())
        root.addArrangedSubview(makeActions())
        for child in root.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observation = appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(AppBrandIconView(size: 40))

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(
            NSTextField.haxLabel("HaxPick 权限引导", font: .systemFont(ofSize: 16, weight: .bold))
        )
        textStack.addArrangedSubview(subtitle)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.applyContinuousCornerRadius(5)
        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        row.addArrangedSubview(statusDot)
        return row
    }

    private func makeSteps() -> NSView {
        let card = RoundedSurfaceView(
            cornerRadius: 14,
            backgroundColor: AppTheme.cardBg,
            borderColor: AppTheme.border,
            borderWidth: 0.75
        )

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])

        let rows = [
            ("1", "打开辅助功能页面", "点击下方按钮，跳转到系统设置对应位置"),
            ("2", "将 HaxPick 加入授权列表", "在列表中勾选 HaxPick，允许读取选中文本"),
            ("3", "回到这里刷新状态", "授权后点击刷新，窗口会自动关闭"),
        ]
        for (index, item) in rows.enumerated() {
            let row = makeStep(number: item.0, title: item.1, detail: item.2)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if index < rows.count - 1 {
                let dividerContainer = NSView()
                dividerContainer.translatesAutoresizingMaskIntoConstraints = false
                let divider = SoftDividerView()
                dividerContainer.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: dividerContainer.leadingAnchor, constant: 36),
                    divider.trailingAnchor.constraint(equalTo: dividerContainer.trailingAnchor),
                    divider.centerYAnchor.constraint(equalTo: dividerContainer.centerYAnchor),
                    dividerContainer.heightAnchor.constraint(equalToConstant: 1),
                ])
                stack.addArrangedSubview(dividerContainer)
                dividerContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return card
    }

    private func makeStep(number: String, title: String, detail: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)

        let badge = NSTextField(labelWithString: number)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.appearance = AppTheme.windowAppearance
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 13, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = AppTheme.accent.cgColor
        badge.layer?.cornerRadius = 11
        badge.widthAnchor.constraint(equalToConstant: 22).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.addArrangedSubview(NSTextField.haxLabel(title, font: .systemFont(ofSize: 13, weight: .semibold)))
        text.addArrangedSubview(NSTextField.haxLabel(detail, font: .systemFont(ofSize: 11), color: AppTheme.textSecondary))
        row.addArrangedSubview(badge)
        row.addArrangedSubview(text)
        return row
    }

    private func makeActions() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let primaryRow = NSStackView()
        primaryRow.orientation = .horizontal
        primaryRow.alignment = .centerY
        primaryRow.spacing = 8

        let open = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openSettings))
        open.appearance = AppTheme.windowAppearance
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"

        let refresh = NSButton(title: "刷新状态", target: self, action: #selector(refreshPermission))
        refresh.appearance = AppTheme.windowAppearance
        refresh.bezelStyle = .rounded

        let later = NSButton(title: "稍后再说", target: self, action: #selector(closeGuide))
        later.appearance = AppTheme.windowAppearance
        later.bezelStyle = .rounded

        primaryRow.addArrangedSubview(open)
        primaryRow.addArrangedSubview(refresh)
        primaryRow.addArrangedSubview(NSView())
        primaryRow.addArrangedSubview(later)

        repairButton.appearance = AppTheme.windowAppearance
        repairButton.title = "系统里显示已开启但仍不可用？重置旧权限记录"
        repairButton.bezelStyle = .rounded
        repairButton.target = self
        repairButton.action = #selector(repairPermission)

        stack.addArrangedSubview(primaryRow)
        stack.addArrangedSubview(repairButton)
        primaryRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func refresh() {
        if let repairError = appState.permissionRepairError, !repairError.isEmpty {
            subtitle.stringValue = "权限记录异常：\(repairError)"
        } else {
            subtitle.stringValue = appState.permissionGranted
                ? "已授权，可以开始使用"
                : "需要辅助功能权限才能监听划词"
        }
        statusDot.layer?.backgroundColor = (appState.permissionGranted ? AppTheme.success : NSColor.systemOrange).cgColor
        repairButton.isHidden = appState.permissionGranted
    }

    @objc private func openSettings() {
        appState.openAccessibilitySettings()
    }

    @objc private func refreshPermission() {
        appState.refreshPermissionStatus()
        if appState.permissionGranted {
            onClose()
        }
    }

    @objc private func repairPermission() {
        appState.repairAccessibilityPermission()
    }

    @objc private func closeGuide() {
        onClose()
    }
}
