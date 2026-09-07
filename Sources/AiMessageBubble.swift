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
            HStack(alignment: .top) {
                Spacer(minLength: 56)
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.mutedBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if !message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AiReasoningDisclosure(
                        text: message.reasoning,
                        isStreaming: isStreaming
                    )
                }

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
                } else if isStreaming && message.reasoning.isEmpty {
                    ThinkingIndicator()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            EmptyView()
        }
    }
}

private struct AiReasoningDisclosure: View {
    let text: String
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .medium))

                    Text("思考过程")
                        .font(.system(size: 11.5, weight: .medium))

                    if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundColor(AppTheme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Group {
                    if isStreaming {
                        Text(text)
                            .font(.system(size: 11.5))
                            .lineSpacing(3)
                    } else {
                        MarkdownWithCodeBlocks(text: text)
                    }
                }
                .foregroundColor(AppTheme.textSecondary)
                .textSelection(.enabled)
                .padding(.leading, 17)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(AppTheme.mutedBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border.opacity(0.75), lineWidth: 0.75)
        }
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("正在思考…")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
        }
        .accessibilityLabel("正在思考")
    }
}
