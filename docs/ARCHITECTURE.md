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

Xcode 工程无独立测试 target，单元测试由 SPM `HaxPickAppTests` 承载。GitHub Actions 会在 PR 与 `main` push 上运行 `swift test` 和实际 macOS Xcode build。

## 平台约束

- macOS 13+（`Package.swift` 声明 `.macOS(.v13)`，`Info.plist` 设 `LSMinimumSystemVersion = 13.0`）
- Swift 5.9（`Package.swift` `swift-tools-version: 5.9`）
- 应用是纯菜单栏模式：`LSUIElement = true` + `NSApp.setActivationPolicy(.accessory)`，**没有 Dock 图标**，因此也不能依赖普通主窗口生命周期

## 架构

```text
HaxPickApp (SwiftUI @main, MenuBarExtra)
  └── AppDelegate → AppState.shared.start()
        └── AppState（应用生命周期 / 顶层编排）
              ├── SelectionMonitor（全局鼠标事件）
              │     ├── AccessibilityTextService
              │     └── ClipboardSelectionService
              ├── PermissionGuideWindowController
              ├── ToolbarPanelController（NSPanel 生命周期）
              │     └── PanelSessionViewModel（Panel / UI 状态）
              │           └── AiAgentSession（AI 会话状态与请求生命周期）
              │                 ├── AiMessage
              │                 ├── AiToolAction
              │                 ├── AiPrompts
              │                 └── DeepSeekService（HTTP / DTO / 错误映射）
              └── MenuBarContentView
```

`AppState` 不再被定义为“所有状态唯一持有者”。它仍负责应用级生命周期和组件编排；单次划词 AI 会话的 history、loading、error、generation、retry/cancel 由 `AiAgentSession` 独立持有。

职责边界：

- `AppState`：权限、设置、SelectionMonitor、Panel Controller、DeepSeekService 实例编排
- `ToolbarPanelController`：NSPanel 创建、定位、聚焦、dismiss
- `PanelSessionViewModel`：toolbar/result 模式、选中文本、输入框、原文展开状态，以及对 `AiAgentSession` 的 UI 投影
- `AiAgentSession`：AI history、请求生命周期、generation、cancel、retry、rollback
- `AiPrompts`：system prompt / 首次工具 prompt
- `AiToolAction`：工具动作与展示 metadata
- `DeepSeekService`：把 `[AiMessage]` 序列化并发送到 DeepSeek，不再决定业务 prompt 或 conversation history

## 关键机制

### 双通道划词读取

`SelectionMonitor.handleMouseUp()` 中的读取顺序不可颠倒：

1. **Accessibility API**（`AccessibilityTextService.selectedTextSnapshot`）— `SelectionMonitor` 会在 `mouseUp` 当下先抓早期 AX 选区快照，再经过 150ms 等待和 AX 重试；如果目标应用自己的划词 toolbar 让后续选区消失，最终会回退到早期快照。
2. **⌘C 兜底**（`ClipboardSelectionService.selectedTextBySimulatedCopy`）— 仅在 AX 通道失败且目标仍表现为可读取文本区域时执行。流程为“保存剪贴板 → 写 marker → 模拟 ⌘C → 读取后恢复”，并避免覆盖期间出现的外部剪贴板修改。

### 划词检测阈值

- 鼠标拖动距离 ≥ **8pt** 才视为有效划词
- 鼠标抬起后等待 **150ms** 让系统完成选中状态更新
- 同一文本 **1.2s** 内不重复触发
- 用户关闭面板后，该文本在下次有效拖动前不再触发

### 面板两个模式

`PanelSessionViewModel.PanelMode`：

- `.toolbar` — 320×48pt，复制/翻译/解释/总结
- `.result` — 440×628pt，标题 + 原文区 + AI 对话区 + 操作栏 + 继续提问

面板尺寸由 `FloatingPanelLayout` 统一提供。

`.toolbar` 不主动 activate，`hidesOnDeactivate = false`；`.result` 使用 `activate + makeKeyAndOrderFront`，并设 `hidesOnDeactivate = true`。

### AI Session 与完整历史

一次工具任务开始后，`AiAgentSession` 内部 history 结构为：

```text
system（隐藏）
user: 初始工具 prompt + 原文（隐藏）
assistant: 首次结果（可见）
user: Q1（可见）
assistant: A1（可见）
user: Q2（可见）
assistant: A2（可见）
...
```

`isVisible` 只控制本地 UI 是否渲染，不影响 DeepSeek 请求。DeepSeekService 会把完整 history 的 `role + content` 全部发送给模型。

因此后续追问不再使用旧的：

```text
原文 + 上一轮结果 + 当前问题
```

而是发送真正的完整 conversation history。

### SourceTextCard 与 Chat History 分离

用户划选的原文仍由结果面板的原文区域单独展示，不直接生成一条用户聊天气泡。

模型侧需要原文上下文，因此初始工具 prompt 作为 `isVisible = false` 的 user message 存进 AI history。这样同时满足：

- UI 保持“划词工具”而不是普通聊天窗口
- 模型拥有完整上下文
- 后续多轮请求能够自然携带原文和之前所有 Q/A

### 请求生命周期与 stale result

`AiAgentSession` 持有：

- `currentTask`
- `generation`
- `isLoading`
- `errorMessage`
- retry plan

`clear()`、`cancel()`、开始新的 tool action 都会使旧 Task 失效并递增 generation。

请求完成时必须满足：

```text
Task 未取消
+
request generation == 当前 generation
```

才允许写入 history。

即使底层异步调用没有及时响应 Task cancellation，旧结果也不能污染新的划词 Session。

### 错误与 rollback

错误不再作为：

```text
assistant("网络错误...")
```

写入 conversation history。

现在错误存放在独立 `errorMessage` 状态，由 UI 以 error card 展示。

追问流程：

```text
append user Q
↓
发送完整 history
↓
成功：append assistant A
失败：remove pending user Q
      + errorMessage
      + 保存 retry plan
```

因此错误文本不会：

- 被“复制结果”复制
- 被下一轮当作 assistant 上下文发送
- 污染完整会话历史

### Retry / Regenerate

失败重试与成功后“重新生成”使用不同语义：

- 初次工具请求失败：复用当前隐藏 system/user context
- 追问失败：失败时已回滚 user，retry 时只重新 append 一次该 user message
- 已成功响应后重新生成：删除最后一条 assistant，再用它之前的完整 history 重发

因此 retry 不会产生重复 user history。

在首次 assistant 响应成功之前，Session 不接受 follow-up；初始请求失败时应该先 retry，而不是基于不存在的结果继续追问。

### 提示词职责

`AiPrompts` 负责：

- `systemPrompt(for:)`
- `initialUserPrompt(for:text:)`

后续追问直接作为普通 user message 追加到完整 history，不再由 `DeepSeekService` 拼接特殊 follow-up prompt。

### NSPanel 生命周期

`HaxPickPanel` 由 `ToolbarPanelController` 管理。

显式关闭、ESC、点击面板外部，以及 `.result` 的 `windowDidResignKey` 都最终进入统一 dismiss 流程。

`prepareForDismissal()` 是幂等的，同时调用 `AiAgentSession.cancel()`，保证隐藏面板不会继续接受旧 AI 请求结果。

### Markdown 渲染

AI 可见 assistant message 仍通过 `MarkdownWithCodeBlocks` 渲染。Markdown / 代码高亮当前没有跟随 AI Session 重构一起替换，避免把网络、会话和渲染三类改动混在一个 PR 中。

### API Key 存储

当前仍使用 `UserDefaults`（key: `deepseek_api_key`）。空值会删除持久化记录，避免重启后旧 Key 回弹。

Keychain 迁移属于后续工程质量阶段，不与本次 AI Session 重构混合。

### DeepSeek API

- 端点：`https://api.deepseek.com/chat/completions`
- 模型：`deepseek-v4-flash` / `deepseek-v4-pro`
- 超时：45s
- DeepSeekService 输入：`[AiMessage]`
- DeepSeekService 输出：单次完整 assistant 文本
- 错误处理：优先解析 JSON `error.message`，失败则回退 HTTP body

Streaming / SSE 不在当前架构阶段实现。

## 开发注意事项

- `AppState` 是应用生命周期与顶层编排，不要把 AI history 再放回 AppState
- `PanelSessionViewModel` 不应该重新持有 HTTP Task / generation / conversation history
- `AiAgentSession` 是 AI 会话状态的唯一写入点
- `DeepSeekService` 不应该重新加入 tool action switch、prompt 拼接或“上一轮结果”逻辑
- 不要在 `FloatingToolbarView` 中直接操作 `NSPanel`
- 新增 Sources 文件时必须同时加入 `hax_pick.xcodeproj` Sources build phase；`swift test` 通过并不代表实际 `.app` target 已包含新文件
- `ClipboardSelectionService.simulateCommandC()` 使用 `.cghidEventTap`，不要随意更改
