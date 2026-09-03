<div align="center">

<img src="docs/app-icon.png" width="160" alt="HaxPick App Icon" />

# HaxPick — macOS 划词助手

</div>

一个用 Swift 写的 macOS 划词效率工具：

- 在任意 App 中划词（拖动 ≥ 8pt）
- 松开鼠标后自动弹出悬浮工具栏
- 调用 DeepSeek API 对选中文本执行 AI 动作
- 支持继续追问、复制原文/结果、一键重试
- 首次启动会自动弹出辅助功能权限引导页

## 核心功能

### 7 种动作

| 动作 | 工具栏入口 | 说明 |
|------|-----------|------|
| 复制 | 主工具栏 | 直接复制原文，不展开面板 |
| 翻译 | 主工具栏 | 英文 → 简体中文，单词/短语/句子均支持 |
| 解释 | 主工具栏 | 简要解释 + 分点说明 + 背景补充 |
| 总结 | 主工具栏 | 一句话总结 + 2~4 条要点 |
| 润色 | "更多"菜单 | 不改变原意，优化中文表达 |
| 改写 | "更多"菜单 | 不同表达方式改写 |
| 提取要点 | "更多"菜单 | 一句话概述 + 3~5 条要点 |

### 继续追问

结果面板内置推荐问题 chips（每个动作 3 个预置建议）和自由输入框，追问会复用当前原文和上一轮结果作为上下文。

### Markdown 渲染

结果区域支持 Markdown 渲染，像列表、加粗、分段这类格式会直接按排版后的样式显示。

### 双通道划词读取

1. **通道一（优先）**：通过 Accessibility API（`AXUIElement`）读取选中文本，并利用 `kAXBoundsForRangeParameterizedAttribute` 精确定位面板锚点。
   - 在 `mouseUp` 当下会先抓一份早期 AX 选区快照，避免目标应用自己的划词工具栏在后续 150ms 内把选区冲掉。
2. **通道二（兜底）**：若 Accessibility 读取失败，仅在当前焦点元素仍然像文本控件，或浏览器 Web 内容区域（如 `AXWebArea`）时才模拟 ⌘C 从剪贴板获取选中文本；读到结果后会立刻恢复原始剪贴板，若截图工具或用户操作已先改写剪贴板，则不再强行覆盖。

### 去重与防抖

- 同一段文本 1.2 秒内不重复触发工具栏。
- 用户关闭面板"忽略"的文本，在下次有效拖动前不再触发。

## 运行方式

1. 用 Xcode 打开 `hax_pick.xcodeproj`
2. 选择 `hax_pick` scheme 并运行
3. 首次启动时完成权限引导页里的辅助功能授权
4. 点击菜单栏图标，在新的卡片式面板里填写 DeepSeek API Key
5. 在浏览器、文档、编辑器等应用中划词测试

## 使用说明

- **划词**：在任意应用中用鼠标拖动选中文本（拖动距离需 ≥ 8pt），松开后工具栏自动弹出在选区附近。
- **焦点策略**：划词后的首层工具栏只悬浮展示，不主动抢占前台焦点，并保持 `hidesOnDeactivate = false` 以避免未激活时被系统立即收起；点击 AI 动作进入结果面板时，才激活 HaxPick 以支持键盘关闭和继续提问。
- **复制原文**：点击工具栏第一个"复制"按钮，原文直接复制到剪贴板，工具栏自动关闭。
- **AI 动作**：点击翻译/解释/总结等按钮，工具栏展开为结果面板并自动请求 DeepSeek。
- **继续追问**：点击推荐问题 chip 或在输入框输入问题后点击"发送"。
- **关闭面板**：点击"关闭"按钮 / 按 ESC 键 / 点击面板外任意位置。
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
| `Sources/MenuBarContentView.swift` | 菜单栏卡片式面板 UI |

## 配置说明

- **API Key**：存储于 `UserDefaults`（key: `deepseek_api_key`），用户需在菜单栏面板中自行填写自己的 DeepSeek API Key。
- **模型**：可在菜单栏面板中切换 `deepseek-v4-flash` / `deepseek-v4-pro`。
- **请求超时**：45 秒。
- **系统要求**：macOS 13+。
- **首次启动权限引导**：若未开启辅助功能，应用会自动弹出引导窗口；也可以从菜单栏面板重新打开。

## 面板规格

| 属性 | 工具栏模式 | 结果面板模式 |
|------|-----------|-------------|
| 尺寸 | 480×60pt | 440×548pt |
| 圆角 | 14pt | 14pt |
| 内边距 | 10pt | 18pt |
| 屏幕边缘安全间距 | 12pt | 12pt |
| 风格 | 扁平无阴影 | 扁平无阴影 |

## 后续可增强

- [ ] API Key 从 UserDefaults 迁移到 Keychain
- [ ] 面板弹出/切换动画（淡入 + 上移）
- [ ] 全局快捷键唤起
- [ ] 历史记录
- [ ] TTS 朗读
- [ ] OCR 截图问答
- [x] 多模型切换
- [ ] 点赞/点踩反馈
