import SwiftUI

struct AiChatInputBar: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            SoftDivider(horizontalInset: 12)

            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    viewModel.isLoading ? "正在生成…" : "继续提问…",
                    text: $viewModel.followUpInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1...4)
                .disabled(viewModel.isLoading)
                .onSubmit(viewModel.submitFollowUp)

                HStack(spacing: 6) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ComposerIconButtonStyle())
                    .disabled(!viewModel.canStartNewConversation)
                    .help("新建会话")
                    .accessibilityLabel("新建会话")

                    Text(viewModel.isLoading ? "生成中" : "Return 发送")
                        .font(.system(size: 9.5))
                        .foregroundColor(AppTheme.textSecondary.opacity(0.72))

                    Spacer(minLength: 8)

                    if viewModel.isLoading {
                        Button {
                            viewModel.stopGeneration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(ComposerPrimaryButtonStyle())
                        .help("停止生成")
                        .accessibilityLabel("停止生成")
                    } else {
                        Button {
                            viewModel.submitFollowUp()
                        } label: {
                            HaxIcon(asset: .send)
                                .frame(width: 13, height: 13)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(ComposerPrimaryButtonStyle())
                        .disabled(!viewModel.canSubmitFollowUp)
                        .opacity(viewModel.canSubmitFollowUp ? 1 : 0.42)
                        .help("发送")
                        .accessibilityLabel("发送")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.75)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Color.white.opacity(0.72))
    }
}

private struct ComposerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.textSecondary)
            .background(AppTheme.mutedBg.opacity(configuration.isPressed ? 0.72 : 0.46))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ComposerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
