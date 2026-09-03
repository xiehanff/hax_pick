# HaxPick 架构文档

本文档描述 HaxPick 的项目结构、构建方式与关键实现机制。AI 编码助手指引见仓库根目录 `CLAUDE.md` / `AGENTS.md`（本地文件，不入库）。

## 项目概述

HaxPick 是一个 macOS 菜单栏划词助手。用户划词后弹出悬浮工具栏，通过 DeepSeek API 执行翻译/解释/总结/润色/改写/提取要点。

## 构建与运行

```bash
xcodebuild -project hax_pick.xcodeproj -scheme hax_pick -configuration Debug build
open hax_pick.xcodeproj
swift build
swift test
```

Xcode 工程无独立测试 target，单元测试由 SPM `HaxPickAppTests` 承载。GitHub Actions 会在 PR 与 `main` push 上运行 `swift test` 和实际 macOS Xcode build。

## 平台约束

- macOS 13+
- Swift 5.9
- `LSUIElement = true` + `NSApp.setActivationPolicy(.accessory)`，应用没有普通主窗口生命周期

## 架构

```text
HaxPickApp
  └── AppDelegate
       └── AppState（应用生命周期 / 顶层编排）
            ├── KeychainAPIKeyStore（DeepSeek API Key）
            ├── SelectionMonitor
            │    ├── AccessibilityTextService
            │    └── ClipboardSelectionService
            ├── PermissionGuideWindowController
            ├── ToolbarPanelController（NSPanel 生命周期）
            │    └── PanelSessionViewModel（Panel / UI 状态投影）
            │         └── AiAgentSession（AI history / streaming / retry / stop）
            │              ├── AiMessage
            │              ├── AiToolAction
            │              ├── AiPrompts
            │              └── DeepSeekService（SSE transport / DTO / error mapping）
            │
            │    SwiftUI
            │    ├── FloatingToolbarView（shell / 紧凑工具栏）
            │    └── ResultPanelView
            │         ├── AiMessageBubble
            │         └── AiChatInputBar
            └── MenuBarContentView
```

职责边界：

- `AppState`：权限、设置、Keychain credential 编排、SelectionMonitor、Panel Controller、DeepSeekService 实例编排
- `KeychainAPIKeyStore`：DeepSeek API Key 的 Generic Password 读写，不负责 UI 或迁移策略
- `ToolbarPanelController`：NSPanel 创建、定位、聚焦、dismiss
- `PanelSessionViewModel`：toolbar/result 模式、选中文本、输入框、原文展开状态，以及对 `AiAgentSession` 的 UI 投影
- `AiAgentSession`：AI history、streaming draft、generation、cancel、stop、retry、rollback
- `AiPrompts`：system prompt / 首次工具 prompt
- `AiToolAction`：工具动作与展示 metadata
- `DeepSeekService`：把 `[AiMessage]` 序列化为 DeepSeek 请求并解析 SSE chunk，不负责 conversation 业务规则

## 双通道划词读取

`SelectionMonitor.handleMouseUp()` 的读取顺序不可颠倒：

1. Accessibility API：先抓早期 AX 选区快照，再等待系统完成选区更新并重试。
2. ⌘C 兜底：仅在 AX 通道失败且目标表现为文本区域时执行，同时保护用户原剪贴板内容。

关键阈值：

- 拖动距离 ≥ 8pt
- mouseUp 后等待 150ms
- 同一文本 1.2s 内不重复触发
- 关闭面板后的文本在下一次有效拖动前进入 ignored selection

## Panel 模式

`PanelSessionViewModel.PanelMode`：

- `.toolbar`：320×48pt
- `.result`：440×628pt

尺寸由 `FloatingPanelLayout` 统一管理。

`.toolbar` 不主动 activate，`hidesOnDeactivate = false`；`.result` 使用 `activate + makeKeyAndOrderFront`，并设置 `hidesOnDeactivate = true`。

## AI Session 与完整历史

一次工具任务的模型历史：

```text
system（隐藏）
user: 初始工具 prompt + 原文（隐藏）
assistant: A0
user: Q1
assistant: A1
user: Q2
assistant: A2
...
```

`AiMessage.isVisible` 只决定本地 UI 是否渲染，不影响发送给模型的上下文。后续追问始终发送完整 history，不再只拼“原文 + 上一轮结果 + 当前问题”。

原文仍由结果面板的原文区域独立展示，因此模型能看到原文，但 UI 不会制造一个巨大的初始 user bubble。

## Streaming / SSE

DeepSeek 请求启用：

```json
{
  "stream": true
}
```

`DeepSeekService` 使用 `URLSession.AsyncBytes` 读取响应，并把 SSE：

```text
data: {"choices":[{"delta":{"content":"你"}}]}
data: {"choices":[{"delta":{"content":"好"}}]}
data: [DONE]
```

转换成：

```text
AsyncThrowingStream<String, Error>
  ├── "你"
  └── "好"
```

网络层只负责 transport / SSE / HTTP error mapping，不直接更新 SwiftUI 状态。

DeepSeek 在长时间等待期间可能发送 SSE keep-alive comment（例如 `: keep-alive`）或空行；这些行必须忽略，不能当 JSON payload 解析。

正常的 Chat Completions 流必须显式收到：

```text
data: [DONE]
```

才能被视为完整成功。即使此前已经收到可展示的 `content`，如果 HTTP body 在 `[DONE]` 之前直接 EOF，也必须按 `incompleteStream` 失败处理，让 `AiAgentSession` 走 rollback / Retry；不能把被截断的 partial assistant 当成完整历史提交。

`complete(messages:)` 仍保留为聚合 helper：内部消费相同 stream，最终返回完整字符串，主要用于兼容测试和非流式调用点。

## Streaming draft、UI 节流与渲染阶段

`AiAgentSession` 消费所有网络 chunk，但不会每收到一个 token 就触发 `@Published messages` 更新。

默认发布间隔约为：

```text
40ms ≈ 25 FPS
```

流程：

```text
SSE chunk
  ↓ 每个 chunk 都立即累计到 activeDraftContent
内存中的完整 draft
  ↓ 约每 40ms 发布一次
AiMessage.content
```

Streaming 阶段和已完成阶段采用不同渲染策略：

```text
正在 streaming
  ↓
轻量 Text
  ↓ 不运行完整 Markdown / 正则拆段 / 代码高亮

收到 [DONE] / Stop 接受 partial
  ↓
streamingAssistantID 清除
  ↓
MarkdownWithCodeBlocks
```

`AiAgentSession.streamingAssistantID` 只有在当前请求已经真正收到 partial content 时才有值。因此 regenerate 刚开始、尚未收到新 chunk 时，旧 assistant 仍保持已提交 Markdown；不会因为单纯 `isLoading == true` 就发生视觉降级。

这样 40ms draft publish 不再重复执行整套 Markdown 与代码高亮解析，同时完整结果仍保留原有格式化能力。

请求结束时无论是否刚好命中节流窗口，都会执行最终 flush。

重要状态语义：

> partial assistant 已经可见，不代表请求已经结束。

能否继续追问仍由 `isLoading == false` 决定。

## Stop generation

结果面板在请求中显示“停止生成”。

### 已经收到部分内容

```text
A0 / Q1
  ↓
stream partial assistant
  ↓
Stop
  ↓
保留当前 partial assistant
isLoading = false
didStop = true
```

这条 partial 作为用户主动接受的当前结果保留，可以复制、继续追问，也可以通过“重新生成”再次生成。Stop 后它不再属于 active streaming draft，因此恢复 Markdown 渲染。

### 首 chunk 前停止

```text
开始请求
  ↓
尚未收到任何内容
  ↓
Stop
  ↓
删除空 draft
追问场景同时 rollback pending user
保存 retry plan
```

因此不会留下空 assistant 或未回答 user turn，同时仍允许用户 Retry。

### Regenerate 中停止

Regenerate 延续事务式语义：请求期间旧 assistant 仍是已提交结果；如果收到 partial 后 Stop，则 partial 成为新的当前 assistant；若首 chunk 前 Stop，则原 assistant 保持不变并保留 Retry 计划。

## Retry / Regenerate

失败重试：

- 初次请求失败：复用隐藏 system/user context
- follow-up 失败：rollback pending user，Retry 时只追加一次该 user
- regenerate：模型请求使用“不包含旧 assistant”的 snapshot

Regenerate 始终保持事务式：

```text
已提交：... Q1 → A1
             │
             ├── UI 保留 A1
             └── 模型请求：... Q1
```

成功后原位替换 A1；失败则保留 A1 + error；Retry 继续使用同一个 pre-regenerate snapshot。

## Error / stale request rollback

错误通过独立 `errorMessage` 展示，不写入 assistant history。

Streaming 请求即使已经展示过 partial，只要 transport 最终失败（包括 `[DONE]` 前提前 EOF），仍会 rollback 当前 draft；follow-up 场景同时 rollback pending user，并保留 Retry plan。这样半截回答不会进入后续模型 history。

`AiAgentSession` 使用 `generation + Task.cancel()` 双保险。`clear()`、dismiss、开始新 tool action 都会使旧请求 generation 失效，因此底层网络即使晚到，也不能写入新 Session。

## Chat UI 与 follow-tail

`FloatingToolbarView` 只保留 shell 与紧凑 toolbar。结果页拆分为：

```text
ResultPanelView
├── source text
├── conversation
│   └── AiMessageBubble
├── Stop / Retry / Copy
└── AiChatInputBar
```

Conversation 使用：

```text
ScrollViewReader
  ↓
tail anchor
  ↓
message / streamed content / error / loading 状态变化
  ↓
scrollTo(tail, anchor: .bottom)
```

因此每次经过节流后的 draft 发布都会跟到最新内容。

当前版本采用“始终跟尾”策略；用户主动向上滚动后自动解除 follow-tail 属于后续增强，不在本阶段引入额外滚动状态机。

## NSPanel 生命周期

显式关闭、ESC、点击面板外部以及 `.result` 的 `windowDidResignKey` 最终都进入统一 dismiss 流程。

`prepareForDismissal()` 是幂等的，并调用 `AiAgentSession.cancel()`。关闭面板时当前 streaming draft 会按取消语义 rollback，不会在隐藏 Session 中继续写入。

## API Key / Keychain

DeepSeek API Key 的主持久化存储已经迁移到 macOS Keychain，使用 Generic Password item：

```text
service: com.hax.haxpick.deepseek-api-key
account: deepseek-api-key
accessible: when unlocked, this device only
```

新的 API Key 不再写入 UserDefaults。

为了兼容升级前版本，`deepseek_api_key` UserDefaults 只作为一次性 legacy migration 来源：

```text
启动
  ↓
Keychain 有有效 Key
  ├─ 使用 Keychain
  └─ 删除 legacy UserDefaults 明文

Keychain 没有 Key + legacy 有有效 Key
  ↓
尝试写入 Keychain
  ├─ 成功 → 删除 legacy 明文
  └─ 失败 → 暂时保留 legacy，避免升级后静默丢失唯一凭证
```

Keychain 读取失败时同样不会主动删除 legacy fallback，迁移可在后续启动重试。

但“用户主动编辑/清空”和“升级迁移”语义不同：一旦用户主动修改 API Key，旧 legacy UserDefaults 会立即删除，即使新的 Keychain 操作失败，也不能让旧 Key 在下次启动时回弹。保存失败会通过 `apiKeyStorageError` 在菜单栏设置中明确提示用户重试。

用户主动清空时也会先删除 legacy 明文，再删除 Keychain item；如果 Keychain 删除失败，UI 会提示错误，而不会静默声称已持久化成功。

## DeepSeek API

- 端点：`https://api.deepseek.com/chat/completions`
- 模型：`deepseek-v4-flash` / `deepseek-v4-pro`
- timeout：45s
- 输入：`[AiMessage]`
- 主输出：`AsyncThrowingStream<String, Error>`
- SSE 正常结束：必须收到 `[DONE]`
- `[DONE]` 前 EOF：`incompleteStream`，不得提交 partial history
- SSE keep-alive comment / 空行：忽略
- 非 2xx：优先解析 JSON `error.message`，失败则回退 HTTP body

## 开发注意事项

- `AppState` 只负责应用级编排，不要把 AI history 放回 AppState
- API Key 主存储必须保持在 Keychain；不要重新把新 Key 写入 UserDefaults
- legacy `deepseek_api_key` 仅允许用于升级迁移 fallback
- `PanelSessionViewModel` 不持有 HTTP Task / generation / conversation history
- `AiAgentSession` 是 AI 会话状态唯一写入点
- `DeepSeekService` 不重新加入 prompt 或 retry 业务逻辑
- Streaming chunk 可以高频到达，但 UI draft 发布必须继续节流
- active streaming assistant 用轻量 Text；完成后再恢复 Markdown/code highlighting
- partial 可见不等于 request completed；后续发送必须检查 `isLoading`
- Chat Completions stream 只有收到 `[DONE]` 才能 commit assistant
- Regenerate 必须保持事务式
- 不要在 SwiftUI View 中直接操作 NSPanel
- 新增 Sources 文件必须同步加入 `hax_pick.xcodeproj` Sources build phase
- `ClipboardSelectionService.simulateCommandC()` 使用 `.cghidEventTap`，不要随意更改
