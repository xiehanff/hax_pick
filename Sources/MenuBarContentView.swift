import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @State private var apiKeyVisible = false
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 14)

            permissionSection
                .padding(.bottom, 12)

            apiKeySection
                .padding(.bottom, 12)

            modelSection
                .padding(.bottom, 16)

            bottomActions
        }
        .padding(16)
        .frame(width: 340)
        .background(AppTheme.background)
        .environment(\.colorScheme, .light)
        .onAppear {
            apiKeyDraft = appState.apiKey
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppBrandIcon(size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("HaxPick")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("划词助手")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Circle()
                    .fill(appState.permissionGranted ? AppTheme.success : Color.orange)
                    .frame(width: 8, height: 8)
            }

            Text(appState.statusMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.top, 8)
        }
    }

    private var permissionSection: some View {
        cardSection(title: "权限") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("辅助功能", systemImage: "hand.raised")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text(appState.permissionGranted ? "已开启" : "未开启")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(appState.permissionGranted ? AppTheme.success : Color.orange)
                }

                Text("开启后可监听全局划词并弹出工具栏。")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    Button("去开启") {
                        appState.showPermissionGuide()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("刷新") {
                        appState.refreshPermissionStatus()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var apiKeySection: some View {
        cardSection(title: "API Key") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Group {
                        if apiKeyVisible {
                            TextField("输入 DeepSeek API Key", text: $apiKeyDraft)
                        } else {
                            SecureField("输入 DeepSeek API Key", text: $apiKeyDraft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)

                    Button {
                        apiKeyVisible.toggle()
                    } label: {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(apiKeyVisible ? "隐藏 API Key" : "显示 API Key")
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(AppTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                HStack(spacing: 8) {
                    if let apiKeyStorageError = appState.apiKeyStorageError {
                        Text(apiKeyStorageError)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Key 保存在 macOS Keychain，修改后点击保存。")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("保存") {
                        if appState.saveAPIKey(apiKeyDraft) {
                            apiKeyDraft = appState.apiKey
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(
                        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == appState.apiKey &&
                        appState.apiKeyStorageError == nil
                    )
                }
            }
        }
    }

    private var modelSection: some View {
        cardSection(title: "模型") {
            HStack(spacing: 0) {
                ForEach(appState.availableModels()) { model in
                    Button {
                        appState.selectedModel = model
                    } label: {
                        Text(model.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(appState.selectedModel == model ? .white : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                appState.selectedModel == model
                                    ? AppTheme.accent
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppTheme.mutedBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 8) {
            Button("系统设置") {
                appState.openAccessibilitySettings()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button("退出") {
                appState.quitApp()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func cardSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)
            content()
        }
        .padding(12)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}
