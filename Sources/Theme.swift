import AppKit
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

// MARK: - Liquid Glass 主题

enum AppTheme {
    static let background     = Color(hex: 0xF6F6F7)
    static let cardBg         = Color.white
    static let panelContent   = Color.white.opacity(0.72)
    static let mutedBg        = Color(hex: 0xF2F2F3)
    static let accent         = Color(hex: 0xFF6B1A)
    static let textPrimary    = Color(hex: 0x232427)
    static let textSecondary  = Color(hex: 0x74767B)
    static let border         = Color.black.opacity(0.085)
    static let success        = Color(hex: 0x34C759)

    static let toolbarCorner: CGFloat = 15
    static let resultCorner: CGFloat = 28
    static let menuCorner: CGFloat = 18
    static let glassContentInset: CGFloat = 12
}

// MARK: - 悬浮面板尺寸

enum FloatingPanelLayout {
    static let toolbarSize = NSSize(width: 378, height: 48)
    static let resultWidthFraction: CGFloat = 0.36
    static let resultMinimumWidth: CGFloat = 460
    static let resultMaximumWidth: CGFloat = 560
    static let resultHeightFraction: CGFloat = 0.82
    static let resultMinimumHeight: CGFloat = 560
    static let resultMaximumHeight: CGFloat = 720
    static let screenEdgeInset: CGFloat = 16
}

// MARK: - 共享 NSPanel 子类

final class HaxPickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - NSHostingView 容器

extension AppTheme {
    /// 将 SwiftUI 视图包裹在固定尺寸的容器中，供 NSPanel 使用。
    /// 圆角与边缘抗锯齿完全交给 SwiftUI 内部的 clipShape 绘制；这里不再叠加
    /// CALayer.cornerRadius 硬裁剪——它没有抗锯齿且曲率与 continuous 圆角不一致，
    /// 会在 1x 屏上把圆角边缘“咬”出锯齿。
    static func makeHostingView<V: View>(rootView: V, size: NSSize) -> NSView {
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}

// MARK: - 跨版本玻璃材质

enum HaxGlassStyle {
    case light
    case dark

    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .light:
            return .underWindowBackground
        case .dark:
            return .hudWindow
        }
    }

    var fallbackTint: Color {
        switch self {
        case .light:
            return .white.opacity(0.04)
        case .dark:
            return .black.opacity(0.72)
        }
    }

    var solidFallback: Color {
        switch self {
        case .light:
            return Color(hex: 0xF5F5F7)
        case .dark:
            return Color(hex: 0x34363A)
        }
    }

    var rimColor: Color {
        switch self {
        case .light:
            return .white.opacity(0.78)
        case .dark:
            return .white.opacity(0.22)
        }
    }

    var bevelColor: Color {
        switch self {
        case .light:
            return .black.opacity(0.055)
        case .dark:
            return .black.opacity(0.30)
        }
    }

#if compiler(>=6.2)
    var nativeTint: Color {
        switch self {
        case .light:
            return .white.opacity(0.05)
        case .dark:
            return .black.opacity(0.30)
        }
    }
#endif
}

private struct VisualEffectMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct HaxGlassSurface<Content: View>: View {
    let style: HaxGlassStyle
    let cornerRadius: CGFloat
    let showsRim: Bool
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        style: HaxGlassStyle,
        cornerRadius: CGFloat,
        showsRim: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.showsRim = showsRim
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(
                    .regular.tint(style.nativeTint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .glassRim(style: style, cornerRadius: cornerRadius, enabled: showsRim)
        } else {
            fallbackSurface
        }
#else
        fallbackSurface
#endif
    }

    private var fallbackSurface: some View {
        content
            .background {
                if reduceTransparency {
                    style.solidFallback
                } else {
                    VisualEffectMaterialView(material: style.fallbackMaterial)
                    style.fallbackTint
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()
            .glassRim(style: style, cornerRadius: cornerRadius, enabled: showsRim)
    }
}

private extension View {
    @ViewBuilder
    func glassRim(
        style: HaxGlassStyle,
        cornerRadius: CGFloat,
        enabled: Bool
    ) -> some View {
        if enabled {
            overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(style.rimColor, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(cornerRadius - 2, 0), style: .continuous)
                    .inset(by: 2)
                    .stroke(style.bevelColor, lineWidth: 0.75)
            }
        } else {
            self
        }
    }
}

// MARK: - 弱分隔线

struct SoftDivider: View {
    var horizontalInset: CGFloat = 18

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 0.5)
            .padding(.horizontal, horizontalInset)
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

// MARK: - 工具栏动作按钮

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
        .foregroundColor(.white.opacity(0.88))
        .padding(.horizontal, 11)
        .frame(height: 32)
        .fixedSize()
    }
}

struct ToolbarDragHandle: View {
    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(3), spacing: 3), count: 3),
            spacing: 3
        ) {
            ForEach(0..<9, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.52))
                    .frame(width: 2.5, height: 2.5)
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

// MARK: - 主按钮（发送等）

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(configuration.isPressed ? AppTheme.accent.opacity(0.8) : AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(configuration.isPressed ? AppTheme.mutedBg : AppTheme.cardBg.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

// MARK: - 推荐问题 chip

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(configuration.isPressed ? AppTheme.mutedBg : Color.white)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(AppTheme.border, lineWidth: 1)
            }
    }
}
