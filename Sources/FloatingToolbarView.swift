import SwiftUI

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .toolbar:
                ZStack {
                    ToolbarRainbowBackground()
                        .clipShape(Capsule())
                    glassToolbar
                }
                .frame(
                    width: FloatingPanelLayout.toolbarSize.width,
                    height: FloatingPanelLayout.toolbarSize.height
                )
            case .result:
                HaxGlassSurface(style: .light, cornerRadius: AppTheme.resultCorner) {
                    ResultPanelView(viewModel: viewModel)
                        .padding(AppTheme.glassContentInset)
                }
            }
        }
        .environment(\.colorScheme, .light)
    }

    /// 高斯模糊工具栏：系统玻璃材质只采样窗口后方内容，无法模糊同一窗口内的
    /// 彩虹背景，因此在玻璃层内绘制与底层像素对齐的彩虹模糊副本，再叠磨砂白。
    private var glassToolbar: some View {
        toolbarView
            .frame(
                width: FloatingPanelLayout.toolbarSize.width,
                height: FloatingPanelLayout.toolbarSize.height
            )
            .background {
                ZStack {
                    ToolbarRainbowBackground()
                        .frame(
                            width: FloatingPanelLayout.toolbarSize.width,
                            height: FloatingPanelLayout.toolbarSize.height
                        )
                        .blur(radius: 12)
                    Color.white.opacity(0.75)
                }
            }
            .clipShape(Capsule())
    }

    private var toolbarView: some View {
        HStack(spacing: 6) {
            ToolbarDragHandle()
                .frame(width: 15, height: 32)
                .allowsHitTesting(false)

            AppBrandIcon(size: 34)

            Button {
                viewModel.handlePrimaryAction(.copy)
            } label: {
                ToolbarTextButton(title: AiToolAction.copy.rawValue)
            }
            .buttonStyle(.plain)
            .help("复制原文")
            .accessibilityLabel("复制原文")

            ForEach(AiToolAction.primaryActions) { action in
                Button {
                    viewModel.handlePrimaryAction(action)
                } label: {
                    ToolbarTextButton(title: action.rawValue)
                }
                .buttonStyle(.plain)
            }

            ToolbarTextButton(
                title: "深度理解",
                foregroundColor: .black
            )
            .help("暂未实现")

            ToolbarTextButton(
                title: "润色",
                foregroundColor: .black
            )
            .help("暂未实现")
        }
        .padding(.leading, 22)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 上半环角向渐变色块：以底边中点为圆心、只扫上半圈（去掉底部 1/2 的环），
/// 左右对称，中心（拱顶）最深，向两侧渐浅。
struct ToolbarRainbowBackground: View {
    var body: some View {
        AngularGradient(
            stops: [
                .init(color: Color(hex: 0xEAf4fe), location: 0),
                .init(color: Color(hex: 0xA9CDF9), location: 0.5),
                .init(color: Color(hex: 0xEAf4fe), location: 1),
            ],
            center: .bottom,
            startAngle: .degrees(180),
            endAngle: .degrees(360)
        )
    }
}
