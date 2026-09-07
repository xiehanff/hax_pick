import SwiftUI

/// 系统样式的设置窗口：辅助功能权限、模型选择、DeepSeek API Key、版本号。
struct SettingsContentView: View {
    @ObservedObject var appState: AppState
    @State private var apiKeyDraft = ""
    @State private var apiKeyVisible = false

    var body: some View {
        Form {
            Section("辅助功能权限") {
                HStack(spacing: 8) {
                    Image(
                        systemName: appState.permissionGranted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundColor(appState.permissionGranted ? .green : .orange)

                    Text(appState.permissionGranted
                        ? "已开启，可以监听全局划词"
                        : "开启后才能读取其他应用中的选中文本")

                    Spacer()

                    if appState.permissionGranted {
                        Button("刷新") {
                            appState.refreshPermissionStatus()
                        }
                    } else {
                        Button("去开启") {
                            appState.showPermissionGuide()
                        }
                    }
                }
            }

            Section("AI 设置") {
                Picker("模型", selection: $appState.selectedModel) {
                    ForEach(appState.availableModels()) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: appState.selectedModel) { _ in
                    appState.refreshPermissionStatus()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Group {
                            if apiKeyVisible {
                                TextField("DeepSeek API Key", text: $apiKeyDraft)
                            } else {
                                SecureField("DeepSeek API Key", text: $apiKeyDraft)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            apiKeyVisible.toggle()
                        } label: {
                            Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                        }
                        .help(apiKeyVisible ? "隐藏 API Key" : "显示 API Key")

                        if appState.canRetryAPIKeyStorage {
                            Button("重试") {
                                retryAPIKeyStorage()
                            }
                        } else {
                            Button("保存") {
                                saveAPIKey()
                            }
                            .disabled(!hasAPIKeyChanges && appState.apiKeyStorageError == nil)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(appState.apiKey.isEmpty ? "未配置" : "已配置")
                            .foregroundColor(appState.apiKey.isEmpty ? .orange : .green)
                        Text(apiKeyStatusMessage)
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                    .lineLimit(2)
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "v\(appState.appVersion)")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKeyDraft = appState.apiKey
        }
    }

    private var hasAPIKeyChanges: Bool {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != appState.apiKey
    }

    private var apiKeyStatusMessage: String {
        appState.apiKeyStorageError ?? appState.apiKeyStorageStatusMessage
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
