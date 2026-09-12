# Changelog

本文档记录 HaxPick 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

---

## [Unreleased]

### 修复
- **TUI 划词剪贴板污染**:剪贴板兜底不再先写入随机 marker；改为通过复制前后的 `changeCount` 判断模拟 ⌘C 是否成功，避免不响应复制快捷键的 agent TUI 将 `hax_pick_xxxxx` 一类 marker 留在系统剪贴板中。
- **CI 构建产物**:CI 构建完成后自动打包并上传可下载的 macOS `.app` 压缩包，保留 7 天。
- **设置页 API Key 输入**:允许无标题栏设置窗口成为 key window，确保 API Key 输入框可以点击获得焦点并使用 ⌘V 粘贴；输入框改为 24pt 高、带内边距的圆角浅色卡片样式，区分占位符与 Key 文本字体，文本垂直居中且占位符字号为 11pt。
- **模型选项**:设置页新增 `deepseek-v4-flash-vision-exp` 模型。
- **B 类死代码清理**:移除仅用于旧测试计数的 `draftRevision`、已删除原文区对应的 `showsSourceTurn`/`isOriginalExpanded`，以及生产无调用的 `DeepSeekService.complete(messages:)` 聚合接口；保留流式/完整响应测试注入器、Panel 会话工厂和 `SelectionMonitor.stop()` 生命周期接口。
- **工具栏字号与高度自适应**:主操作按钮改为较细的 Medium 14pt；白色主体内容区提高到至少 44pt，并继续按字体实际行高计算，窗口和玻璃层同步增高。
- **权限重置行为**:点击“重置权限”后只调用系统辅助功能授权询问，不再自动打开辅助功能设置页面。
- **API Key 存储方式**:移除 Keychain 访问、存储、迁移和重试逻辑，改为使用 UserDefaults 本地缓存，保存和安装后恢复不再触发系统密码验证。
- **对话窗口缩放抖动**:移除四角双轴缩放，调整尺寸时一次只修改宽度或高度，避免窗口 frame 与内容布局同时竞争。
- **清理已确认死代码**:移除未被生产代码或测试引用的工具图标映射、旧标题属性、无参辅助功能便捷接口、旧权限入口、未使用图标视图、原文切换方法和菜单圆角常量；保留测试注入接口及 `AiAgentSession.draftRevision`。
- **流式滚动控制权**:滚动通知改为同步处理，避免将布局变化误判为用户滚动；滚轮、拖动与惯性滚动期间只更新内容，不强制跟尾，结束后按用户最后停靠位置恢复；禁用对话区异步预绘制滚动，Markdown 高度统一交给 Auto Layout；跟尾容差从 32pt 收紧到 1pt，避免靠近底部就被吸附。
- **正式回答代码块发灰**:移除深度理解模式对整个 Markdown 视图施加的 0.78 透明度，仅淡化正文前景色，保留代码卡片不透明纯黑；增加实际绘制像素和祖先透明度回归检查。
- **流式输出底部闪烁**:Markdown 流式快照从整段 `NSTextStorage` 替换改为只替换当前未完成段落，保留已完成段落的 glyph/layout 缓存；文本应用、文档增高与 follow-tail 滚动改为同一次无动画 Core Animation 提交；用户离开底部时仍持续渲染流式快照并锁定当前 offset，不再于重新到底时一次性补齐积压内容；同时将 `invalidateCursorRects` 限制到模式切换，窗口缩放 frame 取整并跳过无变化帧。

### 变更
- **工具栏按钮光标**:功能按钮恢复使用系统默认箭头光标，避免点击按钮时显示划词光标。
- **工具栏功能按钮间距**:主操作按钮之间的横向文字间距从 7pt 增加到 11pt，提升按钮可读性和点击区域的呼吸感。
- **工具栏精简**:移除未实现且无实际用途的“润色”占位按钮，保留核心操作入口。
- **对话窗口视觉精简**:移除头部下方和输入区上方的两条横向分割线；Markdown 代码块改为纯黑背景。
- **内容层圆角改为同心方案**:结果窗/工具栏/设置窗的白色内容层圆角 = 外圆角 24pt − 玻璃外缘 12pt = 12pt(Apple concentric corners 标准,内外曲线共享圆心、边缘留白厚度恒定);修复设置窗首次打开出现在屏幕底部的问题(center() 早于内容加载,borderless 窗口尺寸变化锚定左下角导致偏移,现改为先装内容再居中并在每次 showWindow 时居中)。
- **设置窗口对齐对话窗口 UI**:改为 borderless 玻璃窗口(HaxGlassView + 白色内容层 + 12pt 玻璃外缘 + 24pt 圆角),顶部为品牌图标 + 标题 + 右上角单个圆形关闭按钮,可拖背景移动;移除系统标题栏/系统关闭按钮与内容区重复大标题,内容区背景透明由内容层承载。
- **追问建议胶囊字体**:胶囊内英文改用 Google Sans Mono(中文 OPPO Sans 级联),与 Markdown 正文一致。
- **思考卡片左侧竖条**:思考过程展开卡片左缘增加 3pt 半透明白色圆角竖条,呼应引用块的“思考中”视觉;思考文字相应右移。
- **其他 UI 字体统一 OPPO Sans**:工具栏按钮、结果窗标题/状态/输入框/建议胶囊/思考标签、菜单栏设置页、权限引导页等全部 UI 文字(中英文)改用 OPPO Sans(按字重映射 ttf 内 Light/Regular/Medium/SemiBold/Bold 实例);Markdown 正文字体策略不变。
- **Markdown 正文字体切换**:对话内 Markdown 正文改为拉丁字符 Google Sans Mono + 中文级联回退 OPPO Sans(经 `AppFont.body` 字体描述符级联实现,粗体合成);代码块/行内代码同为 Google Sans Mono。
- **内置字体接入**:从 Plume PDF 内置字体提取 `GoogleSansMono-Regular.ttf`、`OPPO_Sans_4.0.ttf` 打包至 `Sources/Resources/Fonts`,新增 `AppFont` 负责 bundle 字体注册与构造;Fonts/HaxIcons 加入 xcodeproj Copy 脚本并修复多项 25 位非法对象 ID(`AiChatInputBar`/`HaxIcons` 此前在 Xcode 构建中被静默丢弃)。
- **移除结果窗顶部划词原文展示区**:`SourceTurnView` 及其结构 diff 条目删除,对话直接以 AI 回复开始。
- **对话窗可移动、边缘缩放重做**:`isMovableByWindowBackground` 全模式开启;缩放改为窗口四边 + 四角命中(根视图 12pt 边带),macOS 15+ 使用系统对角缩放光标(旧系统退化为左右/上下),拖拽方向按被拖动边缘为锚点计算,最小 460×400、不超过屏幕;移除右下角十字光标把手。
- **玻璃外缘恢复 12pt**:`glassContentInset` 从 10pt 恢复为旧版的 12pt;思考卡片左侧竖条从 3pt 最终减为 1pt。
- **工具栏“回到上一个对话”气泡入口**:重新划词归档有内容/进行中的会话(任务后台继续),点击气泡图标可重新进入上一个对话窗;新增 `ConversationArchiveTests`。
- **深色卡片背景提亮**:代码块卡片(0x2E3038@0.96)与思考过程卡片(0x22242B@0.94)带透明度叠加后观感接近纯黑;改为不透明的更亮深灰(代码块与思考卡统一为不透明纯黑 #1A1B1E);思考卡与代码块的左缘阶梯状渲染已修复(横向改用 lineRect 求宽度,纵向保留 usedRect)。
- **Markdown 标题行距**:标题段落补 5pt 行距,多行标题不再挤在一起。
- **代码块边距补齐**:本地 Down 补丁修复 `inset(by:)` 将 `tailIndent` 写死为负值导致代码文本越过卡片右缘的问题;code 段落补卡内左右各 8pt、与上下文各 20pt(视觉约 10pt)的间距。
- **思考过程展开样式**:箭头改为 SF Symbol(`chevron.right`/`chevron.down`,按钮内自动垂直居中,与文字同色);展开的思考内容放入深色圆角卡片(0x22242B),文字改浅色,与正文输出明确区分。
- **工具栏视觉对齐结果窗口**:工具栏不再贴满玻璃层,四周留 10pt 玻璃外缘,与结果面板同款 24pt 外圆角、白色内容层与白色描边(加粗到 1.25pt);整体尺寸从 420×48 增加到 440×56。
- **思考过程改为纯文字样式**:去掉按钮 bezel/胶囊,变为无边框纯文字(11pt medium、textSecondary 72% 灰),箭头(`›`/`⌄`)紧随文字、同色,spinner 仍为右侧独立 sibling。
- **追问建议胶囊内边距与截断**:`SuggestionButton` 重构为 `SuggestionPill`(背景层 + 内嵌无边距按钮),左右各 11pt 内边距,文字不再贴胶囊边缘;文本过长时胶囊最宽到容器宽度并以尾部省略号截断。
- **Markdown 视觉微调**:行内代码改为纯紫色(0x7C3AED)高亮文字、无背景;代码块卡片上下内边距加大到 10pt、代码行补 3pt 行距,不再与文本贴边;对话内容右侧留白从 16pt 增加到 28pt,为覆盖式滚动条让位。
- **代码块背景改为圆角卡片**：Down 上游 `DownLayoutManager` 对代码块背景逐行满宽直角填充（左右顶到容器边缘）。Down 已改为本地包（`LocalPackages/Down`），本地修补为整块圆角（6pt）卡片，距容器两侧各留 8pt，视觉与此前 CDMarkdownKit 的暗色卡片一致；其余源码未动。
- **Markdown 代码配色修复 + 语法高亮**：行内代码在白色阅读层上改为深色小胶囊(深底浅紫字)，不再几乎不可见；代码块通过引入 [Splash](https://github.com/JohnSundell/Splash)(0.16.0)恢复语法高亮(关键字品红、注释绿、字符串橙、数字浅绿)，高亮通过覆写 `DownStyler.style(codeBlock:)` 叠加在 Down 的暗色代码卡片上，不涉及自写 Markdown 解析。
- **思考过程按钮边框与阴影**：胶囊按钮边框改为 1pt 不透明 `AppTheme.border`，并增加轻微投影(黑色 16% 不透明度、半径 2.5)。

- **Markdown 库替换：CDMarkdownKit → Down**：AI 回复与思考过程的 Markdown 改由 Down（cmark 0.29，CommonMark 合规）渲染，直接产出 `NSAttributedString`，并使用其 `DownTextView` / `DownLayoutManager` 绘制代码块背景与引用条。修复 CDMarkdownKit inline-code 在中文紧贴反引号场景泄漏 UTF-16 hex（`0061...`）的问题；字体与配色仍由 HaxPick 通过 `DownStyler` 定制，段落排版继续沿用库默认值。
- **思考过程标签视觉修正**：折叠态不再有全宽边框卡片。边框/背景只落在“思考过程 ›”胶囊按钮自身，按钮按内容宽度收缩；spinner 是按钮右侧的独立 sibling；展开后才切换到与正文同宽的完整布局。

### 修复

- **过时流式渲染测试更新**：`AiMessageBubblePerformanceTests` 中三个断言“流式期间使用纯文本视图”的用例改为匹配当前实现（流式与完成态共用同一 Markdown 视图原地更新），这些用例在本次改动前就已失败。

### 新增

- **Liquid Glass 跨版本外壳**：新增 `HaxGlassSurface`，macOS 26 / Xcode 26 构建使用 SwiftUI 原生 `glassEffect`，旧系统回退到 `NSVisualEffectView`，并响应“降低透明度”。
- **首次启动权限引导页**：未开启辅助功能时，应用启动会自动弹出引导窗口。
- **托盘菜单 UI 重构**：菜单栏面板改为紧凑玻璃布局；权限正常时收敛为单行状态，并保留 API Key、模型和快捷操作。
- **多模型选择**：菜单栏面板支持在 `deepseek-v4-flash` / `deepseek-v4-pro` 之间切换模型。
- **API Key 可见性切换**：菜单栏 API Key 输入框增加眼睛图标，可在明文/遮盖之间切换。
- **对话气泡 UI**：结果面板改为对话式气泡布局，用户追问右对齐深蓝白字，AI 回复左对齐带图标，多次追问堆叠展示。
- **Markdown + 代码高亮**：`MarkdownWithCodeBlocks` 独立组件，AI 回复按 ` ``` ` 分割渲染，代码块以暗色卡片 + Swift 语法高亮（关键字品红、注释绿、字符串橙、数字浅绿）展示。
- **`SelectionMonitor.stop()`**：提供全局事件监听器清理方法，避免资源泄漏。
- **共享工具层**：`HaxPickPanel`（合并两个 `NSPanel` 子类）、`AppTheme.makeClippedHostingView()`、`NSPoint` 几何扩展。
- **剪贴板兜底单测**：补充文本上下文判定、外部写入保护、marker 等待逻辑，以及 `SelectionMonitor` 对 AX/剪贴板双通道分支的单元测试。

- **移除结果窗顶部的划词原文展示区**:`SourceTurnView` 及其结构 diff 条目删除,对话直接以用户动作/AI 回复开始;`PanelSessionViewModel.showsSourceTurn`/`isOriginalExpanded` 保留但不再驱动 UI。- **移除结果窗顶部的划词原文展示区**:`SourceTurnView` 及其结构 diff 条目删除,对话直接以用户动作/AI 回复开始;`PanelSessionViewModel.showsSourceTurn`/`isOriginalExpanded` 保留但不再驱动 UI。
- **工具栏样式与 AI 对话窗口对齐**：改为与结果侧栏一致的玻璃视觉——`HaxGlassSurface` 玻璃外壳 + `panelContent` 白色微透明内容层 + 白色内描边；移除上半环淡蓝彩虹背景与模糊副本实现（含 `ToolbarRainbowBackground`）。
- **托盘回归系统样式**：托盘菜单改为标准 `MenuBarExtra(.menu)`，仅保留「设置…」「退出」；「设置」打开系统样式的设置窗口（grouped Form），内含辅助功能权限、模型选择、DeepSeek API Key 与版本号。移除 `TrayPanelController` 自建面板、`HaxGlassSurface` 托盘包装与自定义卡片视觉。
- **工具栏移除边框**：保留纯白背景和全圆角，彻底移除边框，避免边缘锯齿和裁剪异常。
- **工具栏改为纯白黑灰边框样式**：移除阴影和透明背景，使用纯白背景与黑灰色圆角边框，避免产生方形半透明残影。
- **工具栏玻璃细节调整**：背景改为白色半透明高斯模糊，强制使用 `NSVisualEffectView` 的真实透出路径；移除无效的 `CIGaussianBlur` 自身图层滤镜，将模糊背景移至 NSHostingView 外部，使用原生 maskImage 裁切且保持背景层 alpha=1；白色边框降低不透明度，禁用功能文字统一改为黑色，整体内容右移并移除分割线。
- **工具栏强化真实透明磨玻璃**：经本机蓝白条纹对照后使用浅色 `.hudWindow` + `behindWindow` 的 `NSVisualEffectView` 系统高斯模糊，确保能隐约透出后方窗口或桌面；白色背景仅作轻微提亮，保留白色 2pt 边框。
- **工具栏恢复浅色磨玻璃**：取消黑色渐变，改用以白色为主的系统高斯模糊材质，保留白色 2pt 边框；复制、翻译、解释改为黑色文字，拖动点阵改为黑色。
- **工具栏视觉重制**：移除工具栏磨玻璃透明效果与选中文字数展示，改为灰黑不透明渐变背景、白色 2pt 边框和全圆角；缩小左侧点阵空隙，复制保留图标，翻译/解释改为纯文字。
- **测试结构精简**：划词监测测试复用统一构造器，剪贴板上下文与观察结果改为表驱动用例，在保留关键分支覆盖的同时减少重复代码。
- **移除 SwiftPM 可运行产物**：`Package.swift` 不再声明 executable product，避免在 Xcode 里从 `Package.swift` 运行出无 .app 包裹的裸可执行文件（托盘图标回退、辅助功能授权按新身份另立条目）；App 统一从 `hax_pick.xcodeproj` 运行，`swift build` / `swift test` 不受影响。
- **统一玻璃视觉语言**：工具栏、结果侧栏和托盘菜单统一使用外亮内暗的同心倒角；结果侧栏保留 12pt 玻璃外缘，托盘菜单保留 8pt 外缘，表现磨砂玻璃厚度。
- **浅色玻璃材质校准**：结果侧栏与托盘菜单的外缘改用高透明 `.underWindowBackground` 磨砂材质，主题背景改为 72% 白色微透明层，可轻微透出桌面色彩，不再呈现纯白实色块。
- **划词工具栏重设计**：改为 378×48pt 深色玻璃工具条，显示品牌图标、选中字数、复制，以及 MVP 的“翻译 / 解释”两个 AI 动作；“翻译”使用品牌橙主动作态。
- **结果侧栏重设计**：结果窗口固定在当前屏幕右侧，宽度为可用区域的 36%（460–560pt），高度为可用区域的 82%（560–720pt）并垂直居中；点击侧栏外不再自动关闭。
- **结果内容层重排**：采用高透明磨砂玻璃外壳与白色磨砂微透明阅读层，输入框保持高不透明度；分区线改为带内边距的 0.5pt 弱分隔线。
- **仓库脱敏**：清空原 Plume 时代 git 历史并重新初始化仓库；提交身份改为 GitHub noreply 邮箱（不暴露真实邮箱）；`.gitignore` 增加 `.DS_Store`。
- **项目更名 Plume → hax_pick**：自 Gitee/ds_tool 复制迁出，Xcode target/product 更名 `hax_pick`，bundle ID 改为 `com.hax.haxpick`，类名 `PlumeApp→HaxPickApp`、`PlumePanel→HaxPickPanel`，SPM 包名 `hax_pick`。
- **品牌图标更换**：`AppIcon.icns` 与菜单栏托盘图标（`MenuBarIcon.png` 32px / `MenuBarIcon@2x.png` 64px）统一更换为新版橙色 "h" 品牌图标，沿用 `hax_pick/` 资源目录与 Copy AppIcon 构建脚本。
- **工具栏焦点策略调整**：划词后的首层工具栏仅悬浮展示，不再主动 `activate` 抢占前台，并在 toolbar 模式保持 `hidesOnDeactivate = false` 避免未激活时被立即收起；进入结果面板时才 `makeKeyAndOrderFront`。
- **浏览器划词兜底恢复**：`AccessibilityTextService` 允许网页内容角色（如 `AXWebArea` / `AXStaticText`）和已知浏览器进入剪贴板 fallback，避免页面外层 Group 被误判为“非文本上下文”而不弹工具栏。
- **早期选区快照回退**：`SelectionMonitor` 在拖动阶段即抓取 AX 选区，并在 `mouseUp` 当下保留最终早期快照；若目标应用自己的划词 toolbar 让后续选区消失，可回退到早快照。
- **剪贴板兜底范围校准**：综合焦点元素、鼠标下元素与父层级的 AX 属性/角色判断文本场景，并以已知浏览器、IDE、Codex bundle ID 处理 WebView/Electron 漏报，同时避免普通非文本拖拽触发。
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

### 修复

- **翻译请求等待时间过长**：翻译请求关闭 DeepSeek thinking，解释请求改为 low reasoning effort，避免短文本翻译进入不必要的深度推理。
- **工具栏出现后继续划词被打断**：拖动期间仅只读 AX，不再模拟 ⌘C；提前显示的工具栏鼠标穿透，松开后恢复交互并校正最终选区。最终异步读取检查手势代次，复制前检查左键状态，避免旧探测干扰下一次拖动。

- **网页 / IDE / Codex 划词无法触发**：新增全局 `leftMouseDragged` 监听，拖动达到 3pt 后立即读取选区；AX 失败时检查鼠标下元素与父层级，并为主流浏览器、IDE、Codex 启用剪贴板兜底。
- **工具栏必须等鼠标松开**：划出第一个词后通过 AX 快速重试提前显示工具栏；为避免打断拖动，剪贴板兜底仅在 `mouseUp` 后执行，并校正最终选区。
- **快速探测污染剪贴板**：拖动切换、取消或超时会终止旧探测并恢复原剪贴板，同时保留并发产生的用户/外部剪贴板写入。
- **浮窗圆角锯齿**：移除外层 `CALayer.cornerRadius` 硬裁剪和会被透明窗口边界截断的 SwiftUI 阴影；圆角由独立合成层统一抗锯齿，窗口投影改由 `NSPanel` 绘制。
- **托盘图标空白**：`extract_menu_bar_template.swift` 用 `NSBitmapImageRep.setColor` 向 `alphaNonpremultiplied` 位图写像素会静默丢失，导致 `MenuBarIcon.png` / `MenuBarIcon@2x.png` 被生成为全透明图、菜单栏托盘图标不可见；改为直接写 `bitmapData` 的 RGBA 字节并重新生成托盘图标。

### 移除

- **KeychainService**：删除未被调用的 Keychain 存储模块（60 行死代码），API Key 统一使用 UserDefaults 存储。
- **冗余代码**：删除 `AppState.modelName`、`AppTheme.white`/`successSoft`、`FloatingToolbarView.copyFeedback`/`clearCopyFeedback()`、`displayedOriginalText` 手动截断、重复 `NSPanel` 子类等约 80-100 行。

### 文档

- **删除 PRD**：`docs/划词助手_PRD.md` 已废弃删除；功能与交互说明统一由 `README.md` 承载，架构与关键机制见 `docs/ARCHITECTURE.md`。
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
