# HaxPick 架构文档

本文档描述 HaxPick 的项目结构、构建方式与关键实现机制。AI 编码助手指引见仓库根目录 `CLAUDE.md` / `AGENTS.md`（本地文件，不入库）。

## 项目概述

HaxPick 是一个 macOS 菜单栏划词助手。用户划词后弹出悬浮工具栏，通过 DeepSeek API 执行翻译或解释。

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
            │         └── AiAgentSession（AI history / request window / streaming / retry / stop）
            │              ├── AiMessage / AiHistoryWindow
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
- `AiAgentSession`：本地完整 AI history、发送前 request window、streaming draft、generation、cancel、stop、retry、rollback
- `AiHistoryWindow`：只塑形发送给模型的 request snapshot，不删除本地 conversation history
- `AiPrompts`：system prompt / 首次工具 prompt
- `AiToolAction`：工具动作与展示 metadata
- `DeepSeekService`：把已经塑形的 `[AiMessage]` 序列化为 DeepSeek 请求并解析 SSE chunk，不负责 conversation 业务规则

## 双通道划词读取

`SelectionMonitor` 同时监听 `leftMouseDown`、`leftMouseDragged` 和 `leftMouseUp`，读取顺序不可颠倒：

1. `mouseDown` 保存拖动起点与当时的焦点元素，避免浮层出现后焦点变化导致丢失目标。
2. 拖动达到阈值后，在 `mouseDragged` 阶段立即读取 Accessibility 选区；若首次尚未形成选区，35ms 后重试。
3. 拖动阶段的 AX 通道仍失败时，浏览器、IDE、Codex 或文本控件进入快速 ⌘C 兜底：只使用 CGEvent，最多等待 160ms。读到第一个词即可在鼠标仍按下时显示工具栏。
4. `mouseUp` 再执行一次 AX 重试与完整 ⌘C 兜底（CGEvent + AppleScript，最多等待 400ms），用于把拖动中显示的局部文本更新为最终选区。

AX 查找不只依赖 focused element，还会检查鼠标当前位置、拖动起点下方的元素及各自父层级，覆盖网页的 `AXWebArea` / `AXStaticText`、编辑器的 `AXTextArea` / `AXTextField`，以及 Chrome、Safari、Edge、Firefox、VS Code、Xcode、JetBrains、Codex 等已知文本应用。异步探测用 drag generation 隔离旧手势；被取消或超时的剪贴板探测会恢复原剪贴板内容。

关键阈值：

- 拖动距离 ≥ 3pt
- 拖动阶段 AX 重试等待 35ms，快速剪贴板兜底上限 160ms
- mouseUp 后等待 35ms，再进行最终选区校正
- 同一文本 1.2s 内不重复触发
- 关闭面板后的文本在下一次有效拖动前进入 ignored selection

## Panel 模式

`PanelSessionViewModel.PanelMode`：

- `.toolbar`：378×48pt，定位在选区附近
- `.result`：宽度为当前屏幕可用宽度的 36%，限制在 460–560pt；高度为可用区域的 82%，限制在 560–720pt，并在右侧垂直居中

尺寸由 `FloatingPanelLayout` 统一管理。

`.toolbar` 不主动 activate，点击面板外会关闭；`.result` 使用 `activate + makeKeyAndOrderFront`，固定在当前屏幕右侧且保持 `hidesOnDeactivate = false`，点击侧栏外不会关闭。两种模式都可通过 ESC 关闭。

## Liquid Glass 兼容层

`HaxGlassSurface` 统一承载工具栏、结果侧栏和菜单栏面板的玻璃外壳：

- 使用 Xcode 26 / Swift 6.2 构建且运行在 macOS 26+ 时，采用 SwiftUI 原生 `glassEffect`。
- 使用旧版 SDK 或运行在 macOS 13–15 时，回退到 `.underWindowBackground` 的 `NSVisualEffectView`，让桌面色彩透过白色磨砂层，并保留降低透明度适配。
- 结果侧栏使用 12pt 宽玻璃留边，菜单栏面板使用 8pt 留边；外缘由外侧高光和内侧暗边组成同心倒角，表现玻璃厚度。
- 浅色玻璃外缘只叠加 4% 白色，内容层叠加 72% 白色；外缘比主题背景更透明，主题背景仍能轻微透出桌面色彩。
- 外壳由 SwiftUI 连续圆角的独立合成层裁切，窗口阴影交由 `NSPanel` 绘制，避免透明窗口边界裁断阴影后产生圆角锯齿。
- 分区线使用带水平内边距的 0.5pt 弱分隔线，不与玻璃或内容层边缘相接。
- 长文本内容区使用白色磨砂微透明背景；继续提问输入框保持更高不透明度，避免输入控件丢失边界和对比度。

项目是原生 SwiftUI / AppKit 应用，Flutter 的 `liquid_glass_widgets` 无法直接作为 Swift Package 接入；UI 按其“玻璃用于悬浮控制层、内容保持不透明”的原则使用系统原生能力实现。

## AI Session、本地完整历史与请求窗口

一次工具任务的本地模型历史：

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

`AiMessage.isVisible` 只决定本地 UI 是否渲染。`AiAgentSession.messages` 始终保留当前 Session 的完整 history，因此 UI、Retry、Regenerate 都不会因为 request window 而丢本地消息。

真正发送给 DeepSeek 前，`AiAgentSession(service:historyWindow:)` 会通过 `AiHistoryWindow` 生成一个 request snapshot。默认策略为：

```text
本地完整 history
  ↓
AiHistoryWindow.standard
  ↓
48,000 content characters 的 app-level soft budget
  ↓
DeepSeekService.stream(...)
```

这里刻意使用“字符预算”，不是伪装成精确 tokenizer token 数。

窗口规则：

- hidden system 永远保留；
- 初始 hidden user/tool prompt + 原文永远保留；
- 当前最新 dependency unit 永远保留；
- pending follow-up 会与它直接依赖的上一轮 exchange 一起保留，例如 `Q1 → A1 → Q2` 不可拆开；
- 更早的 user/assistant exchange 从新到旧按完整 unit 加入；
- 一旦下一个更旧 unit 超过 soft budget 就停止，不跳过中间 turn 去捡更老消息；
- 不截断单条 message；如果 anchors 或最新 dependency unit 自身已经超过预算，允许软超限，而不是静默截断原文或当前问题。

因此模型看到的是“原始任务上下文 + 连续的最近依赖上下文”，而本地用户仍能看到完整历史。

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

成功后原位替换 A1；失败则保留 A1 + error；Retry 继续使用同一个 pre-regenerate snapshot。真正进入 transport 时仍会应用同一个 `AiHistoryWindow`，所以同一 retry snapshot 的窗口塑形是确定性的。

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

默认跟尾流程：

```text
ScrollViewReader
  ↓
tail anchor
  ↓
message / streamed content / error / loading 状态变化
  ↓
scrollTo(tail, anchor: .bottom)
```

但 `ResultPanelView` 现在同时维护轻量 `ChatFollowTailState`：

```text
默认 / 新请求开始
  ↓
isFollowingTail = true

用户在结果区滚轮 / 触控板滚动 / 拖动交互
  ↓
isFollowingTail = false
  ↓
后续 streaming publish 不再 scrollTo
  ↓
显示「回到最新」

点击「回到最新」
  ↓
恢复跟尾并立即到底部
```

程序化 `scrollTo` 不会触发 AppKit 用户事件 monitor，因此不会把自己误判成“用户手动滚动”。follow-tail 状态只属于 View 层，不进入 `AiAgentSession`。

## NSPanel 生命周期

显式关闭和 ESC 始终进入统一 dismiss 流程。点击面板外部只在 `.toolbar` 模式触发 dismiss；`.result` 模式保持右侧常驻，不再通过 `windowDidResignKey` 自动关闭。

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

Keychain read 失败
  ↓
legacy 只允许本次 fallback read
  ↓
禁止把 legacy 反向写回未知状态的 Keychain
```

用户主动编辑使用事务式提交，不直接绑定运行时 credential：

```text
UI local draft
  ↓ 点击保存
格式校验（空值 = clear；非空必须符合 sk- 规则）
  ↓
Keychain save / delete
  ├─ 成功 → commit AppState.apiKey
  └─ 失败 → runtime 继续保持上一个成功值 + UI 显示错误
```

因此保存失败不会出现 `runtime = new / Keychain = old`，清空失败也不会出现 `runtime = empty / Keychain = old`。用户主动编辑时 legacy plaintext 会退休，不允许旧 UserDefaults Key 在重启后回弹。

## DeepSeek API

- 端点：`https://api.deepseek.com/chat/completions`
- 模型：`deepseek-v4-flash` / `deepseek-v4-pro`
- timeout：45s
- 输入：经过 `AiHistoryWindow` 塑形后的 `[AiMessage]`
- 主输出：`AsyncThrowingStream<String, Error>`
- SSE 正常结束：必须收到 `[DONE]`
- `[DONE]` 前 EOF：`incompleteStream`，不得提交 partial history
- SSE keep-alive comment / 空行：忽略
- 非 2xx：优先解析 JSON `error.message`，失败则回退 HTTP body

## 开发注意事项

- `AppState` 只负责应用级编排，不要把 AI history 放回 AppState
- API Key 主存储必须保持在 Keychain；不要重新把新 Key 写入 UserDefaults
- legacy `deepseek_api_key` 仅允许用于升级迁移 fallback；Keychain read failure 时禁止 legacy write-back
- API Key 编辑必须保持 local draft → persistence success → runtime commit 的事务顺序
- `PanelSessionViewModel` 不持有 HTTP Task / generation / conversation history，也不负责 history window
- `AiAgentSession` 是 AI 会话状态唯一写入点，并负责生产 service 请求的 history window
- `AiHistoryWindow` 只裁 request snapshot，不得删除或改写 `AiAgentSession.messages`
- request window 必须保留 hidden anchors 和最新 dependency unit；不要把当前 follow-up 与直接依赖的上一轮回答拆开
- `DeepSeekService` 不重新加入 prompt、history window 或 retry 业务逻辑
- Streaming chunk 可以高频到达，但 UI draft 发布必须继续节流
- active streaming assistant 用轻量 Text；完成后再恢复 Markdown/code highlighting
- partial 可见不等于 request completed；后续发送必须检查 `isLoading`
- Chat Completions stream 只有收到 `[DONE]` 才能 commit assistant
- Regenerate 必须保持事务式
- follow-tail 是 View 层交互状态；用户手动查看旧内容后不得被 streaming 强制拉回底部
- 不要在 SwiftUI View 中直接操作 NSPanel
- 新增 Sources 文件必须同步加入 `hax_pick.xcodeproj` Sources build phase
- `ClipboardSelectionService.simulateCommandC()` 使用 `.cghidEventTap`，不要随意更改
