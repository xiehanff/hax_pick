import AppKit
import SwiftUI

struct ResultPanelView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    private let tailID = "ai-chat-tail"
    @State private var followTailState = ChatFollowTailState()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerRow
            sourceTextSection
            resultContentSection
            actionButtonsRow
            if viewModel.lastAssistantContent != nil && !viewModel.isLoading {
                AiChatInputBar(viewModel: viewModel)
            }
        }
        .frame(width: 404)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.titleText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(viewModel.statusHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            Button("关闭") {
                viewModel.close()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var sourceTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("原文")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
                    .tracking(0.5)
                Spacer()
                Button("复制原文") {
                    viewModel.copyOriginalText()
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            ScrollView {
                Text(viewModel.selectedText)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(viewModel.isOriginalExpanded ? nil : 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: viewModel.isOriginalExpanded ? 100 : 42)

            if viewModel.selectedText.count > 140 {
                Button(viewModel.isOriginalExpanded ? "收起" : "展开全部") {
                    viewModel.toggleOriginalExpanded()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.accent)
            }
        }
        .padding(14)
        .background(AppTheme.mutedBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var resultContentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.currentAction?.contentTitle ?? "结果")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
                    .tracking(0.5)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                }
            }

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.conversationMessages) { message in
                                AiMessageBubble(
                                    message: message,
                                    isStreaming: message.id == viewModel.streamingAssistantID
                                )
                            }

                            if let errorMessage = viewModel.errorMessage {
                                errorBubble(errorMessage)
                            }

                            if viewModel.isLoading {
                                Text("正在生成...")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            if !viewModel.isLoading &&
                                viewModel.conversationMessages.isEmpty &&
                                viewModel.errorMessage == nil {
                                Text("选择一个动作后，结果会出现在这里。")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(tailID)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        ScrollWheelInteractionMonitor {
                            followTailState.userDidScroll()
                        }
                    )

                    if !followTailState.isFollowingTail {
                        Button("回到最新") {
                            followTailState.resume()
                            DispatchQueue.main.async {
                                proxy.scrollTo(tailID, anchor: .bottom)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(8)
                    }
                }
                .onChange(of: scrollSignal) { _ in
                    guard followTailState.isFollowingTail else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(tailID, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isLoading) { isLoading in
                    guard isLoading else { return }
                    followTailState.requestDidStart()
                    DispatchQueue.main.async {
                        proxy.scrollTo(tailID, anchor: .bottom)
                    }
                }
            }
            .frame(height: viewModel.isOriginalExpanded ? 250 : 280)
        }
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            if viewModel.canStop {
                Button("停止生成") {
                    viewModel.stopGeneration()
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("重新生成") {
                    viewModel.retry()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!viewModel.canRetry)
            }

            Button("复制结果") {
                viewModel.copyResult()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.lastAssistantContent == nil)

            Spacer()

            Button("关闭") {
                viewModel.close()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func errorBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("请求失败")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.mutedBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var scrollSignal: ScrollSignal {
        let lastMessage = viewModel.conversationMessages.last
        return ScrollSignal(
            messageCount: viewModel.conversationMessages.count,
            lastMessageID: lastMessage?.id,
            draftRevision: viewModel.draftRevision,
            hasError: viewModel.errorMessage != nil,
            isLoading: viewModel.isLoading
        )
    }
}

struct ChatFollowTailState: Equatable {
    private(set) var isFollowingTail = true

    mutating func userDidScroll() {
        isFollowingTail = false
    }

    mutating func requestDidStart() {
        isFollowingTail = true
    }

    mutating func resume() {
        isFollowingTail = true
    }
}

private struct ScrollWheelInteractionMonitor: NSViewRepresentable {
    let onUserScroll: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUserScroll = onUserScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var view: NSView?
        var onUserScroll: () -> Void
        private var eventMonitor: Any?

        init(onUserScroll: @escaping () -> Void) {
            self.onUserScroll = onUserScroll
        }

        func installMonitor() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                let hasScrollDelta = abs(event.scrollingDeltaY) > 0.01 || abs(event.scrollingDeltaX) > 0.01
                guard hasScrollDelta, view.bounds.contains(point) else {
                    return event
                }

                DispatchQueue.main.async { [weak self] in
                    self?.onUserScroll()
                }
                return event
            }
        }

        func removeMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

private struct ScrollSignal: Equatable {
    let messageCount: Int
    let lastMessageID: UUID?
    let draftRevision: Int
    let hasError: Bool
    let isLoading: Bool
}
