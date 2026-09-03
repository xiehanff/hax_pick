import SwiftUI

struct PermissionGuideView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            steps
            actions
        }
        .padding(24)
        .frame(width: 480, height: 420)
        .background(AppTheme.background)
        .environment(\.colorScheme, .light)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 12) {
            AppBrandIcon(size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("HaxPick 权限引导")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(appState.permissionGranted ? "已授权，可以开始使用" : "需要辅助功能权限才能监听划词")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            Circle()
                .fill(appState.permissionGranted ? AppTheme.success : Color.orange)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: 步骤

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepItem(num: "1", title: "打开辅助功能页面", desc: "点击下方按钮，跳转到系统设置对应位置")
            Divider().padding(.leading, 36)
            stepItem(num: "2", title: "将 HaxPick 加入授权列表", desc: "在列表中勾选 HaxPick，允许读取选中文本")
            Divider().padding(.leading, 36)
            stepItem(num: "3", title: "回到这里刷新状态", desc: "授权后点击刷新，窗口会自动关闭")
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func stepItem(num: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Text(num)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: 操作

    private var actions: some View {
        HStack(spacing: 8) {
            Button("打开辅助功能设置") {
                appState.openAccessibilitySettings()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("刷新状态") {
                appState.refreshPermissionStatus()
                if appState.permissionGranted {
                    onClose()
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button("稍后再说") {
                onClose()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
