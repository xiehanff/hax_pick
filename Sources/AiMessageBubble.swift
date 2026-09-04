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
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mutedBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            if !message.content.isEmpty {
                Group {
                    if isStreaming {
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    } else {
                        MarkdownWithCodeBlocks(text: message.content)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .system:
            EmptyView()
        }
    }
}
