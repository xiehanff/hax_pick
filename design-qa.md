# Design QA

## 对比目标与证据

- Source visual truth: `/Users/hax/.codex/generated_images/01a06a15-d0b6-7773-9884-eaa7332809de/exec-5b437167-f2e6-4f0a-95a9-94f0bbe27999.png`
- Result panel: `/Users/hax/Documents/GitHub/hax_pick/artifacts/design-qa/result.png`
- Toolbar: `/Users/hax/Documents/GitHub/hax_pick/artifacts/design-qa/toolbar.png`
- Menu bar panel: `/Users/hax/Documents/GitHub/hax_pick/artifacts/design-qa/menu.png`
- Same-input comparison: `/Users/hax/Documents/GitHub/hax_pick/artifacts/design-qa/comparison.png`
- State: 浅色桌面主题；工具栏处于“已选中文本、默认翻译主动作”状态；结果面板处于“翻译生成完成”状态；菜单栏面板处于权限与 API Key 均正常状态。
- Viewport: 当前显示器可用区域为 1512 × 875 pt；实际计算出的结果面板为 544 × 718 pt，右侧保留 16 pt 并垂直居中；工具栏为 378 × 48 pt；菜单栏面板为 320 × 291 pt。
- Density normalization: 最终三个实现截图均以 1x 逻辑尺寸保存；source 文件是 1487 × 1058 px 的概念合成图。结果面板和菜单栏面板先以 @2x 原生窗口捕获，再无插值比例偏差地归一为 544 × 718 px 与 320 × 291 px；不把桌面内容或像素密度差异记作缺陷。
- State normalization note: source 同时表达工具栏和结果面板，但真实产品中两者为前后状态；实现证据分别捕获后放入同一张 comparison 图。source 未展示菜单栏面板，菜单栏面板按用户明确要求，以结果面板的玻璃外缘、内层白底、同心圆角和弱分隔线作为视觉基准。

## Findings

- 没有遗留 P0、P1 或 P2 问题。
- 字体与排版：使用 macOS 系统字体；标题、正文、状态和辅助文字的层级与 source 一致。实现内容为真实动态文本，换行差异不影响视觉层级。
- 间距与布局：结果面板从旧版接近全高的窄侧栏调整为更宽、更短且垂直居中的浮窗；工具栏压缩为 48 pt；菜单栏面板从大卡片堆叠收敛为紧凑信息面板。
- 玻璃与圆角：结果面板保留 12 pt 外缘，菜单栏面板保留 8 pt 外缘；浅色外缘使用 `.underWindowBackground` 磨砂材质并只叠加 4% 白色，主题背景叠加 72% 白色，形成“外缘更透、主体白色磨砂微透明”的关系。外亮边与内暗边形成同心倒角，玻璃厚度可见。透明窗口不再承载会被边界裁切的 SwiftUI 阴影，投影由 `NSPanel` 绘制；连续圆角表面使用独立合成层，实机截图未见锯齿。
- 分隔线：结果面板和菜单栏面板统一使用带水平内边距的 0.5 pt、5.5% 黑色弱分隔线，不触碰内层边缘。
- 颜色与资产：品牌橙、绿色完成状态、深石墨工具栏和透白磨砂内容层与 source 一致；品牌图标使用应用正式资产，其余图标使用 SF Symbols。图标差异按用户要求列为允许偏差。
- 文案与状态：工具栏默认将“翻译”表现为橙色主动作；关闭、复制、重新生成、推荐追问和发送禁用态均保留。
- 可访问性：按钮语义和帮助文字保留；Reduce Transparency 下提供实色回退；输入和菜单控件继续使用原生 SwiftUI 控件。

## Comparison history

### Pass 1 — 初始实现

- [P1] 结果面板过窄且接近全高，与 source 的独立浮窗比例相差明显。
- [P1] 菜单栏面板采用大块卡片堆叠，信息密度和会话面板不一致。
- [P1] 工具栏缺少明确的橙色主动作，整体高度和按钮比例偏厚。
- [P2] 分隔线横向顶边且对比度偏高，视觉生硬。

### Pass 2 — 比例和视觉语言统一

- 结果面板改为宽度 36%（460–560 pt）、高度 82%（560–720 pt），右侧垂直居中。
- 工具栏调整为 378 × 48 pt，并固定突出“翻译”主动作。
- 菜单栏面板调整为 320 pt 紧凑结构，三处统一使用玻璃外壳和白色内容层。
- [P2] 对照后发现玻璃外缘仍偏窄，不能充分表现 source 中的倒角厚度。

### Pass 3 — 玻璃厚度和弱分隔线

- 结果面板外缘增至 12 pt，菜单栏面板外缘设为 8 pt；增加外亮内暗的同心描边。
- 分隔线改为带内边距的 0.5 pt 弱线。
- [P1] 用户指出圆角仍有明显锯齿；检查确认透明窗口边界裁切了 SwiftUI 阴影，外层硬裁切也会放大 1x 显示器的锯齿感。

### Pass 4 — 圆角抗锯齿修复

- 移除外层 `CALayer.cornerRadius` 硬裁切和 SwiftUI 外投影。
- 玻璃外壳、内层表面均使用 `.continuous` 圆角并独立合成；阴影交由 `NSPanel` 绘制。
- Post-fix evidence: `artifacts/design-qa/toolbar.png`、`result.png`、`menu.png` 和 `comparison.png`。
- Result: 三个 UI 的外轮廓连续、倒角同心，玻璃厚度和弱分隔线清晰；没有新增可执行的 P0、P1 或 P2 问题。

### Pass 5 — 浅色玻璃透明度 1:1 校准

- [P1] 用户指出实现的玻璃外缘呈中性灰，source 的外缘更透明；实现主题背景接近纯白实色，source 为白色磨砂微透明。
- Fix: 浅色玻璃从 `.popover` 改为 `.underWindowBackground`，外缘白色叠加从 22% 降至 4%，外缘高光降至 78%，暗边降至 5.5%；主题背景从实色 `#FCFCFD` 改为 72% 白色叠加。
- Post-fix evidence: `artifacts/design-qa/result.png`、`menu.png` 与重新生成的 `comparison.png`。原生窗口捕获中，主题空白区由约 99.1% 白降低到约 97.5% 白，并保留磨砂底层；外缘由约 84.7% 中性灰提升到约 90.9% 的更轻、更透表面。
- Result: 外缘与主题背景不再是灰边/纯白块关系，材质层级与 source 一致；除用户允许的图标差异外，没有遗留可执行的 P0、P1 或 P2 问题。

## Focused region evidence

- Toolbar: 检查 15 pt 连续圆角、3 pt 内倒角、橙色主动作、计数与复制按钮密度。
- Result panel: 检查 28 pt 连续圆角、12 pt 玻璃外缘、内层同心曲率、弱分隔线和底部输入区。
- Menu bar panel: 检查 18 pt 连续圆角、8 pt 玻璃外缘、紧凑权限/API Key/模型布局和弱分隔线。
- Native interaction: 实际 AppKit/SwiftUI 窗口截图用于核对圆角与透明窗口投影；核心动作、状态切换和面板会话行为由现有测试覆盖。

## Implementation checklist

- [x] 工具栏、结果面板、菜单栏面板使用同一玻璃视觉语言。
- [x] 玻璃外缘加宽，并以同心倒角表现厚度。
- [x] 分隔线带内边距且弱化。
- [x] 透明面板圆角和阴影不再产生明显锯齿。
- [x] 外缘使用高透明磨砂材质，主题背景使用白色磨砂微透明层。
- [x] 结果面板比例贴近 source，并保持右侧悬浮而非贴满屏高。
- [x] 工具栏和菜单栏面板信息密度贴近结果面板。

## Follow-up polish

- [P3] 当前机器使用 Xcode 16.4 / macOS 15，已实测 `NSVisualEffectView` 兼容分支；可在 macOS 26 正式环境补充一张原生 `glassEffect` 截图，但不影响本次验收。

final result: passed
