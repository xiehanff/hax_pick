import SwiftUI

struct AiChatInputBar: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                TextField("继续提问...", text: $viewModel.followUpInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textPrimary)
                    .onSubmit(viewModel.submitFollowUp)

                Button {
                    viewModel.submitFollowUp()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmitFollowUp)
                .opacity(viewModel.canSubmitFollowUp ? 1 : 0.42)
                .help("发送")
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 40)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}
