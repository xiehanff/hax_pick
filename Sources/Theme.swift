import SwiftUI

// MARK: - Color hex 扩展

extension Color {
    init(hex: UInt) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF)        / 255
        )
    }
}

// MARK: - 扁平化主题

enum AppTheme {
    static let background     = Color(hex: 0xF8F8FA)
    static let cardBg         = Color.white
    static let mutedBg        = Color(hex: 0xF0F1F5)
    static let accent         = Color(hex: 0x3366FF)
    static let textPrimary    = Color(hex: 0x1A1A2E)
    static let textSecondary  = Color(hex: 0x8E8E9A)
    static let border         = Color(hex: 0xE4E4EC)
    static let success        = Color(hex: 0x34C759)

    static let corner: CGFloat = 14
}

// MARK: - 悬浮面板尺寸

enum FloatingPanelLayout {
    static let toolbarSize = NSSize(width: 320, height: 48)
    static let resultSize = NSSize(width: 440, height: 628)
}

// MARK: - 共享 NSPanel 子类

final class HaxPickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - NSHostingView 圆角裁剪工具

extension AppTheme {
    /// 将 SwiftUI 视图包裹在圆角裁剪 + 固定尺寸的容器中，供 NSPanel 使用
    static func makeClippedHostingView<V: View>(rootView: V, size: NSSize) -> NSView {
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.clear.cgColor
        clip.layer?.cornerRadius = corner
        clip.layer?.masksToBounds = true

        clip.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: clip.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(clip)
        clip.frame = container.bounds
        clip.autoresizingMask = [.width, .height]
        return container
    }
}

// MARK: - NSPoint 几何工具

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func midpoint(to other: NSPoint) -> NSPoint {
        NSPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }
}

// MARK: - 胶囊工具按钮（工具栏用）

struct CapsuleToolButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(AppTheme.textPrimary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .fixedSize()
    }
}

// MARK: - 主按钮（发送等）

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(configuration.isPressed ? AppTheme.accent.opacity(0.8) : AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 次要按钮（关闭/复制/重试）

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(configuration.isPressed ? AppTheme.mutedBg : AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

// MARK: - 推荐问题 chip

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(configuration.isPressed ? AppTheme.accent.opacity(0.8) : AppTheme.accent)
            .clipShape(Capsule())
    }
}
