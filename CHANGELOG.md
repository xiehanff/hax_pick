# Changelog

本文档记录 HaxPick 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

---

## [Unreleased]

### 新增

- **首次启动权限引导页**：未开启辅助功能时，应用启动会自动弹出引导窗口。
- **托盘菜单 UI 重构**：菜单栏面板改为卡片式布局，补强状态摘要、权限引导、API Key 和快捷操作。
- **多模型选择**：菜单栏面板支持在 `deepseek-v4-flash` / `deepseek-v4-pro` 之间切换模型。
- **API Key 可见性切换**：菜单栏 API Key 输入框增加眼睛图标，可在明文/遮盖之间切换。
- **对话气泡 UI**：结果面板改为对话式气泡布局，用户追问右对齐深蓝白字，AI 回复左对齐带图标，多次追问堆叠展示。
- **Markdown + 代码高亮**：`MarkdownWithCodeBlocks` 独立组件，AI 回复按 ` ``` ` 分割渲染，代码块以暗色卡片 + Swift 语法高亮（关键字品红、注释绿、字符串橙、数字浅绿）展示。
- **`SelectionMonitor.stop()`**：提供全局事件监听器清理方法，避免资源泄漏。
- **共享工具层**：`HaxPickPanel`（合并两个 `NSPanel` 子类）、`AppTheme.makeClippedHostingView()`、`NSPoint` 几何扩展。
- **剪贴板兜底单测**：补充文本上下文判定、外部写入保护、marker 等待逻辑，以及 `SelectionMonitor` 对 AX/剪贴板双通道分支的单元测试。

### 变更

- **仓库脱敏**：清空原 Plume 时代 git 历史并重新初始化仓库；提交身份改为 GitHub noreply 邮箱（不暴露真实邮箱）；`.gitignore` 增加 `.DS_Store`。
- **项目更名 Plume → hax_pick**：自 Gitee/ds_tool 复制迁出，Xcode target/product 更名 `hax_pick`，bundle ID 改为 `com.hax.haxpick`，类名 `PlumeApp→HaxPickApp`、`PlumePanel→HaxPickPanel`，SPM 包名 `hax_pick`。
- **品牌图标更换**：`AppIcon.icns` 与菜单栏托盘图标（`MenuBarIcon.png` 32px / `MenuBarIcon@2x.png` 64px）统一更换为新版橙色 "h" 品牌图标，沿用 `hax_pick/` 资源目录与 Copy AppIcon 构建脚本。
- **工具栏焦点策略调整**：划词后的首层工具栏仅悬浮展示，不再主动 `activate` 抢占前台，并在 toolbar 模式保持 `hidesOnDeactivate = false` 避免未激活时被立即收起；进入结果面板时才 `makeKeyAndOrderFront`。
- **浏览器划词兜底恢复**：`AccessibilityTextService` 允许浏览器 Web 内容角色（如 `AXWebArea`）进入剪贴板 fallback，避免浏览器页面文本被误判为“非文本上下文”而不弹工具栏。
- **早期选区快照回退**：`SelectionMonitor` 在 `mouseUp` 当下先抓一份 AX 选区快照，若目标应用自己的划词 toolbar 在后续等待窗口内冲掉选区，可回退到这份早快照继续弹出 HaxPick toolbar。
- **剪贴板兜底收敛**：`SelectionMonitor` 仅在当前焦点元素仍暴露文本相关 AX 属性时才触发模拟 `⌘C`，避免误伤截图和非文本拖拽场景。
- **剪贴板恢复时机优化**：`ClipboardSelectionService` 从固定等待 400ms 改为最多 400ms 的短轮询，读到文本立即恢复；若外部程序已改写剪贴板则不再覆盖。
- **架构拆分**：`PanelSessionViewModel` 和 `MarkdownWithCodeBlocks` 拆为独立源文件，`FloatingToolbarView.swift` 从 ~508 行缩减到 ~281 行。
- **UI 全面扁平化**：去除所有阴影和渐变效果，采用纯色块 + 粗字体 + 底色差异分区的风格。
- **亮色主题强制**：ToolbarPanel 背景从 `.windowBackgroundColor` 改为固定白色，`.colorScheme(.light)` 确保不随系统深色模式变化。
- **Theme.swift 重写**：统一 AppTheme 色盘（hex 值），新增 `PrimaryButtonStyle` / `SecondaryButtonStyle` / `ChipButtonStyle` / `CapsuleToolButton` / `HaxPickPanel` / `makeClippedHostingView` 组件。
- **FloatingToolbarView 重构**：移除系统 GroupBox，改用纯色卡片分区；工具栏去掉「更多」按钮与子菜单，改用平面 4 按钮布局；面板尺寸（工具栏 320×48pt / 结果 436×628pt）；左侧九宫格拖动把手。
- **结果区 Markdown + 对话渲染**：结果通过 `ConversationTurn` 追加式渲染对话气泡，AI 回复支持 Markdown + 代码块高亮，按句号自动分段。
- **提示词优化**：所有 system/user prompt 追加 Markdown 格式指令、代码块标注语言要求、句号换行分段策略。
- **ChipButtonStyle 深色**：推荐问题 chip 改为深蓝底白字 `#3366FF`。
- **原文区优化**：原文区改为 ScrollView + `.lineLimit` 实现展开/收起，修复手动截断不生效的问题。
- **划词检测优化**：通道一 AX API 重试 3→2（80ms），通道二粘贴板等待 200ms→400ms，适配 Xcode 源码编辑器。
- **`Color(hex:)` 可见性**：从 `private` 改为 `internal`，供 `MarkdownWithCodeBlocks` 复用。

### 移除

- **KeychainService**：删除未被调用的 Keychain 存储模块（60 行死代码），API Key 统一使用 UserDefaults 存储。
- **冗余代码**：删除 `AppState.modelName`、`AppTheme.white`/`successSoft`、`FloatingToolbarView.copyFeedback`/`clearCopyFeedback()`、`displayedOriginalText` 手动截断、重复 `NSPanel` 子类等约 80-100 行。

### 文档

- 新增 `assets/app-icon.png`（1024×1024 高清产品图标，提取自 `AppIcon.icns`），供外界引用展示；README 顶部居中展示产品图标。
- 新增 `assets/ARCHITECTURE.md`，承接 `CLAUDE.md`/`AGENTS.md` 中的架构、构建方式、关键机制、开发注意事项，并补充应用图标章节；`CLAUDE.md`/`AGENTS.md` 精简为本地 AI 编码助手指引并退出 git 托管（加入 `.gitignore`）。
- 修正文档中 Xcode scheme 名为 `hax_pick`（原误写为 `HaxPick`）。
- 更新 PRD 文档，与实际代码实现对齐（双通道划词读取、全部 7 个动作、面板精确规格、版本规划重排）
- 更新 README，补充技术架构图、文件职责表、面板规格表、完整使用说明
- 更新 API Key 相关文档，移除"内置默认 Key"的描述，统一为用户自行填写
- 更新 CLAUDE/AGENTS/README/PRD，补充剪贴板兜底仅在文本上下文触发、短轮询恢复和外部写入保护规则
- 更新 CLAUDE.md + AGENTS.md，同步最新架构（文件拆分、面板规格、对话气泡、共享工具层）

---

## [0.2.0] - 2026-06-04

### 新增

- **双通道选中文本读取**：Accessibility API 读取失败时自动回退到模拟 ⌘C 方案，覆盖更多应用场景。
- **剪贴板保存/恢复**：模拟 ⌘C 前完整保存剪贴板内容，读取后恢复，不对用户造成数据丢失。
- **选中文本坐标优化**：引入双候选锚点（原始坐标 + Y 轴翻转坐标），取距离鼠标最近者，并增加合理性校验（距 fallback 点 ≤ 260pt，距松手点 ≤ 320pt）。
- **FloatingToolbarPanel**：自定义 `NSPanel` 子类，覆写 `canBecomeKey` / `canBecomeMain`，确保面板能正确响应键盘事件。

### 变更

- **SelectionMonitor 重构**：`didPerformSelectionDrag` 改为 `selectionDragStartPoint`，返回拖动起始点坐标，为剪贴板兜底方案提供更准确的锚点。
- **面板视图层级优化**：将 SwiftUI 视图包裹在 `clippingView` 中实现圆角裁剪，替代原 `.clipShape()` 方案，配合 `.compositingGroup()` 避免阴影被裁剪。
- **面板尺寸调整**：工具栏高度从 52pt 调整为 60pt。
- **面板定位参数化**：提取 `screenEdgeInset`（12pt）、`toolbarVerticalOffset`（12pt）、`resultVerticalOffset`（8pt）为常量，替代硬编码值。

---

## [0.1.0] - 2026-06-03

### 新增

- **菜单栏入口**：SwiftUI `MenuBarExtra`，展示权限状态、API Key 配置、模型/版本信息、权限引导和退出入口。
- **全局划词监听**：通过 `NSEvent.addGlobalMonitorForEvents` 监听鼠标按下/抬起，以 8pt 拖动距离为阈值判定有效划词。
- **Accessibility API 读取**：通过 `AXUIElement` 读取 `kAXSelectedTextAttribute`，结合 `kAXBoundsForRangeParameterizedAttribute` 获取选中文本及屏幕坐标。
- **划词工具栏**：悬浮 `NSPanel`，横向 5 个胶囊按钮——复制、翻译、解释、总结、更多。
- **更多动作菜单**：下拉菜单包含润色、改写、提取要点。
- **结果悬浮面板**：包含顶部标题区、原文区、结果内容区、底部操作栏、继续提问区。
- **DeepSeek API 集成**：支持 `deepseek-chat` 模型，翻译/解释/总结/润色/改写/提取要点六类动作各有独立 system prompt 和 user prompt。
- **继续追问**：推荐问题 chips（每动作 3 个）+ 自由输入框，复用原文和上一轮结果上下文。
- **复制功能**：复制原文（工具栏 + 面板内）、复制结果（面板底部），均带绿色"已复制"反馈提示。
- **面板关闭**：支持按钮关闭、ESC 键关闭、点击面板外关闭。
- **去重逻辑**：同名文本 1.2 秒内不重复触发；用户通过关闭面板忽略的文本在下次有效拖动前不再触发。
- **原文展开/收起**：超过 140 字符默认折叠，支持点击展开。
- **API Key 管理**：存储于 `UserDefaults`，菜单栏中可编辑；内置默认 Key。
- **Keychain 预留**：`KeychainService` 完整实现 Keychain 读写，待后续接入。
- **错误处理**：API Key 缺失、401/429/5xx 等错误均有可读中文提示，解析 API 返回的 error message。
- **面板边界约束**：面板位置限制在当前屏幕可视区域内，避免被 Dock/Menu Bar 遮挡。
- **应用常驻后台**：`.accessory` 激活策略，无 Dock 图标，仅菜单栏图标常驻。
