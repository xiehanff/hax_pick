# HaxPick 架构文档

本文档描述 HaxPick 的项目结构、构建方式与关键实现机制。AI 编码助手指引见仓库根目录 `CLAUDE.md` / `AGENTS.md`（本地文件，不入库）。

## 项目概述

HaxPick 是一个 macOS 菜单栏划词助手。用户划词后弹出悬浮工具栏，通过 DeepSeek API 执行翻译/解释/总结/润色/改写/提取要点。

## 构建与运行

```bash
# 构建（命令行）
xcodebuild -project hax_pick.xcodeproj -scheme hax_pick -configuration Debug build

# 运行（需要 Xcode，因为是 GUI 应用）
open hax_pick.xcodeproj  # 然后在 Xcode 中 ⌘R

# SPM 可作为依赖解析，但产物入口是 Xcode project
swift build  # 仅验证编译，不生成可运行的 .app
swift test   # 运行单元测试（SPM test target：HaxPickAppTests）
```

Xcode 工程无独立测试 target，单元测试由 SPM `HaxPickAppTests` 承载；无 lint/format 配置。

## 平台约束

- macOS 13+（`Package.swift` 声明 `.macOS(.v13)`，`Info.plist` 设 `LSMinimumSystemVersion = 13.0`）
- Swift 5.9（`Package.swift` `swift-tools-version: 5.9`）
- 应用是纯菜单栏模式：`LSUIElement = true` + `NSApp.setActivationPolicy(.accessory)`，**没有 Dock 图标**，因此也不能用 `NSApplication.shared.keyWindow` 等通常的主窗口 API

## 架构

```
HaxPickApp (SwiftUI @main, MenuBarExtra)
  └── AppDelegate → AppState.shared.start()
        └── AppState (单例，所有状态的唯一持有者)
              ├── SelectionMonitor (全局鼠标事件)
              │     ├── AccessibilityTextService (通道一)
              │     └── ClipboardSelectionService (通道二)
              ├── PermissionGuideWindowController (首次启动权限引导)
              ├── ToolbarPanelController (NSPanel 生命周期)
              │     ├── PanelSessionViewModel (独立文件，@ObservableObject)
              │     ├── FloatingToolbarView (SwiftUI 工具栏/结果面板)
              │     └── MarkdownWithCodeBlocks (Markdown + 代码高亮渲染)
              ├── MenuBarContentView (托盘卡片式 UI)
              └── DeepSeekService (API 调用)
```

**`AppState` 是唯一的状态中心。** 所有组件通过它协调：
- `AppState.shared` 持有 `SelectionMonitor`、`ToolbarPanelController`、`DeepSeekService` 的实例
- `SelectionMonitor` 检测到划词后通过回调通知 `AppState`
- `AppState.showToolbar(for:at:)` 将文本、坐标和 `DeepSeekService` 传给 `ToolbarPanelController`
- `ToolbarPanelController.show()` 创建/更新 `PanelSessionViewModel` 并弹出 `NSPanel`
- `AppState.start()` 在未开启辅助功能时会自动展示首次启动权限引导页
- `PanelSessionViewModel` 已独立为单独文件，不再内嵌在 `FloatingToolbarView.swift` 中

## 关键机制

### 双通道划词读取

`SelectionMonitor.handleMouseUp()` 中的读取顺序不可颠倒：

1. **Accessibility API**（`AccessibilityTextService.selectedTextSnapshot`）— `SelectionMonitor` 会在 `mouseUp` 当下先对当前焦点元素抓一份早期 AX 选区快照，随后再经过 150ms 等待和 2 次 AX 重试；如果目标应用自己的划词 toolbar 让后续选区消失，最终会回退到这份早快照。
2. **⌘C 兜底**（`ClipboardSelectionService.selectedTextBySimulatedCopy`）— 仅在通道一返回 `nil` 且当前焦点元素仍暴露 `kAXSelectedTextAttribute` / `kAXSelectedTextRangeAttribute` / `kAXNumberOfCharactersAttribute` 这类文本属性，或角色为浏览器 Web 内容区域（如 `AXWebArea`）时执行。流程仍然是“保存剪贴板 → 写 marker → 模拟 ⌘C → 读取后恢复”，但不再固定等待 400ms，而是最多轮询 400ms；一旦读到文本立即恢复，若外部程序已改写剪贴板则不再强行覆盖。

### 划词检测阈值

- 鼠标拖动距离 ≥ **8pt** 才视为有效划词（`SelectionMonitor.minimumSelectionDragDistance`）
- 鼠标抬起后等待 **150ms** 让系统完成选中状态更新
- 同一文本 **1.2s** 内不重复触发
- 用户关闭面板"忽略"的文本，在下次有效拖动前不再触发（`ignoredSelection`）

### 面板两个模式

`PanelSessionViewModel.PanelMode`：
- `.toolbar` — 紧凑工具栏 320×48pt，4 个平铺胶囊按钮（复制/翻译/解释/总结），左侧有九宫格拖动把手
- `.result` — 结果面板 436×628pt，顶部标题 + 原文区(可展开) + 滚动对话区(280pt) + 操作栏 + 继续提问区

模式切换通过 `viewModel.mode` 驱动，`onModeChanged` 回调触发 `ToolbarPanelController` 调整 `NSPanel` 的 `contentSize` 和 `frameOrigin`。焦点策略也按模式分离：`.toolbar` 只 `orderFront`，不主动 `activate`，并且 `hidesOnDeactivate = false`，避免在 app 未激活时刚显示就被系统收起；`.result` 才 `activate + makeKeyAndOrderFront`，同时恢复 `hidesOnDeactivate = true` 以支持失焦关闭。

### 对话气泡与结果区

`PanelSessionViewModel` 的结果不再用单个 `resultText` 字符串，而是 `conversationTurns: [ConversationTurn]`：
- 每个 `ConversationTurn` 包含 `question: String?`（用户追问）和 `answer: String`（AI 回复）
- 首次操作（翻译/解释等）的 turn 没有用户气泡；后续追问会追加用户气泡 + AI 气泡
- 结果区以 `LazyVStack` 渲染对话历史，用户消息右对齐深蓝白字，AI 消息左对齐带图标
- AI 回复通过 `MarkdownWithCodeBlocks` 渲染，按句号/问号/感叹号后换行自动分段，代码块以暗色卡片 + Swift 语法高亮展示

### 提示词分段策略

所有 system prompt / user prompt / 追问 prompt 末尾统一追加分段指令：

> `每个句子请用句号结尾并换行以形成自然段落；简短连续的内容请用逗号连接，不要强行断句。`

`MarkdownWithCodeBlocks` 客户端侧通过正则 `[。！？!?.][\n\s]+` 拆分段落，即使 AI 未严格遵循也能兜底。

### NSPanel 配置

`HaxPickPanel`（定义在 `Theme.swift`，继承 `NSPanel`，被 `ToolbarPanelController` 和 `PermissionGuideWindowController` 共享）的关键属性：
- `styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView]`
- `level: .floating` — 始终悬浮在普通窗口之上
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` — 跨桌面空间可用
- `hidesOnDeactivate = true`（工具栏面板）/ `false`（权限引导面板，需要用户手动关闭）
- `isMovableByWindowBackground = true` — 用户可拖拽
- `canBecomeKey = true` / `canBecomeMain = true` — 允许接收键盘事件（ESC 关闭）

`AppTheme.makeClippedHostingView(rootView:size:)` 是共享的圆角裁剪工具，将 SwiftUI 视图包裹在 `NSHostingView` → 圆角 `NSView` → 固定尺寸容器中。

### 应用图标

图标源文件位于 `hax_pick/` 目录（橙色 "h" 品牌图标）：
- `AppIcon.icns` — 产品图标，含 16~1024px 全尺寸族，由 Copy AppIcon 构建脚本拷贝到 `.app/Contents/Resources/`，`Info.plist` 的 `CFBundleIconFile` 引用
- `MenuBarIcon.png`(32px) / `MenuBarIcon@2x.png`(64px) — 托盘图标，按 16×16pt 显示（2 倍超采样），`NSImage` 加载时自动配对 `@2x` 变体

### API Key 存储

使用 `UserDefaults`（key: `deepseek_api_key`）。无默认 Key，用户需在菜单栏面板中自行填写自己的 DeepSeek API Key。

### DeepSeek API

- 端点：`https://api.deepseek.com/chat/completions`
- 模型：`deepseek-v4-flash` / `deepseek-v4-pro`
- 超时：45s
- 错误处理：优先解析 JSON `error.message`，失败则回退到 HTTP body 原始字符串

### 继续追问的上下文

追问请求的 user prompt 结构为「当前原文 + 上一轮结果 + 追问内容」，由 `DeepSeekService.buildPrompt()` 构建。结果**追加**到 `conversationTurns` 数组作为新一轮对话气泡，而非替换。

## 开发注意事项

- 所有 `@MainActor` 标注是必须的 — `NSEvent` 全局监听回调和 `AXUIElement` 操作都必须在主线程
- `AppState` 是 `@MainActor` 单例，`weak self` 捕获用于打破可能的循环引用（如 `DeepSeekService.apiKeyProvider`）
- `ToolbarPanelController` 复用同一个 `PanelSessionViewModel` 实例，每次 `show()` 调用 `viewModel.reset()` 清空旧状态
- 不要在 `FloatingToolbarView` 中直接操作 `NSPanel` — 所有面板级别的操作通过 `PanelSessionViewModel.onModeChanged` 回调，由 `ToolbarPanelController` 处理
- `ClipboardSelectionService` 的 `simulateCommandC()` 使用 CGEvent 的 `.cghidEventTap`，不要改用其他 tap 类型
