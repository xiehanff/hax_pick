import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @State private var apiKeyVisible = false
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            SoftDivider(horizontalInset: 12)

            permissionSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            SoftDivider(horizontalInset: 12)

            apiKeySection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            SoftDivider(horizontalInset: 12)

            modelSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            SoftDivider(horizontalInset: 12)

            bottomActions
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .frame(width: 304)
        .background(AppTheme.panelContent)
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppTheme.menuCorner - 8,
                style: .continuous
            )
        )
        .compositingGroup()
        .overlay {
            RoundedRectangle(
                cornerRadius: AppTheme.menuCorner - 8,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.76), lineWidth: 0.75)
        }
        .padding(8)
        .frame(width: 320)
        .background(ClearMenuWindowBackground())
        .environment(\.colorScheme, .light)
        .onAppear {
            apiKeyDraft = appState.apiKey
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("HaxPick")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Text(appState.statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            Circle()
                .fill(appState.permissionGranted ? AppTheme.success : Color.orange)
                .frame(width: 7, height: 7)
                .accessibilityLabel(appState.permissionGranted ? "运行正常" : "需要辅助功能权限")
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: appState.permissionGranted ? 0 : 9) {
            HStack(spacing: 9) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("辅助功能")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(appState.permissionGranted ? "已开启，可监听全局划词" : "开启后才能读取选中的文本")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Text(appState.permissionGranted ? "已开启" : "未开启")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(appState.permissionGranted ? AppTheme.success : Color.orange)

                Button {
                    appState.refreshPermissionStatus()
                } label: {
                    HaxIcon(asset: .refresh)
                        .frame(width: 12, height: 12)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textSecondary)
                .help("刷新权限状态")
                .accessibilityLabel("刷新权限状态")
            }

            if !appState.permissionGranted {
                Button("开启辅助功能") {
                    appState.showPermissionGuide()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppTheme.accent)
                .padding(.leading, 27)
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DEEPSEEK API KEY")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)

            HStack(spacing: 7) {
                HStack(spacing: 4) {
                    Group {
                        if apiKeyVisible {
                            TextField("输入 API Key", text: $apiKeyDraft)
                        } else {
                            SecureField("输入 API Key", text: $apiKeyDraft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.textPrimary)

                    Button {
                        apiKeyVisible.toggle()
                    } label: {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(apiKeyVisible ? "隐藏 API Key" : "显示 API Key")
                }
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(height: 30)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasAPIKeyChanges && appState.apiKeyStorageError == nil)
                }
            }

            Text(apiKeyStatusMessage)
                .font(.system(size: 9.5))
                .foregroundColor(apiKeyStatusColor)
                .lineLimit(2)
        }
    }

    private var modelSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 18)

            Text("模型")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            Picker("模型", selection: $appState.selectedModel) {
                ForEach(appState.availableModels()) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 148)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 4) {
            Text("v\(appState.appVersion)")
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.textSecondary.opacity(0.82))

            Spacer()

            Button {
                appState.openAccessibilitySettings()
            } label: {
                Label("系统设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(AppTheme.textSecondary)

            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(width: 0.5, height: 13)
                .padding(.horizontal, 5)

            Button("退出") {
                appState.quitApp()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(AppTheme.textSecondary)
            .keyboardShortcut(.cancelAction)
        }
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
