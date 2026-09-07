import AppKit

// MARK: - Colors

extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum AppTheme {
    static let background = NSColor(hex: 0xF6F6F7)
    static let cardBg = NSColor.white
    static let panelContent = NSColor.white.withAlphaComponent(0.78)
    static let mutedBg = NSColor(hex: 0xF2F2F3)
    static let accent = NSColor(hex: 0xFF6B1A)
    static let textPrimary = NSColor(hex: 0x232427)
    static let textSecondary = NSColor(hex: 0x74767B)
    static let border = NSColor.black.withAlphaComponent(0.085)
    static let success = NSColor(hex: 0x34C759)

    static let resultCorner: CGFloat = 28
    static let menuCorner: CGFloat = 18
    static let glassContentInset: CGFloat = 12
}

// MARK: - Floating panel geometry

enum FloatingPanelLayout {
    static let toolbarSize = NSSize(width: 420, height: 48)
    static let resultWidthFraction: CGFloat = 0.36
    static let resultMinimumWidth: CGFloat = 460
    static let resultMaximumWidth: CGFloat = 560
    static let resultHeightFraction: CGFloat = 0.82
    static let resultMinimumHeight: CGFloat = 560
    static let resultMaximumHeight: CGFloat = 720
    static let screenEdgeInset: CGFloat = 16
}

final class HaxPickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - AppKit glass surface

enum HaxGlassStyle {
    case light
    case dark

    var material: NSVisualEffectView.Material {
        switch self {
        case .light: return .underWindowBackground
        case .dark: return .hudWindow
        }
    }

    var solidFallback: NSColor {
        switch self {
        case .light: return NSColor(hex: 0xF5F5F7)
        case .dark: return NSColor(hex: 0x34363A)
        }
    }

    var overlayTint: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.08)
        case .dark: return NSColor.black.withAlphaComponent(0.35)
        }
    }

    var rimColor: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.78)
        case .dark: return NSColor.white.withAlphaComponent(0.22)
        }
    }
}

final class HaxGlassView: NSView {
    let contentView = NSView()

    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    private let style: HaxGlassStyle
    private let cornerRadius: CGFloat

    init(style: HaxGlassStyle, cornerRadius: CGFloat) {
        self.style = style
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.75
        layer?.borderColor = style.rimColor.cgColor

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = style.material
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = style.overlayTint.cgColor

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            layer?.backgroundColor = style.solidFallback.cgColor
        } else {
            addSubview(effectView)
            effectView.pinEdges(to: self)
            addSubview(tintView)
            tintView.pinEdges(to: self)
        }

        addSubview(contentView)
        contentView.pinEdges(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SoftDividerView: NSView {
    init(color: NSColor = NSColor.black.withAlphaComponent(0.055)) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ToolbarDragHandleView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 15, height: 15) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        let diameter: CGFloat = 2.5
        let gap: CGFloat = 3
        let total = diameter * 3 + gap * 2
        let startX = (bounds.width - total) / 2
        let startY = (bounds.height - total) / 2
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = NSRect(
                    x: startX + CGFloat(column) * (diameter + gap),
                    y: startY + CGFloat(row) * (diameter + gap),
                    width: diameter,
                    height: diameter
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }
}

// MARK: - Shared AppKit helpers

extension NSView {
    func pinEdges(to view: NSView, insets: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func applyContinuousCornerRadius(_ radius: CGFloat, background: NSColor? = nil) {
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        if let background {
            layer?.backgroundColor = background.cgColor
        }
    }
}

extension NSTextField {
    static func haxLabel(
        _ text: String,
        font: NSFont,
        color: NSColor = AppTheme.textPrimary,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }
}

extension NSButton {
    static func haxTextButton(
        _ title: String,
        target: AnyObject?,
        action: Selector?,
        font: NSFont = .systemFont(ofSize: 12, weight: .semibold),
        color: NSColor = AppTheme.textPrimary
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.font = font
        button.contentTintColor = color
        button.focusRingType = .none
        return button
    }
}

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func midpoint(to other: NSPoint) -> NSPoint {
        NSPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }
}
