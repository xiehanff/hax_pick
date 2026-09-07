import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @State private var apiKeyVisible = false
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            runtimeCard
            aiSettingsCard
            footer
        }
        .padding(12)
        .frame(width: 336)
        .background(AppTheme.panelContent)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.menuCorner, style: .continuous))
        .compositingGroup()
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.menuCorner, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 0.75)
        }
        .padding(7)
        .frame(width: 350)
        .background(ClearMenuWindowBackground())
        .environment(\.colorScheme, .light)
        .onAppear {
            apiKeyDraft = appState.apiKey
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("HaxPick")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Text("划词 AI 助手")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(appState.permissionGranted ? AppTheme.success : .orange)
                    .frame(width: 6, height: 6)
                Text(appState.permissionGranted ? "运行中" : "需要权限")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(AppTheme.mutedBg.opacity(0.72))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var runtimeCard: some View {
        MenuCard(title: "运行状态", symbol: "waveform.path.ecg") {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("辅助功能")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(appState.permissionGranted ? "已开启，可以监听全局划词" : "开启后才能读取其他应用中的选中文本")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if appState.permissionGranted {
                    Button {
                        appState.refreshPermissionStatus()
                    } label: {
                        HaxIcon(asset: .refresh)
                            .frame(width: 12, height: 12)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(MenuIconButtonStyle())
                    .help("刷新权限状态")
                } else {
                    Button("去开启") {
                        appState.showPermissionGuide()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(AppTheme.accent)
                }
            }
        }
    }

    private var aiSettingsCard: some View {
        MenuCard(title: "AI 设置", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("模型")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("对划词动作和后续对话同时生效")
                            .font(.system(size: 9.5))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Picker("模型", selection: $appState.selectedModel) {
                        ForEach(appState.availableModels()) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 154)
                }

                Rectangle()
                    .fill(AppTheme.border.opacity(0.7))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DeepSeek API Key")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text(appState.apiKey.isEmpty ? "未配置" : "已配置")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(appState.apiKey.isEmpty ? .orange : AppTheme.success)
                    }

                    HStack(spacing: 7) {
                        HStack(spacing: 4) {
                            Group {
                                if apiKeyVisible {
                                    TextField("sk-…", text: $apiKeyDraft)
                                } else {
                                    SecureField("sk-…", text: $apiKeyDraft)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundColor(AppTheme.textPrimary)

                            Button {
                                apiKeyVisible.toggle()
                            } label: {
                                Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(AppTheme.textSecondary)
                            .help(apiKeyVisible ? "隐藏 API Key" : "显示 API Key")
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 4)
                        .frame(height: 31)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.75)
                        }

                        if appState.canRetryAPIKeyStorage {
                            Button("重试") {
                                retryAPIKeyStorage()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("保存") {
                                saveAPIKey()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(AppTheme.accent)
                            .disabled(!hasAPIKeyChanges && appState.apiKeyStorageError == nil)
                        }
                    }

                    Text(apiKeyStatusMessage)
                        .font(.system(size: 9.5))
                        .foregroundColor(apiKeyStatusColor)
                        .lineLimit(2)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(appState.appVersion)")
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.textSecondary.opacity(0.78))

            Spacer()

            Button {
                appState.openAccessibilitySettings()
            } label: {
                Label("辅助功能设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(AppTheme.textSecondary)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 0.5, height: 13)

            Button("退出") {
                appState.quitApp()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(AppTheme.textSecondary)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var hasAPIKeyChanges: Bool {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != appState.apiKey
    }

    private var apiKeyStatusMessage: String {
        appState.apiKeyStorageError ?? appState.apiKeyStorageStatusMessage
    }

    private var apiKeyStatusColor: Color {
        appState.apiKeyStorageError != nil || appState.apiKeyStorageNeedsAttention
            ? .orange
            : AppTheme.textSecondary
    }

    private func saveAPIKey() {
        if appState.saveAPIKey(apiKeyDraft) {
            apiKeyDraft = appState.apiKey
        }
    }

    private func retryAPIKeyStorage() {
        let committedBeforeRetry = appState.apiKey
        let draftWasUnmodified = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == committedBeforeRetry
        _ = appState.retryAPIKeyStorage()
        if draftWasUnmodified {
            apiKeyDraft = appState.apiKey
        }
    }
}

private struct MenuCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(AppTheme.textSecondary)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border.opacity(0.85), lineWidth: 0.75)
        }
    }
}

private struct MenuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.textSecondary)
            .background(AppTheme.mutedBg.opacity(configuration.isPressed ? 0.9 : 0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ClearMenuWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
            window?.contentView?.wantsLayer = true
            window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
