# macOS 图标资源约定

HaxPick 的图标只维护一个源文件：

```text
assets/app-icon.png
```

它必须是至少 `1024×1024` 的正方形 PNG。

## 派生资源

执行：

```bash
bash scripts/generate_macos_icons.sh hax_pick
```

会生成：

```text
assets/app-icon.png
        │
        ├── hax_pick/AppIcon.icns
        │      └── macOS .app / Finder / 系统设置 / 应用内品牌图标
        │
        ├── hax_pick/MenuBarIcon.png
        │      └── 16×16，菜单栏 1x 派生资源
        │
        └── hax_pick/MenuBarIcon@2x.png
               └── 32×32，菜单栏 Retina 运行时资源
```

`Sources/HaxPickApp.swift` 从最终 app bundle 明确读取 32px 的 `MenuBarIcon@2x.png`，并设置 16pt 逻辑尺寸，保证 Retina 显示清晰。`Sources/AppBrandIcon.swift` 直接使用 `NSApplication.shared.applicationIconImage`，不再放大托盘小图。`hax_pick/Info.plist` 通过 `CFBundleIconFile = AppIcon.icns` 声明应用图标。

## 修改图标时

不要单独修改 `hax_pick/AppIcon.icns` 或 `MenuBarIcon*.png`。

正确流程：

```text
替换 assets/app-icon.png
        ↓
bash scripts/generate_macos_icons.sh hax_pick
        ↓
提交源图 + 三个派生资源
```

CI 会重新生成派生资源并检查 Git diff；如果忘记同步，PR 会失败。

## 运行与验证

图标必须通过 Xcode 生成的 `.app` 验证：

```text
hax_pick.xcodeproj
  ↓
hax_pick scheme
  ↓
hax_pick.app
```

不要用 `swift run` 验证应用图标。SwiftPM 在本项目主要用于编译/测试，`Package.swift` 没有把 macOS bundle 图标作为 executable resource 打包；裸 executable 也不会拥有完整 `.app` bundle identity，因此 macOS 辅助功能列表可能显示通用可执行文件图标。

最终 `.app` 应满足：

```text
Contents/Info.plist
  CFBundleName        = HaxPick
  CFBundleDisplayName = HaxPick
  CFBundleIconFile    = AppIcon.icns

Contents/Resources/
  AppIcon.icns
  MenuBarIcon.png
  MenuBarIcon@2x.png
```

## macOS 系统缓存

系统设置 / Launch Services / TCC 可能短时间缓存旧的应用名称或图标。更新 `.app` 后应先：

1. 完全退出旧 HaxPick。
2. 从 Xcode 重新 Build & Run 新 `.app`。
3. 关闭并重新打开「系统设置 → 隐私与安全性 → 辅助功能」。

如果辅助功能列表里仍保留旧的裸 executable 条目（例如显示为 `hax_pick` + 通用图标），删除该旧条目，然后从新的 HaxPick `.app` 再次触发辅助功能授权即可。不要为了刷新图标默认执行全局 `tccutil reset`，因为那会重置权限状态。
