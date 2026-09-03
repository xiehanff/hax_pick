import SwiftUI

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .toolbar:
                toolbarView
            case .result:
                ResultPanelView(viewModel: viewModel)
            }
        }
        .padding(viewModel.mode == .toolbar ? 10 : 18)
        .frame(
            width: viewModel.mode == .toolbar
                ? FloatingPanelLayout.toolbarSize.width
                : FloatingPanelLayout.resultSize.width
        )
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
    }

    private var toolbarView: some View {
        HStack(spacing: 4) {
            dragHandleView

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
        .frame(height: 32)
    }

    private var dragHandleView: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AppTheme.textSecondary)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .padding(.leading, 2)
        .frame(width: 16, height: 16)
        .help("可拖动面板位置")
    }
}
