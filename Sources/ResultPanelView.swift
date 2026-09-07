import AppKit
import SwiftUI

struct ResultPanelView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    private let tailID = "ai-chat-tail"
    @State private var followTailState = ChatFollowTailState()
    @State private var conversationViewportHeight: CGFloat = 0
    @State private var tailMaxY: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conversationHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

            SoftDivider(horizontalInset: 12)

            conversation

            AiChatInputBar(viewModel: viewModel)
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

    private var conversationHeader: some View {
        HStack(spacing: 9) {
            AppBrandIcon(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.currentAction?.rawValue ?? "AI 对话")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(
                        viewModel.currentAction == .deepDive
                            ? AppTheme.textPrimary.opacity(0.78)
                            : AppTheme.textPrimary
                    )

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(viewModel.statusHint)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CloseButtonStyle())
            .help("关闭")
            .accessibilityLabel("关闭")
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if viewModel.showsSourceTurn {
                            SourceTurnBubble(viewModel: viewModel)
                        }

                        ForEach(viewModel.conversationMessages) { message in
                            AiMessageBubble(
                                message: message,
                                isStreaming: message.id == viewModel.streamingAssistantID,
                                assistantContentOpacity: viewModel.currentAction == .deepDive ? 0.78 : 1
                            )
                        }

                        if viewModel.isLoading && viewModel.streamingAssistantID == nil {
                            HStack(spacing: 7) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在思考…")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            errorBubble(errorMessage)
                        }

                        if !viewModel.isLoading && !viewModel.suggestions.isEmpty {
                            FollowUpSuggestions(
                                suggestions: viewModel.suggestions,
                                onTap: { viewModel.askSuggestion($0) }
                            )
                        }

                        if !viewModel.isLoading &&
                            (viewModel.lastAssistantContent != nil || viewModel.canRetry) {
                            assistantActions
                        }

                        Color.clear
                            .frame(height: 1)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ConversationTailMaxYPreferenceKey.self,
                                        value: geometry.frame(
                                            in: .named(ConversationScrollCoordinateSpace.name)
                                        ).maxY
                                    )
                                }
                            }
                            .id(tailID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .coordinateSpace(name: ConversationScrollCoordinateSpace.name)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ConversationViewportHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
                .background(
                    ManualScrollInteractionMonitor {
                        followTailState.userDidScroll()
                        viewModel.pauseStreamingPresentation()
                    }
                )

                if !followTailState.isFollowingTail {
                    Button {
                        viewModel.resumeStreamingPresentation()
                        followTailState.resume()
                        DispatchQueue.main.async {
                            proxy.scrollTo(tailID, anchor: .bottom)
                        }
                    } label: {
                        Label("回到最新", systemImage: "arrow.down")
                    }
                    .buttonStyle(ReturnToLatestButtonStyle())
                    .padding(10)
                }
            }
            .onPreferenceChange(ConversationViewportHeightPreferenceKey.self) { height in
                conversationViewportHeight = height
            }
            .onPreferenceChange(ConversationTailMaxYPreferenceKey.self) { maxY in
                let previousMaxY = tailMaxY
                tailMaxY = maxY

                guard previousMaxY.isFinite else { return }
                let movingTowardTail = maxY < previousMaxY - 0.5
                let extentAfter = max(0, maxY - conversationViewportHeight)
                guard followTailState.tailPositionDidChange(
                    extentAfter: extentAfter,
                    movingTowardTail: movingTowardTail
                ) else { return }

                viewModel.resumeStreamingPresentation()
                DispatchQueue.main.async {
                    proxy.scrollTo(tailID, anchor: .bottom)
                }
            }
            .onChange(of: scrollSignal) { _ in
                guard followTailState.isFollowingTail else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(tailID, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.requestRevision) { _ in
                viewModel.resumeStreamingPresentation()
                followTailState.requestDidStart()
                DispatchQueue.main.async {
                    proxy.scrollTo(tailID, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var assistantActions: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.retry()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
            .buttonStyle(InlineActionButtonStyle())
            .disabled(!viewModel.canRetry)

            Button {
                viewModel.copyResult()
            } label: {
                Label {
                    Text("复制回答")
                } icon: {
                    HaxIcon(asset: .copy)
                        .frame(width: 12, height: 12)
                }
            }
            .buttonStyle(InlineActionButtonStyle())
            .disabled(viewModel.lastAssistantContent == nil)

            Spacer()
        }
    }

    private func errorBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                Text("请求失败")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(.orange)

            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(AppTheme.textSecondary)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.mutedBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusColor: Color {
        if viewModel.errorMessage != nil { return .orange }
        if viewModel.isLoading { return AppTheme.accent }
        if viewModel.didStop { return .orange }
        return AppTheme.success
    }

    private var scrollSignal: ScrollSignal {
        let lastMessage = viewModel.conversationMessages.last
        return ScrollSignal(
            messageCount: viewModel.conversationMessages.count,
            lastMessageID: lastMessage?.id,
            draftRevision: viewModel.draftRevision,
            suggestionCount: viewModel.suggestions.count,
            hasError: viewModel.errorMessage != nil,
            isLoading: viewModel.isLoading
        )
    }
}

private enum ConversationScrollCoordinateSpace {
    static let name = "ai-conversation-scroll"
}

private struct ConversationViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ConversationTailMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SourceTurnBubble: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(viewModel.currentAction?.rawValue ?? "原文")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.56))

            Text(viewModel.selectedText)
                .font(.system(size: 12.5))
                .foregroundColor(Color.white.opacity(0.86))
                .lineSpacing(3)
                .lineLimit(viewModel.isOriginalExpanded ? nil : 6)
                .textSelection(.enabled)

            if viewModel.selectedText.count > 180 {
                Button(viewModel.isOriginalExpanded ? "收起" : "展开原文") {
                    viewModel.toggleOriginalExpanded()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.70))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0x303136).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FollowUpSuggestions: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("继续追问")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)

            SuggestionFlowLayout(spacing: 7) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        onTap(suggestion)
                    }
                    .buttonStyle(SuggestionButtonStyle())
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct SuggestionFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 10_000
        var measuredWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0 && lineWidth + spacing + size.width > maxWidth {
                measuredWidth = max(measuredWidth, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth == 0 ? 0 : spacing) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        measuredWidth = max(measuredWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(
            width: proposal.width ?? measuredWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct SuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5))
            .foregroundColor(AppTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.mutedBg.opacity(configuration.isPressed ? 0.9 : 0.64))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(AppTheme.border, lineWidth: 0.75)
            }
    }
}

private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.black.opacity(configuration.isPressed ? 0.68 : 0.86))
            .clipShape(Circle())
    }
}

private struct InlineActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(AppTheme.textSecondary)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct ReturnToLatestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.94))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(AppTheme.border, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct ChatFollowTailState: Equatable {
    private(set) var isFollowingTail = true
    static let resumeThreshold: CGFloat = 80

    mutating func userDidScroll() {
        guard isFollowingTail else { return }
        isFollowingTail = false
    }

    mutating func requestDidStart() {
        guard !isFollowingTail else { return }
        isFollowingTail = true
    }

    mutating func resume() {
        guard !isFollowingTail else { return }
        isFollowingTail = true
    }

    @discardableResult
    mutating func tailPositionDidChange(
        extentAfter: CGFloat,
        movingTowardTail: Bool
    ) -> Bool {
        guard !isFollowingTail,
              movingTowardTail,
              extentAfter.isFinite,
              extentAfter <= Self.resumeThreshold else {
            return false
        }

        isFollowingTail = true
        return true
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
    let suggestionCount: Int
    let hasError: Bool
    let isLoading: Bool
}
