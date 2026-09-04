<div align="center">

<img src="docs/app-icon.png" width="160" alt="HaxPick App Icon" />

# HaxPick — macOS 划词助手

</div>

一个用 Swift 写的 macOS 划词效率工具：

- 在任意 App 中划词（拖动 ≥ 3pt）
- 划出第一个词后即显示悬浮工具栏，无需等待鼠标松开
- 调用 DeepSeek API 对选中文本执行 AI 动作
- 支持继续追问、复制原文/结果、一键重试
- 首次启动会自动弹出辅助功能权限引导页

## 核心功能

### MVP 动作

| 动作 | 工具栏入口 | 说明 |
|------|-----------|------|
| 复制 | 工具栏基础操作 | 直接复制原文，不展开结果侧栏 |
| 翻译 | 主工具栏 | 英文 → 简体中文，单词/短语/句子均支持 |
| 解释 | 主工具栏 | 简要解释 + 分点说明 + 背景补充 |

### 继续追问

结果面板内置推荐问题 chips（每个动作 3 个预置建议）和自由输入框，追问会复用当前原文和上一轮结果作为上下文。

### Markdown 渲染

结果区域支持 Markdown 渲染，像列表、加粗、分段这类格式会直接按排版后的样式显示。

### 双通道划词读取

1. **通道一（优先）**：通过 Accessibility API（`AXUIElement`）读取选中文本，并利用 `kAXBoundsForRangeParameterizedAttribute` 精确定位面板锚点。
   - 从 `mouseDragged` 阶段开始读取，划出第一个词即可弹出工具栏；`mouseUp` 后再用最终选区校正工具栏内容。
2. **通道二（兜底）**：若 Accessibility 读取失败，会检查焦点元素、鼠标下方文本元素及父层级，并对浏览器、IDE、Codex 等已知文本应用模拟 ⌘C。拖动阶段使用 160ms 快速探测，松开后使用最多 400ms 的完整兜底；读到结果后立即恢复原始剪贴板，若外部程序已先改写剪贴板则不覆盖。

### 去重与防抖

- 同一段文本 1.2 秒内不重复触发工具栏。
- 用户关闭面板"忽略"的文本，在下次有效拖动前不再触发。

## 运行方式

1. 用 Xcode 打开 `hax_pick.xcodeproj`
2. 选择 `hax_pick` scheme 并运行
3. 首次启动时完成权限引导页里的辅助功能授权
4. 点击菜单栏图标，在紧凑的玻璃面板里填写 DeepSeek API Key
5. 在浏览器、文档、编辑器等应用中划词测试

## 使用说明

- **划词**：在任意应用中用鼠标拖动选中文本（拖动距离需 ≥ 3pt）；划出第一个词后工具栏即在选区附近出现，松开鼠标时更新为最终选区。
- **焦点策略**：划词后的首层工具栏只悬浮展示，不主动抢占前台焦点；点击 AI 动作后才激活 HaxPick，以支持键盘关闭和继续提问。
- **复制原文**：点击工具栏第一个"复制"按钮，原文直接复制到剪贴板，工具栏自动关闭。
- **AI 动作**：点击翻译或解释后，工具栏切换为固定在当前屏幕右侧的结果侧栏，并自动请求 DeepSeek。
- **继续追问**：点击推荐问题 chip 或在输入框输入问题后点击"发送"。
- **关闭面板**：工具栏可点击外部关闭；结果侧栏常驻显示，通过顶部关闭按钮或 ESC 关闭。
- **重新生成**：对当前结果不满意时点击"重新生成"。
- **权限引导**：首次启动会自动弹出引导页；后续可从菜单栏面板重新打开。

## 技术架构

```
HaxPickApp (SwiftUI @main, MenuBarExtra)
  └── AppDelegate (启动入口)
        └── AppState (单例，中心状态管理)
              ├── SelectionMonitor (全局鼠标事件监听)
              │     ├── AccessibilityTextService (AX API 读取)
              │     └── ClipboardSelectionService (⌘C 兜底)
              ├── ToolbarPanelController (NSPanel 管理)
              │     ├── PanelSessionViewModel (面板状态)
              │     └── FloatingToolbarView (SwiftUI 视图)
              └── DeepSeekService (API 请求)
```

| 文件 | 职责 |
|------|------|
| `Sources/HaxPickApp.swift` | 应用入口，MenuBarExtra UI |
| `Sources/AppDelegate.swift` | 启动回调 |
| `Sources/AppState.swift` | 单例状态管理，协调各组件 |
| `Sources/SelectionMonitor.swift` | 全局鼠标事件监听，划词检测与去重 |
| `Sources/AccessibilityTextService.swift` | AX API 读取选中文本和坐标 |
| `Sources/ClipboardSelectionService.swift` | 模拟 ⌘C 获取文本，剪贴板保存/恢复 |
| `Sources/ToolbarPanelController.swift` | NSPanel 创建、定位、ESC/点击外关闭 |
| `Sources/FloatingToolbarView.swift` | SwiftUI 工具栏/结果面板视图 + ViewModel |
| `Sources/DeepSeekService.swift` | DeepSeek API 调用、Prompt 构建、错误处理 |
| `Sources/PermissionGuideWindowController.swift` | 首次启动权限引导窗口控制 |
| `Sources/PermissionGuideView.swift` | 首次启动权限引导页 |
| `Sources/MenuBarContentView.swift` | 菜单栏紧凑玻璃面板 UI |

## 配置说明

- **API Key**：存储于 macOS Keychain，用户需在菜单栏面板中自行填写自己的 DeepSeek API Key。
- **模型**：可在菜单栏面板中切换 `deepseek-v4-flash` / `deepseek-v4-pro`。
- **请求超时**：45 秒。
- **系统要求**：macOS 13+。
- **首次启动权限引导**：若未开启辅助功能，应用会自动弹出引导窗口；也可以从菜单栏面板重新打开。

## 面板规格

| 属性 | 工具栏模式 | 结果面板模式 |
|------|-----------|-------------|
| 尺寸 | 378×48pt | 可用宽度的 36%（460–560pt），可用高度的 82%（560–720pt） |
| 圆角 | 15pt | 28pt |
| 内边距 | 3pt 内层倒角 | 白色阅读层距玻璃外缘 12pt + 内容区分区内边距 |
| 屏幕边缘安全间距 | 16pt | 右侧 16pt，垂直居中 |
| 风格 | 深色磨砂玻璃 | 高透明玻璃外缘 + 白色磨砂微透明内容层 |

> 工具栏、结果面板和菜单栏面板使用同一套外亮内暗玻璃倒角；分区线不触边并降低对比度。工具栏任意空白位置均可拖动移动。

## 后续可增强

- [x] API Key 从 UserDefaults 迁移到 Keychain
- [ ] 面板弹出/切换动画（淡入 + 上移）
- [ ] 全局快捷键唤起
- [ ] 历史记录
- [ ] TTS 朗读
- [ ] OCR 截图问答
- [x] 多模型切换
- [ ] 点赞/点踩反馈
