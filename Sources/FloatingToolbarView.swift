import SwiftUI

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .toolbar:
                HaxGlassSurface(
                    style: .dark,
                    cornerRadius: AppTheme.toolbarCorner,
                    showsRim: false
                ) {
                    toolbarView
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.16))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AppTheme.toolbarCorner - 3,
                                style: .continuous
                            )
                        )
                        .compositingGroup()
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: AppTheme.toolbarCorner - 3,
                                style: .continuous
                            )
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }
                        .padding(3)
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

    private var toolbarView: some View {
        HStack(spacing: 5) {
            ToolbarDragHandle()
                .frame(width: 24, height: 32)
                .allowsHitTesting(false)

            AppBrandIcon(size: 38)

            Text("已选中 \(viewModel.selectedText.count) 个字符")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1, height: 20)

            Button {
                viewModel.handlePrimaryAction(.copy)
            } label: {
                HaxIcon(asset: .copy)
                    .foregroundColor(.white.opacity(0.88))
                    .frame(width: 14, height: 14)
                    .frame(width: 26, height: 32)
            }
            .buttonStyle(.plain)
            .help("复制原文")
            .accessibilityLabel("复制原文")

            ForEach(AiToolAction.primaryActions) { action in
                Button {
                    viewModel.handlePrimaryAction(action)
                } label: {
                    CapsuleToolButton(
                        title: action.rawValue,
                        icon: action.symbolName
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
