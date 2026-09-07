import SwiftUI

struct AiChatInputBar: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            SoftDivider(horizontalInset: 12)

            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    inputPlaceholder,
                    text: $viewModel.followUpInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1...4)
                .disabled(viewModel.isLoading)

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
                    .help("新建自由会话")
                    .accessibilityLabel("新建自由会话")

                    Spacer(minLength: 8)

                    if viewModel.isLoading {
                        Button {
                            viewModel.stopGeneration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(ComposerSendButtonStyle())
                        .help("停止生成")
                        .accessibilityLabel("停止生成")
                    } else {
                        Button {
                            viewModel.submitFollowUp()
                        } label: {
                            HaxIcon(asset: .send)
                                .frame(width: 14, height: 14)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(ComposerSendButtonStyle())
                        .disabled(!viewModel.canSubmitFollowUp)
                        .opacity(viewModel.canSubmitFollowUp ? 1 : 0.32)
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

    private var inputPlaceholder: String {
        if viewModel.isLoading {
            return "正在生成…"
        }
        return viewModel.isFreeChat ? "想聊什么都可以…" : "继续提问…"
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

private struct ComposerSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.textPrimary)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
