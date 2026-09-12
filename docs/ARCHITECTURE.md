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

Xcode 工程无独立测试 target，单元测试由 SPM `HaxPickAppTests` 承载。GitHub Actions 会在 PR 与 `main` push 上运行 `swift test` 和实际 macOS Xcode build；推送 `v*` 标签时构建 Release 版 macOS App，打包为 ZIP 并自动上传到同名 GitHub Release，产物也会作为 Actions artifact 保留 30 天。

## 平台约束

- macOS 13+
- Swift 5.9
- `LSUIElement = true` + `NSApp.setActivationPolicy(.accessory)`，应用没有普通主窗口生命周期

## 架构

```text
HaxPickApp
  └── AppDelegate
       └── AppState（应用生命周期 / 顶层编排）
            ├── UserDefaults（DeepSeek API Key / 模型配置）
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

- `AppState`：权限、设置、本地缓存 credential 编排、SelectionMonitor、Panel Controller、DeepSeekService 实例编排
- `ToolbarPanelController`：NSPanel 创建、定位、聚焦、dismiss
- `PanelSessionViewModel`：toolbar/result 模式、选中文本、输入框、原文展开状态，以及对 `AiAgentSession` 的 UI 投影。重新划词时若当前会话有内容或仍在生成，会话被归档（请求任务后台继续），工具栏气泡图标可重新进入上一个对话（`resumeArchivedConversation`，单归档槽位，划词原文随会话一起归档/恢复）
- `AiAgentSession`：本地完整 AI history、发送前 request window、streaming draft、generation、cancel、stop、retry、rollback
- `AiHistoryWindow`：只塑形发送给模型的 request snapshot，不删除本地 conversation history
- `AiPrompts`：system prompt / 首次工具 prompt
- `AiToolAction`：工具动作与展示 metadata
- `DeepSeekService`：把已经塑形的 `[AiMessage]` 序列化为 DeepSeek 请求并解析 SSE chunk，不负责 conversation 业务规则

## 双通道划词读取

`SelectionMonitor` 同时监听 `leftMouseDown`、`leftMouseDragged` 和 `leftMouseUp`，读取顺序不可颠倒：

1. `mouseDown` 保存拖动起点与当时的焦点元素，避免浮层出现后焦点变化导致丢失目标。
2. 拖动达到阈值后，在 `mouseDragged` 阶段立即读取 Accessibility 选区；若首次尚未形成选区，35ms 后重试。
3. 拖动阶段只读 AX，禁止模拟 ⌘C 干扰未结束的选区手势。AX 成功即可提前显示工具栏；失败则等待鼠标松开后兜底。
4. `mouseUp` 再执行一次 AX 重试与完整 ⌘C 兜底（CGEvent + AppleScript，最多等待 400ms），用于把拖动中显示的局部文本更新为最终选区。

AX 查找不只依赖 focused element，还会检查鼠标当前位置、拖动起点下方的元素及各自父层级，覆盖网页的 `AXWebArea` / `AXStaticText`、编辑器的 `AXTextArea` / `AXTextField`，以及 Chrome、Safari、Edge、Firefox、VS Code、Xcode、JetBrains、Codex 等已知文本应用。异步探测用 drag generation 隔离旧手势，最终读取等待前后也检查 generation，避免旧结果覆盖新手势；模拟复制前检查左键状态，若已开始下一次拖动则跳过。剪贴板兜底不会预写 marker，而是记录复制前的 `changeCount`，仅在复制动作实际写入新内容后读取；被取消或超时且没有写入时不修改原剪贴板，发现外部写入时也不会覆盖。

关键阈值：

- 拖动距离 ≥ 3pt
- 拖动阶段 AX 重试等待 35ms，不执行剪贴板兜底
- mouseUp 后等待 35ms，再进行最终选区校正
- 同一文本 1.2s 内不重复触发
- 关闭面板后的文本在下一次有效拖动前进入 ignored selection

## Panel 模式

`PanelSessionViewModel.PanelMode`：

- `.toolbar`：宽 440pt，高度按按钮字体行高自适应，定位在选区附近
- `.result`：宽度为当前屏幕可用宽度的 36%，限制在 460–560pt；高度为可用区域的 82%，限制在 560–720pt，并在右侧垂直居中

尺寸由 `FloatingPanelLayout` 统一管理。

工具栏宽度保持 440pt；主操作按钮使用较细的 Medium 14pt 字体，白色主体内容区至少 44pt，高度继续由 `FloatingPanelLayout.toolbarTextFont` 的实际字形行高、上下各 10pt 内容内距和上下各 12pt 玻璃内边距计算。工具栏按钮、拖动点阵和恢复入口共用计算出的内容高度，因此调整按钮字体时，窗口白色内容层会同步增高。

结果面板边缘缩放采用单轴规则：左右边缘只修改宽度，上下边缘只修改高度，四角不再同时修改两个尺寸。每个拖拽事件只提交一个整数化窗口 frame，避免窗口 frame、玻璃内容约束和对话布局在同一帧互相争抢造成闪烁。

设置页的“重置权限”会清理当前应用的 Accessibility TCC 记录，然后只调用 `AXIsProcessTrustedWithOptions` 触发系统辅助功能授权询问；它不会自动打开“系统设置 > 辅助功能”页面。需要手动进入设置时，使用独立的“打开设置”按钮。

`.toolbar` 不主动 activate，鼠标左键仍按下时使用 `ignoresMouseEvents` 穿透，监听 `leftMouseUp` 恢复点击（即使最终文本相同未重复发布）；点击面板外会关闭；`.result` 使用 `activate + makeKeyAndOrderFront`，固定在当前屏幕右侧且保持 `hidesOnDeactivate = false`，点击侧栏外不会关闭。两种模式都可通过 ESC 关闭。

## Liquid Glass 兼容层

`HaxGlassSurface` 承载结果侧栏和托盘菜单的玻璃外壳；工具栏与两者使用同一套玻璃视觉：

- 使用 Xcode 26 / Swift 6.2 构建且运行在 macOS 26+ 时，采用 SwiftUI 原生 `glassEffect`。
- 使用旧版 SDK 或运行在 macOS 13–15 时，结果侧栏和菜单栏回退到 `.underWindowBackground` 的 `NSVisualEffectView`，让桌面色彩透过白色磨砂层，并保留降低透明度适配。
- 结果侧栏使用 12pt 宽玻璃留边，菜单栏面板使用 8pt 留边；外缘由外侧高光和内侧暗边组成同心倒角，表现玻璃厚度。
- 浅色玻璃外缘只叠加 4% 白色，内容层叠加 72% 白色；外缘比主题背景更透明，主题背景仍能轻微透出桌面色彩。
- 结果侧栏和托盘菜单外壳由 SwiftUI 连续圆角的独立合成层裁切，窗口阴影交由 `NSPanel` 绘制，避免透明窗口边界裁断阴影后产生圆角锯齿。
- 托盘回归系统样式：`MenuBarExtra(.menu)` 仅含「设置…」「退出」；设置项（辅助功能权限、模型、DeepSeek API Key、版本号）在系统样式的 `Window`（grouped Form）中配置，不使用自定义玻璃视觉。
- 工具栏与结果侧栏共用同一套玻璃视觉：`HaxGlassSurface(style: .light)` 玻璃外壳（Capsule 全圆角）+ `AppTheme.panelContent`（72% 白色微透明）内容层 + 0.78 白色 0.75pt 内描边，随结果侧栏的玻璃改版同步演进。左侧拖动点阵为黑色，复制、翻译、解释和深度理解均显示黑色文字。
- 对话窗头部、内容区与输入区之间不使用横向分割线，仅通过留白和输入卡片边界区分层级。
- 长文本内容区使用白色磨砂微透明背景；继续提问输入框保持更高不透明度，避免输入控件丢失边界和对比度。

项目是原生 SwiftUI / AppKit 应用，Flutter 的 `liquid_glass_widgets` 无法直接作为 Swift Package 接入；结果侧栏、菜单栏和工具栏统一使用系统玻璃兼容层，前景文字由 SwiftUI 绘制。

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

按工具动作控制推理：

- 翻译：`thinking.type = "disabled"`，避免短文本翻译进入深度思考。
- 解释：`thinking.type = "enabled"` 且 `reasoning_effort = "low"`。
- 其他动作：保持服务默认策略。

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

测试使用的完整响应注入器由 `AiAgentSession(complete:)` 提供；生产 `DeepSeekService` 只保留流式接口，避免维护没有运行时调用方的聚合 helper。

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
正在 streaming / 已完成
  ↓
MarkdownWithCodeBlocks（Down / cmark 渲染）
  ↓ 流式期间持续增量解析：latest-wins，只有最新快照会应用，
    同一个库文本视图原地更新，不重建视图
```

`AiAgentSession.streamingAssistantID` 只有在当前请求已经真正收到 partial content 时才有值。因此 regenerate 刚开始、尚未收到新 chunk 时，旧 assistant 仍保持已提交 Markdown；不会因为单纯 `isLoading == true` 就发生视觉降级。

40ms draft publish 复用同一个 Markdown 渲染视图；解析为 latest-wins，过快到达的快照会被合并，正文先以纯文本回退显示、解析完成后原地替换为格式化结果。更新 `NSTextStorage` 时保留完整且未变的段落，只替换当前可能被后续 Markdown 定界符改写的段落及其后缀，避免每个快照使整篇 glyph/layout 缓存失效。Markdown 库为 Down（cmark 0.29，CommonMark 合规；以本地包 `LocalPackages/Down` 引入，本地修补了 `DownLayoutManager` 的代码块背景绘制：纯黑背景、整块 6pt 圆角卡片、两侧 8pt 留边，经 `HaxMarkdownStyler`（`DownStyler` 子类）定制字体与配色，经 `DownTextView` / `DownLayoutManager` 绘制代码块背景与引用条）；行内代码为紫色高亮文字，代码块语法高亮由 Splash 叠加（覆写 `style(codeBlock:)`，仅着色不改文本）；此前使用的 CDMarkdownKit 因 inline-code 对中英文相邻场景的解析缺陷已移除。

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

`ResultPanelView` 使用原生 `ConversationScrollView` / `ConversationDocumentView` 和轻量 `ChatFollowTailState` 管理位置：

- 默认 / 新请求开始跟尾；用户离开底部超过 1pt 即暂停，显示「回到最新」，不再以 32pt 的“接近底部”阈值提前吸附。
- `scrollWheel` 在交给 AppKit 前取得用户滚动控制权；同步监听 `willStartLiveScroll` / `didLiveScroll` / `didEndLiveScroll` 覆盖触控板、滚动条拖动和普通滚轮。在手势及惯性期间，流式内容继续渲染，但程序不得强制跟尾。
- 手势结束后等待 120ms 静默间隔（main run loop common modes），桥接抬指与惯性开始以及普通滚轮事件间隙。根据最后一次用户滚动是否真的到达底部决定恢复跟尾；流式增长自身不改变此决定。
- clip bounds 通知必须同步处理，禁止再包装为异步 Task。文档布局 / 程序定位期间的通知被就地过滤，避免延迟执行时失去来源标记、将程序滚动当成用户输入。
- 对话滚动视图显式禁用 responsive scrolling，让滚动与流式文档尺寸更新使用同一主线程几何状态；Markdown 文本视图关闭 TextKit 自行纵向 resize，高度由 intrinsic size + Auto Layout 单一控制。

follow-tail 状态只属于 View 层，不进入 `PanelSessionViewModel` / `AiAgentSession`；流式快照不因用户离开尾部而暂停 UI 转发，避免再次到底时一次性补齐。AppKit 回归测试在窗口托管的视图中覆盖正式输出、展开思考、反复到达两端、惯性衔接和普通滚轮，并记录每次 bounds 通知，而不仅检查最终位置；这些自动化检查不替代真实触控板的视觉验收。

流式 Markdown 应用后会同步重新测量 conversation document，并在同一次禁用隐式动画的 Core Animation 事务中同时提交 document 高度与尾部 offset。不得将这条路径延迟到下一轮 main queue，否则会暴露“新文本 + 旧文档高度”的裁剪中间帧。

正式回答代码块背景为不透明 `#000000`。深度理解的 0.78 淡化只设置在正文前景色，Markdown 视图及祖先保持 alpha = 1，不可整层降低透明度（否则黑底会与浅色阅读层混成灰色）。

## NSPanel 生命周期

显式关闭和 ESC 始终进入统一 dismiss 流程。点击面板外部只在 `.toolbar` 模式触发 dismiss；`.result` 模式保持右侧常驻，不再通过 `windowDidResignKey` 自动关闭。

`prepareForDismissal()` 是幂等的，并调用 `AiAgentSession.cancel()`。关闭面板时当前 streaming draft 会按取消语义 rollback，不会在隐藏 Session 中继续写入。

## API Key / 本地缓存

DeepSeek API Key 使用 `UserDefaults` 键 `deepseek_api_key` 持久化。启动时读取有效的 `sk-` 值；设置页保存时校验后写入本地缓存，清空时删除该键。运行时 `AppState.apiKey` 是请求唯一读取入口。

设置页使用无标题栏玻璃窗口；由于 borderless `NSWindow` 默认不能成为 key window，必须由 `SettingsWindow` 显式允许 `canBecomeKey` / `canBecomeMain`，并在窗口成为 key 后再让 API Key 字段成为 first responder。API Key 字段自身也在鼠标按下时确保窗口和 field editor 获得焦点，并保留 ⌘V 的 responder fallback；视觉上使用圆角浅色输入卡片、内边距和独立占位符字体。

本地缓存写入不调用 Keychain，不触发系统密码验证，也不存在 Keychain 迁移、故障恢复或重试状态。`apiKeyStorageState` 只表示 `.local` 或 `.empty`。

## DeepSeek API

- 端点：`https://api.deepseek.com/chat/completions`
- 模型：`deepseek-v4-flash` / `deepseek-v4-flash-vision-exp` / `deepseek-v4-pro`
- timeout：45s
- 输入：经过 `AiHistoryWindow` 塑形后的 `[AiMessage]`
- 动作推理策略：翻译关闭 thinking，解释使用 low reasoning effort
- 主输出：`AsyncThrowingStream<String, Error>`
- SSE 正常结束：必须收到 `[DONE]`
- `[DONE]` 前 EOF：`incompleteStream`，不得提交 partial history
- SSE keep-alive comment / 空行：忽略
- 非 2xx：优先解析 JSON `error.message`，失败则回退 HTTP body

## 开发注意事项

- `AppState` 只负责应用级编排，不要把 AI history 放回 AppState
- API Key 主存储保持在 UserDefaults 的 `deepseek_api_key` 本地缓存
- API Key 编辑保持 local draft → 格式校验 → 本地写入 → runtime commit 的顺序
- `PanelSessionViewModel` 不持有 HTTP Task / generation / conversation history，也不负责 history window
- `AiAgentSession` 是 AI 会话状态唯一写入点，并负责生产 service 请求的 history window
- `AiHistoryWindow` 只裁 request snapshot，不得删除或改写 `AiAgentSession.messages`
- request window 必须保留 hidden anchors 和最新 dependency unit；不要把当前 follow-up 与直接依赖的上一轮回答拆开
- `DeepSeekService` 不重新加入 prompt、history window 或 retry 业务逻辑
- Streaming chunk 可以高频到达，但 UI draft 发布必须继续节流
- Markdown 渲染统一走 Down（cmark）；流式与完成态共用同一个库文本视图原地更新，不得自写 Markdown parser
- partial 可见不等于 request completed；后续发送必须检查 `isLoading`
- Chat Completions stream 只有收到 `[DONE]` 才能 commit assistant
- Regenerate 必须保持事务式
- follow-tail 是 View 层交互状态；用户手动查看旧内容后不得被 streaming 强制拉回底部
- 不要在 SwiftUI View 中直接操作 NSPanel
- 新增 Sources 文件必须同步加入 `hax_pick.xcodeproj` Sources build phase
- `ClipboardSelectionService.simulateCommandC()` 使用 `.cghidEventTap`，不要随意更改
