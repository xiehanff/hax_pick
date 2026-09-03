import SwiftUI

struct AiMessageBubble: View {
    let message: AiMessage
    let isStreaming: Bool

    init(message: AiMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    @ViewBuilder
    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            if !message.content.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    AppBrandIcon(size: 20)
                        .opacity(0.7)

                    Group {
                        if isStreaming {
                            Text(message.content)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        } else {
                            MarkdownWithCodeBlocks(text: message.content)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.mutedBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer(minLength: 12)
                }
            }
        case .system:
            EmptyView()
        }
    }
}
