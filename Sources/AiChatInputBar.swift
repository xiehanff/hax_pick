import SwiftUI

struct AiChatInputBar: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("继续提问")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)

            if !viewModel.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                viewModel.askSuggestion(suggestion)
                            }
                            .buttonStyle(ChipButtonStyle())
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("输入你的问题", text: $viewModel.followUpInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                Button("发送") {
                    viewModel.submitFollowUp()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSubmitFollowUp)
            }
        }
        .padding(14)
        .background(AppTheme.mutedBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
