import AppKit
import SwiftUI

struct ResultPanelView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    private let tailID = "ai-chat-tail"
    @State private var followTailState = ChatFollowTailState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

            SoftDivider()

            sourceTextSection
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            SoftDivider()

            resultContentSection
                .padding(.horizontal, 18)
                .padding(.top, 16)

            actionButtonsRow
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            if viewModel.lastAssistantContent != nil && !viewModel.isLoading {
                SoftDivider(horizontalInset: 14)
                AiChatInputBar(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panelContent)
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppTheme.resultCorner - AppTheme.glassContentInset,
                style: .continuous
            )
        )
        .compositingGroup()
        .overlay {
            RoundedRectangle(
                cornerRadius: AppTheme.resultCorner - AppTheme.glassContentInset,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.78), lineWidth: 0.75)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.titleText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(viewModel.statusHint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Spacer()

            Button {
                viewModel.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.mutedBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
    }

    private var sourceTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("原文")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button {
                    viewModel.copyOriginalText()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("复制原文")
            }

            if viewModel.isOriginalExpanded {
                ScrollView {
                    sourceText
                }
                .frame(maxHeight: 112)
            } else {
                sourceText
                    .lineLimit(3)
            }

            if viewModel.selectedText.count > 140 {
                Button(viewModel.isOriginalExpanded ? "收起" : "展开全部") {
                    viewModel.toggleOriginalExpanded()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.accent)
            }
        }
    }

    private var resultContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.currentAction?.contentTitle ?? "结果")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
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
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            if !viewModel.isLoading &&
                                viewModel.conversationMessages.isEmpty &&
                                viewModel.errorMessage == nil {
                                Text("选择一个动作后，结果会出现在这里。")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(tailID)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        ManualScrollInteractionMonitor {
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
                .onChange(of: viewModel.requestRevision) { _ in
                    followTailState.requestDidStart()
                    DispatchQueue.main.async {
                        proxy.scrollTo(tailID, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 16) {
            if viewModel.canStop {
                Button {
                    viewModel.stopGeneration()
                } label: {
                    Label("停止生成", systemImage: "stop.circle")
                }
                .buttonStyle(InlineActionButtonStyle())
            } else {
                Button {
                    viewModel.retry()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                .buttonStyle(InlineActionButtonStyle())
                .disabled(!viewModel.canRetry)
            }

            Button {
                viewModel.copyResult()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(InlineActionButtonStyle())
            .disabled(viewModel.lastAssistantContent == nil)

            Spacer()
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

    private var sourceText: some View {
        Text(viewModel.selectedText)
            .font(.system(size: 13))
            .foregroundColor(AppTheme.textSecondary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        if viewModel.errorMessage != nil {
            return .orange
        }
        if viewModel.isLoading {
            return AppTheme.accent
        }
        return AppTheme.success
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

private struct InlineActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppTheme.textSecondary)
            .opacity(configuration.isPressed ? 0.55 : 1)
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

private struct ManualScrollInteractionMonitor: NSViewRepresentable {
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
            let mask: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDragged]
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point), Self.isManualScrollInteraction(event) else {
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

        private static func isManualScrollInteraction(_ event: NSEvent) -> Bool {
            switch event.type {
            case .scrollWheel:
                return abs(event.scrollingDeltaY) > 0.01 || abs(event.scrollingDeltaX) > 0.01
            case .leftMouseDragged:
                return true
            default:
                return false
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
