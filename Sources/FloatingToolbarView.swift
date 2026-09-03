import SwiftUI
// MARK: - 主视图

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: PanelSessionViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .toolbar:
                toolbarView
            case .result:
                resultView
            }
        }
        .padding(viewModel.mode == .toolbar ? 10 : 18)
        .frame(
            width: viewModel.mode == .toolbar
                ? FloatingPanelLayout.toolbarSize.width
                : FloatingPanelLayout.resultSize.width
        )
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
    }

    // MARK: - 工具栏视图

    private var toolbarView: some View {
        HStack(spacing: 4) {
            dragHandleView

            ForEach(DeepSeekService.ToolAction.primaryActions) { action in
                Button {
                    viewModel.handlePrimaryAction(action)
                } label: {
                    CapsuleToolButton(title: action.rawValue,
                                      icon: action.symbolName)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 32)
    }

    private var dragHandleView: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AppTheme.textSecondary)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .padding(.leading, 2)
        .frame(width: 16, height: 16)
        .help("可拖动面板位置")
    }

    // MARK: - 结果面板视图

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerRow
            sourceTextSection
            resultContentSection
            actionButtonsRow
            if !viewModel.suggestions.isEmpty { followUpSection }
        }
        .frame(width: 404)
    }

    // MARK: 顶部标题区

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

    // MARK: 原文区

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

    // MARK: 结果内容区

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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.conversationTurns) { turn in
                        if let question = turn.question {
                            userBubble(question)
                        }
                        aiBubble(turn.answer)
                    }

                    if viewModel.isLoading && viewModel.conversationTurns.isEmpty {
                        Text("正在生成...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    if !viewModel.isLoading && viewModel.conversationTurns.isEmpty {
                        Text("选择一个动作后，结果会出现在这里。")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func aiBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AppBrandIcon(size: 20)
                .opacity(0.7)
            
            MarkdownWithCodeBlocks(text: text)
                .padding(12)
                .background(AppTheme.mutedBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 12)
        }
    }

    // MARK: 底部操作栏

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Button("重新生成") { viewModel.retry() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isLoading || viewModel.currentAction == nil)

            Button("复制结果") { viewModel.copyResult() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.conversationTurns.isEmpty)

            Spacer()

            Button("关闭") { viewModel.close() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: 继续提问区

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("继续提问")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)

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
