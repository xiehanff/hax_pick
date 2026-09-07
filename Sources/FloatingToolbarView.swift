import SwiftUI

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .toolbar:
                HaxGlassSurface(
                    style: .light,
                    cornerRadius: FloatingPanelLayout.toolbarSize.height / 2
                ) {
                    toolbarView
                        .background(AppTheme.panelContent)
                        .clipShape(Capsule())
                        .compositingGroup()
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.78), lineWidth: 0.75)
                        }
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
