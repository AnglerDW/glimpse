# Glimpse P2：工具栏、标注与放大镜 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 P1 的截图主流程上加上编辑阶段：贴着选区的玻璃工具栏（▢ ◯ ↗ ✎ T ▦ ① │ ↶ ↷ │ 保存 │ ✕ ✓）、二级颜色 / 粗细栏、7 种标注工具、撤销重做、带标注的全分辨率输出，以及选区阶段的放大镜和取色。

**Architecture:** 纯逻辑继续放在 `GlimpseCore`（Swift 6 语言模式，`swift test` + Swift Testing，先写失败测试）：工具栏 / 标签 / 放大镜的摆放、标注模型与撤销栈、⇧ 约束、箭头几何、画笔平滑、马赛克、文字排版、合成器、取色。App 层只做 AppKit 胶水：`MaterialView` 封装两种玻璃，`ToolbarView` / `StylePaletteView` / `GlassLabelView`（尺寸标签和工具提示）/ `MagnifierView` 各自成文件，标注画在独立的 `AnnotationCanvasView` 里，`SelectionView` 只负责把鼠标键盘转发过去。标注以冻结画面的**像素坐标**存储（设计文档 §5.2），屏幕显示和导出都调用同一个 `Renderer.draw`。

**Tech Stack:** Swift 6.3 / Xcode 26.6（macOS 26.5 SDK）、macOS 14+ 部署目标、AppKit（`NSGlassEffectView` / `NSVisualEffectView`、`NSTextView`）、CoreGraphics、CoreText、Swift Testing、XcodeGen。

**设计文档：** `docs/superpowers/specs/2026-11-04-glimpse-design.md`
**上一期计划：** `docs/superpowers/plans/2026-11-04-glimpse-p1-capture.md`（已验收）

**范围外（P3 再做）：** 识别文字（OCR）按钮和结果面板、贴图按钮和贴图浮窗、HUD 提示（P2 里失败仍是 `NSLog` + 提示音）、引导页、设置页、开机自动启动。工具栏里**不放**这两个按钮的占位；P3 按设计文档 §3.3 的顺序把「识别文字」「贴图」插到第三组「保存」前面（`ToolbarItem.groups` 第三组改成 `[.recognizeText, .pin, .save]`）。

**提交约定：** 用户要求不由 agent 执行 `git commit`。本计划不含提交步骤；每个任务结束时「停下，不 commit」，把改动交给用户检查。

**执行约束：** 执行本计划的 agent **不得**启动应用、不得运行 `scripts/run.sh`、不得做任何会触发系统权限弹窗的操作。agent 只跑 `swift test` 和 `scripts/build.sh`；每个界面任务末尾的「手动检查」由用户在真机上做。

---

## 实施前说明（2026-11-05）

本计划以 P1 验收后的**实际代码**为准（不是 P1 计划里的原稿）。写计划时核对过的现状：

- `EditorPhase` 是 `.selecting` / `.editing(tool: Tool?)` / `.typing`；`KeyRouter` 已经把 R/O/A/P/T/M/N、Esc、⌘Z / ⌘⇧Z、C、方向键都路由好了，P1 只是没处理 `selectTool`、`deselectTool`、`undo`、`redo`、`copyColor`、`passToTextField`、`endTyping`、`reselect`。
- 遮罩已经是 **55%** 黑色（设计文档 §3.2、§4.3 已改），本计划不动它。
- `SelectionView` 有 `clearHover()`；`mouseMoved` 每次都会调 `delegate?.selectionViewDidMouseEnter(self)`；`CaptureSessionController` 用 `mouseScreenView` 去重并清掉其他屏的悬停；跟踪区域带 `.assumeInside`。本计划的修改都在这个版本上做，替换片段里的原文都来自当前文件。
- `Renderer.crop` 输出独立小图（不引用整屏冻结画面），色彩空间跟冻结画面一致（P3 屏上是 Display P3）；Task 9 的合成保持这两点。
- 写计划时 `swift test` 是 58 个测试；批次 A 完成后是 80 个（各任务的预期总数见对应步骤）。

**SDK 核对（玻璃材质）**：`xcrun --show-sdk-path` → `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`（Xcode 26.6，本机 macOS 26.5）。`AppKit.framework/Headers/NSGlassEffectView.h` 里：

```objc
API_AVAILABLE(macos(26.0))
@interface NSGlassEffectView: NSView
@property (nullable, strong) __kindof NSView *contentView;
@property CGFloat cornerRadius;
@property (nullable, copy) NSColor *tintColor;
@property NSGlassEffectViewStyle style;   // NSGlassEffectViewStyleRegular / Clear，Swift 里是 NSGlassEffectView.Style
@end
API_AVAILABLE(macos(26.0))
@interface NSGlassEffectContainerView: NSView   // 合并相邻玻璃，P2 不用
```

头文件特别说明：只保证 `contentView` 在玻璃里面，随便 `addSubview` 的子视图层级不保证。所以 `MaterialView` 把内容都放进 `contentView`。macOS 14 / 15 用 `NSVisualEffectView`：`material = .popover`（跟随日夜间；`.hudWindow` 永远偏深，不符合 §4.2「日间玻璃偏白」），`blendingMode = .withinWindow`（覆盖层窗口不透明，要模糊的是同一窗口里的冻结画面），`state = .active`（Glimpse 永远不是前台应用，不设的话会一直显示成非活跃的灰色）。`NSWindow.h` 里也有 `allowsToolTipsWhenApplicationIsInactive`，但它只解决「应用不活跃时显示提示」，解决不了层级：AppKit 的提示窗口层级低于 `.screenSaver`，会被覆盖层挡住。所以工具提示由覆盖层自己画（见下面第 19 条），不用 AppKit 的 `toolTip`。

**设计文档没说死、本计划自己定下的地方**（取主流截图工具的做法，尽量少做）：

1. **先出工具栏**：批次 A 结束就能在真机上看到玻璃工具栏，✕ / ✓ / 保存可用。7 个工具按钮一开始就全部显示（布局一次定好），还没实现的工具按钮置灰、对应字母键无效；由 `App/Sources/Toolbar/ToolRollout.swift` 里的一个集合控制，每个工具任务往里加，Task 8 删掉这个文件。撤销 / 重做按钮在没有可撤销内容时置灰。
2. **工具栏位置**：选区下方、右边缘对齐选区右边缘（✕ ✓ 挨着选区右下角，同微信 / Snipaste）；下方放不下放上方，再放不下放进选区内部右下角；左右超出屏幕时平移回来，离屏幕边至少 4pt，离选区 8pt。
3. **二级栏位置**：放在工具栏远离选区的一侧（工具栏在选区下方或内部 → 二级栏在工具栏下方；工具栏在上方 → 二级栏在工具栏上方），这一侧放不下就换另一侧；左边缘对齐工具栏左边缘（工具按钮那头）。工具栏本身的位置不因二级栏出现而跳动。
4. **尺寸标签**：改成同一种材质，圆角取 min(12, 半高)，接近胶囊，照视觉稿 `radius-v2.html` 的 `.size`（设计文档只规定了工具栏 / 面板 12pt、按钮 8pt；实施中按视觉稿定，不用最初写的 8pt）。工具栏放在选区上方且挡住标签时，标签移进选区左上角内侧。标签不拦截鼠标。
5. **颜色**：6 个预设色是红 `#FF3B30`、橙 `#FF9500`、黄 `#FFCC00`、绿 `#34C759`、蓝 `#007AFF`、黑 `#000000`；夜间外观下「黑」画成白 `#FFFFFF`。画的那一刻把颜色解析成具体 RGB 存进标注，之后切换外观不会改已画的标注。
6. **三档粗细对各工具的含义**（单位 pt，存储时乘以缩放倍数变成像素）：矩形 / 椭圆 / 箭头 / 画笔线宽 2 / 4 / 6；文字字号 14 / 20 / 28；马赛克笔刷直径 12 / 24 / 40；序号圆直径 20 / 26 / 34。默认红色、中档。颜色和粗细档**全局共用**（设计文档 §3.3；用户反馈「换工具又被重置了」）：所有工具用同一个当前颜色、同一档粗细，换工具不重置；同一档对不同工具仍对应上面各自的尺寸。马赛克不用颜色，只跟粗细档。存 `UserDefaults`，一个键 `annotationStyle`（新的小 store `AnnotationStyleStore`，不往 `SettingsStore` 里塞；还没发布过，早先的 `toolStyle.<工具>` 键直接弃用，不做迁移）。
7. **箭头**：一个实心多边形。箭杆从尾部细到头部渐粗（设计文档 §3.4；用户反馈等粗的箭杆不好看，同微信 / Snipaste）：尾部半宽 = max(0.5, 0.15 × 线宽)（至少 1 像素宽），接箭头处半宽 = 0.8 × 线宽；箭头长 = 4.5 × 线宽、半宽 = 2.2 × 线宽，明显宽于箭杆末端。箭头最多占箭头总长的 60%：短箭头的头部随之缩短，各处宽度按同一比例缩小，所以再短也保留「细尾 → 箭杆 → 箭头」，不会变成一个胖三角。⇧ 吸附到最近的 45° 倍数，保持拖拽长度。
8. **⇧ 约束**：矩形 / 椭圆取两边中较长的一边，朝拖拽方向延伸。拖拽中按下或松开 ⇧ 立即生效，不用等鼠标移动。
9. **点一下不拖**：矩形、椭圆、箭头不生成标注；画笔、马赛克点一下画一个点。
10. **马赛克**：块大小 8pt（按屏幕像素取整），块网格从冻结画面左上角对齐，所以多笔之间、屏幕显示和导出完全一致；像素取自原始冻结画面，不取已画的标注（§3.4 原文），所以马赛克会盖住它下面的标注。马赛克没有颜色，选中马赛克时二级栏的 6 个色块置灰。
11. **序号**：按下鼠标就放置（快速连点不丢号）；数字 = 当前最大序号 + 1，所以撤销 ③ 之后再放还是 ③。圆内数字为粗体，黄色、白色底用黑字，其他用白字。
12. **文字**：单击处是第一行的竖直中线（光标出现在点击处）；不自动换行，只有 Enter 换行；输入时改二级栏的颜色 / 字号会作用到当前文本框；结束输入时只含空白的文本框直接丢弃；一个文本框是一个撤销步骤；输入期间的 ⌘Z 和工具栏的撤销 / 重做只作用于文本框里的输入（不结束输入）。点工具栏其他按钮先结束输入（文字保留），所以输入中点 ✓ 会把文字一起复制；在另一块屏上单击也只结束输入，不在那块屏开始新选区。结束输入时输入法还没上屏的组字丢弃（同组字中按 Esc）。Tab 不输入任何东西。文本框和提交后的标注逐像素重合（emoji 最多差 1px）：文字标注记下屏幕缩放倍数，Core 按点字号排版再放大，和文本框同一套排版，中文、emoji 等后备字体才不会提交后变宽变窄；基线行底对齐，文本框把每行基线固定住（见 Task 8）。菜单栏应用没有「编辑」菜单，⌘C / ⌘V / ⌘X / ⌘A / ⌘Z / ⇧⌘Z 由文本框自己处理。输入法正在组字时按 Esc 只取消组字，不结束输入。
13. **画完不自动取消工具**：画完一个标注、结束一次文字输入后，工具保持选中（同 Snipaste），可以连续画。
14. **只能在选区内开始画**：选了工具后，在选区外按下鼠标不画；从选区内开始画的标注可以画出选区，超出部分在屏幕上被遮罩压暗，导出时被裁掉（§5.2）。标注层在遮罩下面。例外：正在输入的文本框在遮罩上面（要能收点击），伸出选区的部分输入时不压暗，结束输入变成标注后才压暗；接受这个差别。
15. **撤销粒度**：一个标注一步。右键清除选区和标注不进撤销栈（§3.2 右键就是「重来」）。
16. **放大镜**：只在选区阶段显示（包括正在拖出选区时）；有选区的情况下其他屏不显示放大镜。15 × 15 像素放大 8 倍，中心像素描边；下面三行是**像素**坐标（冻结画面的像素，Retina 屏上是点坐标的 2 倍）、RGB（`RGB 255, 59, 48`）和十六进制（`#FF3B30`）。色值换算到 sRGB（设计软件和 CSS 用的就是它），不显示 P3 原始值。（已被 spec §3.2 / §4.1 取代，见文末「实施后修正」）
17. **按 C / ⇧C 复制色值后退出截图**：C 复制十六进制（`#FF3B30`），⇧C 复制 RGB（`255, 59, 48`，不带前缀）；色值以文本放进剪贴板，然后关闭覆盖层，跟 Enter 复制图片后关闭一致（同 Snipaste）。设计文档 §3.2 第 2 步和 §3.2.1 选区阶段已同步。⇧C 的按键路由在 Task 10 加进 `KeyRouter`。
18. **合成方式**：§5.2 写的是「先在整屏上合成标注，再裁剪」。实现上直接开一张选区大小的位图、把坐标系平移到选区左上角，再画整屏冻结画面和标注，结果逐像素等价，但不用再分配一张整屏大图。马赛克仍从原始整屏画面取块。
19. **工具提示自己画（主方案，不是退路）**：鼠标在工具栏按钮上停 0.6 秒，覆盖层里出现一个和尺寸标签同款的玻璃小标签，内容是「名称（快捷键）」，放在按钮朝向选区的一侧（另一侧可能是二级栏），放不下就翻到另一侧；移开或按下按钮即消失，工具栏移动时也消失。理由：AppKit 提示窗口在 `.screenSaver` 覆盖层下面大概率看不见，与其写一个「看不见再改」的条件步骤，不如直接自己画——代码量小（复用 `GlassLabelView` 和 `OverlayLayout`），外观和工具栏统一（用户看重工具栏的观感），也不依赖 AppKit 未公开的层级。二级栏的色块 / 粗细按钮只设 VoiceOver 名称，不设悬停提示（设计文档只要求工具栏有提示）。

---

## 文件结构

新增（+）与修改（~）：

```
glimpse/
├─ Core/Sources/GlimpseCore/
│  ├─ Geometry/OverlayLayout.swift            + 工具栏 / 二级栏 / 尺寸标签 / 工具提示摆放（Task 1）
│  ├─ Geometry/Magnifier.swift                + 放大镜取样范围、摆放、像素取色（Task 10）
│  ├─ Annotation/AnnotationStyle.swift        + RGBA、PaletteColor、StrokeWidth、AnnotationStyle、各工具三档尺寸（Task 3）
│  ├─ Annotation/TextLayout.swift             + 文字字体、行高、逐行绘制（Task 3）；行底对齐的基线（Task 8）
│  ├─ Annotation/Annotation.swift             + 标注模型（像素坐标）、bounds、ArrowMetrics（Task 3）；文字记下屏幕缩放倍数（Task 8）
│  ├─ Annotation/AnnotationDocument.swift     + 标注列表 + 撤销重做 + 序号（Task 3）
│  ├─ Annotation/ShapeGeometry.swift          + ⇧ 约束、45° 吸附、箭头外形（Task 4）、画笔平滑（Task 6）
│  ├─ Annotation/AnnotationDraft.swift        + 正在拖拽的标注（Task 4）
│  ├─ Annotation/TextAnnotation.swift         + 文字框起点、空白丢弃（Task 8）
│  ├─ Rendering/AnnotationRenderer.swift      + Renderer.draw：逐种标注绘制（Task 4 起，6 / 7 / 8 补全）
│  ├─ Rendering/MosaicSource.swift            + 冻结画面的像素化缓存（Task 7）
│  ├─ Rendering/Renderer.swift                ~ crop 改为 composite 的特例，新增 composite（Task 9）
│  ├─ Input/EditorInput.swift                 ~ ⇧C 复制 RGB 色值的按键路由（Task 10）
│  └─ Settings/AnnotationStyleStore.swift     + 全局共用的颜色 / 粗细记忆（Task 3）
├─ Core/Tests/GlimpseCoreTests/
│  ├─ TestImage.swift                         ~ 新增 render(_:width:height:)（Task 4）
│  ├─ OverlayLayoutTests.swift                + Task 1
│  ├─ AnnotationModelTests.swift              + Task 3
│  ├─ AnnotationStyleStoreTests.swift         + Task 3
│  ├─ ShapeToolTests.swift                    + Task 4
│  ├─ PenCounterTests.swift                   + Task 6
│  ├─ MosaicTests.swift                       + Task 7
│  ├─ TextAnnotationTests.swift               + Task 8
│  ├─ KeyRouterTests.swift                    ~ ⇧C（Task 10）
│  ├─ CompositeTests.swift                    + Task 9
│  └─ MagnifierTests.swift                    + Task 10
└─ App/Sources/
   ├─ Material/MaterialView.swift             + 液态玻璃 / 毛玻璃统一封装（Task 2）
   ├─ Toolbar/ToolbarItem.swift               + 按钮清单、图标、名称、快捷键（Task 2）
   ├─ Toolbar/ToolbarButton.swift             + 30×30、8pt 圆角的图标按钮（Task 2）
   ├─ Toolbar/ToolbarView.swift               + 工具栏（Task 2）
   ├─ Toolbar/ToolRollout.swift               + 临时：已上线的工具（Task 2 建，Task 8 删）
   ├─ Toolbar/StylePaletteView.swift          + 二级栏：6 色 + 3 档粗细（Task 5）
   ├─ Annotation/AnnotationCanvasView.swift   + 标注层：文档、草稿、样式、文字框（Task 5 起）
   ├─ Annotation/AnnotationTextView.swift     + 输入层的文本框（Task 8）
   └─ Overlay/
      ├─ GlassLabelView.swift                 + 玻璃材质的单行标签：尺寸标签、工具提示（Task 2）
      ├─ MagnifierView.swift                  + 放大镜（Task 10）
      ├─ OverlayContentView.swift             ~ 变成每屏的组装者：图层顺序、摆放工具栏等（Task 2、5 整体替换，7 / 8 / 10 局部修改）
      ├─ SelectionView.swift                  ~ 去掉自绘标签；转发工具手势；输入层；放大镜（Task 2、5、6、8、9、10 局部修改）
      ├─ OverlayWindow.swift                  ~ 传入 AnnotationStyleStore（Task 5）
      └─ CaptureSessionController.swift       ~ 持有 AnnotationStyleStore（Task 5）；输入中在别的屏单击只结束输入（Task 8）
```

`project.yml` 不用改：`App/Sources` 下新建的子目录会被 XcodeGen 自动收进工程，`scripts/build.sh` 每次都会重新生成工程。

## 批次与真机检查点

| 批次 | 任务 | 结束后用户在真机上能验证的 |
|---|---|---|
| A 工具栏 | Task 1–2 | 玻璃工具栏贴着选区、跟随移动 / 缩放、上下避让；✕ / ✓ / 保存可用；尺寸标签换成玻璃 |
| B 标注模型 + 形状 | Task 3–5 | 二级栏；矩形、椭圆、箭头；⇧ 约束；撤销重做；右键清除；颜色 / 粗细全局共用并记忆 |
| C 画笔 / 序号 / 马赛克 | Task 6–7 | 画笔平滑、序号递增与回退、马赛克 |
| D 文字 | Task 8 | 文字工具和输入层按键规则、中文输入法 |
| E 输出 + 放大镜 | Task 9–10 | 复制 / 保存带标注且是原始分辨率；放大镜、按 C / ⇧C 取色 |
| F 收尾 | Task 11 | 全部测试、干净编译、完整验收 |

每个批次结束，用户跑 `scripts/run.sh` 按该批次各任务的「手动检查」走一遍，通过后再开始下一批次。注意：批次 B、C、D 里画的标注**要到 Task 9 才会出现在复制 / 保存的结果里**，在此之前输出仍是只裁剪的原图，这是按顺序推进的预期现象。

---

## 批次 A：工具栏

### Task 1：Chrome 摆放（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/Geometry/OverlayLayout.swift`
- Test: `Core/Tests/GlimpseCoreTests/OverlayLayoutTests.swift`

工具栏、二级栏、尺寸标签、工具提示放在哪里是纯几何，先在 Core 里写好并测试。坐标都是屏幕本地点（左上角原点、y 向下），和 `Selection` 一样。规则见上面「实施前说明」第 2–4 条和第 19 条。可选的 `obstacle` 参数是不能碰的区域：刘海屏上是摄像头外壳那一块（没有刘海就传 nil）。摆放结果碰到它（含 4pt 边距）就当作「放不下」，和超出屏幕一样走回退（上方放不下 → 选区内部）；刘海旁边的位置不受影响。摆放结果取整到整点，避免半点导致文字和边缘发虚。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/OverlayLayoutTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct OverlayLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let toolbarSize = CGSize(width: 300, height: 40)
    let paletteSize = CGSize(width: 200, height: 30)
    let labelSize = CGSize(width: 80, height: 20)

    @Test func toolbarGoesBelowRightAligned() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 100, width: 400, height: 300), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 408, width: 300, height: 40), side: .below))
    }

    @Test func toolbarGoesAboveWhenNoRoomBelow() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 500, width: 400, height: 280), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 452, width: 300, height: 40), side: .above))
    }

    @Test func toolbarGoesInsideWhenNoRoomEitherSide() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: screen, screen: screen)
        #expect(p == .init(frame: CGRect(x: 692, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarStaysOnScreenHorizontally() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 0, y: 100, width: 100, height: 100), screen: screen)
        #expect(p.frame == CGRect(x: 4, y: 208, width: 300, height: 40))
    }

    @Test func paletteGoesAwayFromSelection() {
        let below = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 408, width: 300, height: 40), side: .below)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: below, screen: screen)
                == CGRect(x: 300, y: 456, width: 200, height: 30))
        let above = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 452, width: 300, height: 40), side: .above)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: above, screen: screen)
                == CGRect(x: 300, y: 414, width: 200, height: 30))
    }

    @Test func paletteFlipsWhenNoRoom() {
        let toolbar = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 750, width: 300, height: 40), side: .below)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen)
                == CGRect(x: 300, y: 712, width: 200, height: 30))
    }

    @Test func toolTipFacesTheSelection() {
        let button = CGRect(x: 400, y: 413, width: 30, height: 30)
        // Toolbar below the selection: the tooltip goes above the button, centred on it.
        #expect(OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: button, toolbarSide: .below, screen: screen)
                == CGRect(x: 380, y: 385, width: 70, height: 22))
        // Toolbar above the selection: below the button.
        #expect(OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: button, toolbarSide: .above, screen: screen)
                == CGRect(x: 380, y: 449, width: 70, height: 22))
    }

    @Test func toolTipFlipsAndStaysOnScreen() {
        // Button at the top-left corner: no room above, so below; shifted right to stay on screen.
        let r = OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: CGRect(x: 4, y: 4, width: 30, height: 30),
                                      toolbarSide: .inside, screen: screen)
        #expect(r == CGRect(x: 4, y: 40, width: 70, height: 22))
    }

    @Test func sizeLabelSitsAboveTopLeft() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 200, y: 100, width: 400, height: 300),
                                        screen: screen, avoiding: nil)
        #expect(r == CGRect(x: 200, y: 74, width: 80, height: 20))
    }

    @Test func sizeLabelMovesInsideAtTopEdge() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 200, y: 10, width: 400, height: 300),
                                        screen: screen, avoiding: nil)
        #expect(r == CGRect(x: 206, y: 16, width: 80, height: 20))
    }

    @Test func sizeLabelMovesInsideWhenToolbarCoversIt() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 500, y: 500, width: 100, height: 280),
                                        screen: screen, avoiding: CGRect(x: 300, y: 452, width: 300, height: 40))
        #expect(r == CGRect(x: 506, y: 506, width: 80, height: 20))
    }

    // A camera housing 100pt wide and 40pt tall, centred at the top of the screen.
    let notch = CGRect(x: 450, y: 0, width: 100, height: 40)

    @Test func toolbarFallsInsideWhenAboveWouldTouchTheNotch() {
        let selection = CGRect(x: 200, y: 60, width: 400, height: 740)
        #expect(OverlayLayout.toolbar(size: toolbarSize, selection: selection, screen: screen).side == .above)
        #expect(OverlayLayout.toolbar(size: toolbarSize, selection: selection, screen: screen, obstacle: notch)
                == .init(frame: CGRect(x: 292, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarStaysAboveWhenBesideTheNotch() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 700, y: 60, width: 200, height: 740),
                                      screen: screen, obstacle: notch)
        #expect(p == .init(frame: CGRect(x: 600, y: 12, width: 300, height: 40), side: .above))
    }

    @Test func paletteSkipsASideThatTouchesTheNotch() {
        let toolbar = OverlayLayout.ToolbarPosition(frame: CGRect(x: 440, y: 70, width: 300, height: 40), side: .above)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen)
                == CGRect(x: 440, y: 32, width: 200, height: 30))
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen, obstacle: notch)
                == CGRect(x: 440, y: 118, width: 200, height: 30))
    }

    @Test func sizeLabelMovesInsideWhenAboveWouldTouchTheNotch() {
        let selection = CGRect(x: 440, y: 50, width: 300, height: 300)
        #expect(OverlayLayout.sizeLabel(size: labelSize, selection: selection, screen: screen, avoiding: nil, obstacle: notch)
                == CGRect(x: 446, y: 56, width: 80, height: 20))
    }

    @Test func toolTipFlipsAwayFromTheNotch() {
        let button = CGRect(x: 460, y: 60, width: 30, height: 30)
        let size = CGSize(width: 70, height: 22)
        #expect(OverlayLayout.toolTip(size: size, button: button, toolbarSide: .below, screen: screen).origin
                == CGPoint(x: 440, y: 32))
        #expect(OverlayLayout.toolTip(size: size, button: button, toolbarSide: .below, screen: screen, obstacle: notch).origin
                == CGPoint(x: 440, y: 96))
    }

    @Test func toolbarInsideIsAlsoClampedHorizontally() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 0, y: 0, width: 100, height: 800), screen: screen)
        #expect(p == .init(frame: CGRect(x: 4, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarExactFitBelow() {
        // below = 748 + 8 = 756 and 756 + 40 == 796 == screen.maxY - margin
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 448, width: 400, height: 300), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 756, width: 300, height: 40), side: .below))
    }

    @Test func toolbarExactFitAbove() {
        // above = 52 - 8 - 40 = 4 == screen.minY + margin
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 52, width: 400, height: 748), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 4, width: 300, height: 40), side: .above))
    }

    @Test func toolTipStaysOnScreenAtTheRightEdge() {
        let r = OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: CGRect(x: 960, y: 413, width: 30, height: 30),
                                      toolbarSide: .below, screen: screen)
        #expect(r == CGRect(x: 926, y: 385, width: 70, height: 22))
    }

    @Test func toolTipLandsOnWholePoints() {
        // Centred on x = 415 with an odd width: 415 - 35.5 = 379.5 rounds to 380.
        let r = OverlayLayout.toolTip(size: CGSize(width: 71, height: 22), button: CGRect(x: 400, y: 413, width: 30, height: 30),
                                      toolbarSide: .below, screen: screen)
        #expect(r.origin == CGPoint(x: 380, y: 385))
    }

    @Test func sizeLabelWithToolbarInsideGoesInsideTopLeft() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: screen, screen: screen,
                                        avoiding: CGRect(x: 692, y: 752, width: 300, height: 40))
        #expect(r == CGRect(x: 6, y: 6, width: 80, height: 20))
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter OverlayLayoutTests`
Expected: 编译失败，`cannot find 'OverlayLayout' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Geometry/OverlayLayout.swift`：

```swift
import CoreGraphics

/// Where the editing chrome (toolbar, style palette, size label) goes around a selection.
/// Every rect is screen-local points (top-left origin, y down), like `Selection`.
/// `obstacle` is an area the chrome must stay out of: on a notch screen, the camera housing. Callers pass nil
/// when there is none. A placement that would touch it (with the usual margin) counts as "no room" and falls
/// back the same way a placement that leaves the screen does.
public enum OverlayLayout {
    /// Space between the selection and the toolbar, and between the toolbar and the style palette.
    public static let gap: CGFloat = 8
    /// Chrome keeps at least this far from every screen edge.
    public static let screenMargin: CGFloat = 4

    public struct ToolbarPosition: Equatable, Sendable {
        public enum Side: Equatable, Sendable { case below, above, inside }
        public let frame: CGRect
        public let side: Side

        public init(frame: CGRect, side: Side) {
            self.frame = frame
            self.side = side
        }
    }

    /// Below the selection; above it when there is no room below; inside its bottom edge as a last
    /// resort (design doc §3.2). Right-aligned with the selection so ✕ ✓ sit next to its right edge,
    /// then shifted sideways to stay on screen.
    public static func toolbar(size: CGSize, selection: CGRect, screen: CGRect, obstacle: CGRect? = nil) -> ToolbarPosition {
        let below = selection.maxY + gap
        let belowFrame = frame(x: selection.maxX - size.width, y: below, size: size, screen: screen)
        if below + size.height <= screen.maxY - screenMargin, isClear(belowFrame, of: obstacle) {
            return ToolbarPosition(frame: belowFrame, side: .below)
        }
        let above = selection.minY - gap - size.height
        let aboveFrame = frame(x: selection.maxX - size.width, y: above, size: size, screen: screen)
        if above >= screen.minY + screenMargin, isClear(aboveFrame, of: obstacle) {
            return ToolbarPosition(frame: aboveFrame, side: .above)
        }
        return ToolbarPosition(frame: frame(x: selection.maxX - gap - size.width,
                                            y: selection.maxY - gap - size.height, size: size, screen: screen),
                               side: .inside)
    }

    /// The colour / width palette goes on the side of the toolbar away from the selection (below a toolbar
    /// that is below or inside it, above a toolbar that is above it) and flips when that side has no room.
    /// Left-aligned with the toolbar, where the tool buttons are.
    public static func palette(size: CGSize, toolbar: ToolbarPosition, screen: CGRect, obstacle: CGRect? = nil) -> CGRect {
        let below = toolbar.frame.maxY + gap
        let above = toolbar.frame.minY - gap - size.height
        let fitsBelow = below + size.height <= screen.maxY - screenMargin
            && isClear(frame(x: toolbar.frame.minX, y: below, size: size, screen: screen), of: obstacle)
        let fitsAbove = above >= screen.minY + screenMargin
            && isClear(frame(x: toolbar.frame.minX, y: above, size: size, screen: screen), of: obstacle)
        let y: CGFloat
        switch toolbar.side {
        case .below, .inside: y = fitsBelow || !fitsAbove ? below : above
        case .above: y = fitsAbove || !fitsBelow ? above : below
        }
        return frame(x: toolbar.frame.minX, y: y, size: size, screen: screen)
    }

    /// Above the selection's top-left corner; inside it when there is no room above or when the toolbar
    /// (which may sit above the selection) would cover the label.
    public static func sizeLabel(size: CGSize, selection: CGRect, screen: CGRect, avoiding toolbar: CGRect?,
                                 obstacle: CGRect? = nil) -> CGRect {
        let above = frame(x: selection.minX, y: selection.minY - size.height - 6, size: size, screen: screen)
        let roomAbove = selection.minY - size.height - 6 >= screen.minY + screenMargin
        if roomAbove, isClear(above, of: obstacle), toolbar.map({ !$0.intersects(above) }) ?? true { return above }
        return frame(x: selection.minX + 6, y: selection.minY + 6, size: size, screen: screen)
    }

    /// A toolbar button's tooltip: centred on the button, on the toolbar's selection-facing side (the style
    /// palette may occupy the other side), flipped when that side has no room.
    public static func toolTip(size: CGSize, button: CGRect, toolbarSide: ToolbarPosition.Side, screen: CGRect,
                               obstacle: CGRect? = nil) -> CGRect {
        let above = button.minY - 6 - size.height
        let below = button.maxY + 6
        let x = button.midX - size.width / 2
        let fitsAbove = above >= screen.minY + screenMargin
            && isClear(frame(x: x, y: above, size: size, screen: screen), of: obstacle)
        let fitsBelow = below + size.height <= screen.maxY - screenMargin
            && isClear(frame(x: x, y: below, size: size, screen: screen), of: obstacle)
        let preferAbove = toolbarSide != .above
        let y = preferAbove ? (fitsAbove || !fitsBelow ? above : below) : (fitsBelow || !fitsAbove ? below : above)
        return frame(x: button.midX - size.width / 2, y: y, size: size, screen: screen)
    }

    /// True when `rect` stays `screenMargin` away from `obstacle` (or there is none).
    public static func isClear(_ rect: CGRect, of obstacle: CGRect?) -> Bool {
        guard let obstacle else { return true }
        return !rect.intersects(obstacle.insetBy(dx: -screenMargin, dy: -screenMargin))
    }

    /// A rect of `size` at (x, y) on whole points (so text and edges stay crisp), shifted to stay
    /// `screenMargin` inside `screen`.
    private static func frame(x: CGFloat, y: CGFloat, size: CGSize, screen: CGRect) -> CGRect {
        let cx = max(screen.minX + screenMargin, min(x.rounded(), screen.maxX - screenMargin - size.width))
        let cy = max(screen.minY + screenMargin, min(y.rounded(), screen.maxY - screenMargin - size.height))
        return CGRect(origin: CGPoint(x: cx, y: cy), size: size)
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter OverlayLayoutTests`
Expected: `Test run with 22 tests in 1 suite passed`

Run: `cd Core && swift test`
Expected: `Test run with 80 tests in 10 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 2：玻璃材质 + 工具栏 + 玻璃尺寸标签和工具提示

**Files:**
- Create: `App/Sources/Material/MaterialView.swift`
- Create: `App/Sources/Toolbar/ToolbarItem.swift`
- Create: `App/Sources/Toolbar/ToolbarButton.swift`
- Create: `App/Sources/Toolbar/ToolbarView.swift`
- Create: `App/Sources/Toolbar/ToolRollout.swift`
- Create: `App/Sources/Overlay/GlassLabelView.swift`
- Modify: `App/Sources/Overlay/OverlayContentView.swift`（整体替换）
- Modify: `App/Sources/Overlay/SelectionView.swift`（13 处替换）

本任务结束后，用户就能在真机上用工具栏：玻璃材质、贴着选区、跟随移动和缩放；✕ 退出、✓ 复制、保存按钮可用；工具按钮显示但置灰。

做法要点：
- 工具栏、尺寸标签都是覆盖层窗口（`.screenSaver` 层级的不抢前台面板）里的**子视图**，不另开窗口，不激活应用。
- 按钮 `refusesFirstResponder = true`：点按钮不会把键盘焦点从 `SelectionView` 抢走，Esc / Enter / 字母键照常。
- 工具栏按钮走和按键同一个入口 `SelectionView.perform(_:)`：✕ = `.exit`、✓ = `.finishCopy`、保存 = `.save`。
- `OverlayContentView` 改为翻转坐标（`isFlipped = true`），这样它的子视图 frame 也是屏幕本地坐标，可以直接用 `OverlayLayout` 的结果。冻结画面层和 `SelectionView` 都铺满整个视图，翻转对它们没有影响。
- `SelectionView` 通过新的 `SelectionViewChromeDelegate` 通知「选区或阶段变了」，`OverlayContentView` 据此重新摆放；鼠标在工具栏上时光标是箭头。
- 不做任何出现动画（§4.3，用户真机反馈：选择完之后 bar 应该立马出来）：选区一确定，`SelectionView` 在同一次鼠标松开里改 `phase`，`layoutChrome` 立即摆好并显示工具栏。
- 工具提示（§3.3「鼠标悬停显示名称和快捷键」）由覆盖层自己画，理由见「实施前说明」第 19 条：`ToolbarButton` 鼠标停留 0.6 秒后经 `ToolbarView` 通知 `OverlayContentView`，后者用一个 `GlassLabelView` 按 `OverlayLayout.toolTip` 摆放；移开、按下、工具栏移动时隐藏。按钮不设 AppKit 的 `toolTip`，避免万一两种提示同时出现。
- 置灰按钮只靠 `alphaValue = 0.35` 变淡；按钮单元格设 `imageDimsWhenDisabled = false`，避免 AppKit 再把图标暗一次。
- 刘海屏：`OverlayContentView.notchObstacle` 用 `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`（两者之间的空隙，高度取 `safeAreaInsets.top`，翻转坐标里 y 从 0 起；x 减去屏幕原点）算出摄像头外壳的矩形，作为 `obstacle` 传给工具栏、二级栏、尺寸标签、工具提示（Task 10 的放大镜同样）的摆放；两块区域为 nil（没有刘海）时没有障碍。`chromeArea` 是整屏。
- 悬停状态：工具栏移动或隐藏时鼠标没动，AppKit 不发 mouseExited（重建跟踪区域也不发）。`ToolbarButton.resetHover()` 清掉高亮并取消待触发的提示；`ToolbarView.resetHover()` 对所有按钮调用；`layoutChrome` 在工具栏隐藏或位置变化时调用并隐藏提示；`ToolbarButton.viewDidHide` 也清理；`updateTrackingAreas` 只移除自己建的跟踪区域（不动 NSButton 自带的）；新区域既不发 enter 也不发 exit，所以重建后手动处理：鼠标仍在按钮上（例如方向键微调把工具栏挪了 1pt）就恢复高亮并重新计时 0.6 秒，提示出现在新位置；鼠标已不在按钮上就结束悬停。
- 右键：工具栏上的右键会沿响应链冒泡到 `OverlayContentView`，到不了同级的 `SelectionView`，所以 `OverlayContentView.rightMouseDown` 转发给 `selectionView`（设计文档 §3.2：右键就是「重来」）。
- 按钮状态：`ToolbarView.update` 记住上次应用的状态，没变就直接返回（布局很频繁）；`ToolbarButton` 的 `isEnabled` / `isSelectedTool` / 悬停只在值变化时重刷颜色。
- `show(_:at:)` 只设 frame 并取消隐藏；「工具栏挪了位置」直接比较 `toolbar.frame` 和新位置。
- 毛玻璃回退（macOS 14 / 15）：`NSVisualEffectView` 用 `maskImage`（可拉伸的连续曲率圆角矩形，由一个 `cornerCurve = .continuous` 的 CALayer 按视图的实际尺寸整张画出，尺寸或圆角变了才重画；不用可拉伸的 `capInsets`，因为连续圆角的弯曲跨度约 1.53 倍半径，矮标签上超过半高，拉伸边距放不下）做圆角，不用 layer 的 `cornerRadius` + `masksToBounds`；macOS 26 的 `NSGlassEffectView` 仍用它自己的 `cornerRadius`。
- 材质装饰（设计文档 §4.1，对照视觉稿 `radius-v2.html` 的 `.glass`）：（已被 spec §3.2 / §4.1 取代，见文末「实施后修正」）两种玻璃上都叠淡色（macOS 26 用 `NSGlassEffectView.tintColor`，回退版在模糊层上面加一层底色）、1pt 渐变高光描边（160° 方向）+ 0.5pt 内描边、顶部反光（在 `contentView` 最底层，按钮画在它上面）、向下 10pt 的投影（`shadowPath` + 挖空形状的遮罩，只投在外面，不透进半透明的玻璃；挖空的形状比外形小 1pt，CGPath 的圆弧圆角和连续圆角之间那一点差落在 1pt 的高光描边下面）。装饰视图都是 `hitTest` 返回 nil 的 `DecorationView`，不影响按钮点击、悬停和右键转发。图层颜色是 CGColor，`viewDidChangeEffectiveAppearance` 时重新取；尺寸变化在 `setFrameSize` 里关掉隐式动画重排。翻转视图的图层是 y 向下的坐标，所以渐变端点照 CSS 算、投影偏移取 +10。
- 工具栏尺寸按视觉稿 `.tb`：上下 6pt、左右 8pt、按钮间距 2pt；分隔线是 `MaterialSeparatorView`（1 × 16pt，日间 15% 黑、夜间 18% 白），两侧再各空 5pt。选中按钮加强调色光晕。图标用 SF Symbols 13pt regular：视觉稿的 17px 是图标外框，框里的图形约 8–11pt、线宽约 1.2pt；SF Symbols regular 线宽约为字号的 0.09 倍，13pt 大小和线宽都最接近，17pt 大一半且更粗。macOS 26 上选中光晕可能被玻璃的内容区裁掉一部分（可以接受）；我们的高光和投影有意叠在液态玻璃上，和回退版保持一致。（已被 spec §3.2 / §4.1 取代，见文末「实施后修正」）
- 尺寸标签和工具提示按视觉稿 `.size`：11pt 中等字重，上下 4pt、左右 9pt，圆角取 12 和半高的较小值。

- [ ] **Step 1：MaterialView**

`App/Sources/Material/MaterialView.swift`：

```swift
import AppKit

/// The one material behind all Glimpse chrome (design doc §4.1): Liquid Glass (`NSGlassEffectView`)
/// on macOS 26+, frosted glass (`NSVisualEffectView`) on macOS 14 / 15, with the same continuous
/// corner radius on both. Callers add subviews to `contentView` and never see which one is in use.
/// Light / dark follows the window's effective appearance, which follows the system.
///
/// On top of the system material it draws what the chosen mockup has (`radius-v2.html`, `.glass`):
/// a light tint, a soft drop shadow, a 1pt specular rim and a 0.5pt inner hairline, and a sheen
/// across the top. None of them takes clicks. Bottom to top:
/// - `shadowView`: the drop shadow, outside the shape only (see `layoutDecorations`)
/// - the effect view, clipped to the corner radius; on macOS 14 / 15 it holds `tintView` under `contentView`
///   - `contentView`: `sheenView` first, so everything callers add draws above the sheen
/// - `rimView`: hairline and specular rim along the edge
class MaterialView: NSView {
    /// Flipped, like the overlay: subviews are laid out from the top-left.
    let contentView: NSView = FlippedView()

    /// The continuous corner radius of the glass and its rim and shadow. Labels set it as their height changes.
    var cornerRadius: CGFloat {
        didSet {
            if cornerRadius != oldValue { applyCornerRadius() }
        }
    }

    private let effect: NSView
    private let shadowView = DecorationView()
    private let tintView = DecorationView()
    private let sheenView = DecorationView()
    private let rimView = DecorationView()

    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let hairlineLayer = CALayer()
    private let rimLayer = CAGradientLayer()
    private let rimMask = CALayer()
    /// Size and radius the macOS 14 / 15 blur mask was drawn for; it is redrawn only when one changes.
    private var maskedShape: (size: CGSize, radius: CGFloat)?

    /// How far the shadow reaches past the shape: blur radius plus offset, with room to spare.
    private static let shadowReach: CGFloat = 50

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        if #available(macOS 26, *) {
            effect = NSGlassEffectView()
        } else {
            effect = NSVisualEffectView()
        }
        super.init(frame: .zero)
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.style = .regular
            glass.contentView = contentView
        } else if let visual = effect as? NSVisualEffectView {
            visual.material = .popover          // adapts to light / dark; .hudWindow is always dark
            visual.blendingMode = .withinWindow // blur the frozen screen in this window, not what is behind it
            visual.state = .active              // the overlay is never in the active app, so never look inactive
            visual.addSubview(tintView)         // NSGlassEffectView has tintColor; the blur needs a layer above it
            visual.addSubview(contentView)
            contentView.autoresizingMask = [.width, .height]
        }
        effect.autoresizingMask = [.width, .height]
        contentView.addSubview(sheenView)
        for view in [shadowView, effect, rimView] {
            addSubview(view)
        }

        shadowLayer.mask = shadowMask
        shadowMask.fillRule = .evenOdd
        shadowView.layer?.addSublayer(shadowLayer)
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.masksToBounds = true
        sheenLayer.cornerRadius = 6
        sheenLayer.cornerCurve = .continuous
        sheenView.layer?.addSublayer(sheenLayer)
        for layer in [hairlineLayer, rimMask] {
            layer.cornerCurve = .continuous
        }
        hairlineLayer.borderWidth = 0.5
        rimMask.borderWidth = 1
        rimMask.borderColor = NSColor.black.cgColor // a mask only uses alpha
        rimLayer.mask = rimMask
        rimLayer.locations = [0, 0.35, 0.6, 1]
        rimView.layer?.addSublayer(hairlineLayer)
        rimView.layer?.addSublayer(rimLayer)

        applyCornerRadius()
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Subclasses size themselves by setting `frame`; the decorations follow here.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutDecorations()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshColors() // the window's appearance may differ from the app's one seen in init
    }

    // MARK: - Shape

    private func applyCornerRadius() {
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
        layoutDecorations() // also rounds the macOS 14 / 15 blur, whose mask is drawn at the exact size
    }

    /// Sizes every decoration layer to the current bounds and corner radius. Done without implicit
    /// animations: added CALayers would otherwise ease into a new size for 0.25s.
    private func layoutDecorations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let size = bounds.size
        if let visual = effect as? NSVisualEffectView, size.width > 0, size.height > 0,
           maskedShape?.size != size || maskedShape?.radius != cornerRadius {
            maskedShape = (size, cornerRadius)
            visual.maskImage = Self.maskImage(size: size, cornerRadius: cornerRadius) // Apple's way to round it
        }
        for view in [shadowView, rimView] {
            view.frame = bounds
        }
        tintView.frame = CGRect(origin: .zero, size: size)
        tintView.layer?.cornerRadius = cornerRadius

        // Shadow: the rounded rect casts it, and the mask cuts the shape itself out, so the shadow never
        // darkens the see-through glass from below (CSS box-shadow is outside-only too). CGPath only has
        // circular corners, which differ from the continuous ones by a fraction of a point, so the cut-out
        // is 1pt smaller: its edge then lies under the 1pt rim instead of leaving a hairline gap at the corners.
        let corner = min(cornerRadius, size.width / 2, size.height / 2) // CGPath traps on a larger radius
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let reach = Self.shadowReach
        shadowMask.frame = bounds.insetBy(dx: -reach, dy: -reach)
        let inner = bounds.insetBy(dx: 1, dy: 1).offsetBy(dx: reach, dy: reach)
        let innerCorner = max(0, min(corner - 1, inner.width / 2, inner.height / 2))
        let cutOut = CGMutablePath()
        cutOut.addRect(shadowMask.bounds)
        if inner.width > 0, inner.height > 0 {
            cutOut.addRoundedRect(in: inner, cornerWidth: innerCorner, cornerHeight: innerCorner)
        }
        shadowMask.path = cutOut

        // Sheen: inset 12% left and right, 1pt from the top, 45% of the height (`.glass::after`).
        sheenView.frame = CGRect(x: size.width * 0.12, y: 1, width: size.width * 0.76, height: size.height * 0.45)
        sheenLayer.frame = sheenView.bounds

        for layer in [hairlineLayer, rimMask] as [CALayer] {
            layer.frame = bounds
            layer.cornerRadius = cornerRadius
        }
        rimLayer.frame = bounds
        (rimLayer.startPoint, rimLayer.endPoint) = Self.cssGradientPoints(degrees: 160, size: size)
    }

    /// Start and end of CSS `linear-gradient(<degrees>deg, …)` in a box of `size`, as unit points.
    /// CSS angles run clockwise from "to top", and the line is long enough that the corners land exactly
    /// on the first and last stop. The decoration views are flipped, so their layers' y runs down as in CSS.
    private static func cssGradientPoints(degrees: CGFloat, size: CGSize) -> (CGPoint, CGPoint) {
        guard size.width > 0, size.height > 0 else { return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)) }
        let angle = degrees * .pi / 180
        let direction = CGPoint(x: sin(angle), y: -cos(angle))
        let half = (abs(size.width * sin(angle)) + abs(size.height * cos(angle))) / 2
        let dx = direction.x * half / size.width
        let dy = direction.y * half / size.height
        return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    // MARK: - Colours

    /// Light and dark values from the mockup (`.L .glass` / `.D .glass`). Layer colours are CGColors and
    /// do not follow appearance changes on their own, so they are resolved again on every change.
    private func refreshColors() {
        let dark = effectiveAppearance.isDark
        let tint = dark ? NSColor(srgbRed: 40 / 255, green: 40 / 255, blue: 48 / 255, alpha: 0.32)
                        : NSColor(white: 1, alpha: 0.28)
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.tintColor = tint
        } else {
            tintView.layer?.backgroundColor = tint.cgColor
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Shadow: 0 10px 30px; a CSS blur of 30 is a Core Animation radius of about 15. +y is down: the
        // shadow view is flipped, and AppKit gives a flipped view's layer a y-down space.
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = dark ? 0.45 : 0.18
        shadowLayer.shadowRadius = 15
        shadowLayer.shadowOffset = CGSize(width: 0, height: 10)

        hairlineLayer.borderColor = NSColor(white: 1, alpha: dark ? 0.18 : 0.5).cgColor
        let rim: [CGFloat] = dark ? [0.55, 0.08, 0, 0.30] : [0.95, 0.15, 0, 0.55]
        rimLayer.colors = rim.map { NSColor(white: 1, alpha: $0).cgColor }
        let sheen: CGFloat = dark ? 0.12 : 0.35
        sheenLayer.colors = [NSColor(white: 1, alpha: sheen).cgColor, NSColor(white: 1, alpha: 0).cgColor]
    }

    // MARK: - Fallback mask

    /// The blur's shape at its exact size: a rounded rect with continuous corners, like the rim drawn over it.
    /// Drawn whole rather than as stretchable caps: a continuous corner bends over about 1.53 × the radius,
    /// which on a short label is more than half its height, so no cap insets would fit.
    private static func maskImage(size: CGSize, cornerRadius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shape = CALayer()
            shape.frame = rect
            shape.cornerRadius = cornerRadius
            shape.cornerCurve = .continuous
            shape.backgroundColor = NSColor.black.cgColor
            shape.render(in: context)
            return true
        }
    }
}

/// A plain container with a top-left origin.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A layer-backed view that only shows something and never takes a click: hit testing skips it, so clicks
/// and right clicks reach the buttons or the material underneath exactly as without it.
private final class DecorationView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The 1 × 16pt line between groups on the material (`.sep` in the mockup): 15% black in light,
/// 18% white in dark. Drawn, so AppKit resolves the colour again whenever the appearance changes.
final class MaterialSeparatorView: NSView {
    static let size = CGSize(width: 1, height: 16)
    private static let color = NSColor.adaptive(light: NSColor(white: 0, alpha: 0.15),
                                                dark: NSColor(white: 1, alpha: 0.18))

    init(origin: CGPoint) {
        super.init(frame: CGRect(origin: origin, size: Self.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        Self.color.setFill()
        bounds.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSAppearance {
    /// True for the dark appearances, including their high-contrast variants.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// A colour that AppKit resolves for the current appearance each time it draws with it.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }

    /// Icons and text on the material, from the mockup: near-black in light, near-white in dark.
    static let materialText = adaptive(light: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1),
                                       dark: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1))
}
```

- [ ] **Step 2：工具栏按钮清单**

`App/Sources/Toolbar/ToolbarItem.swift`：

```swift
import GlimpseCore

/// One toolbar button. Order and grouping follow design doc §3.3; P3 adds `.recognizeText` and
/// `.pin` in front of `.save` in the third group (识别文字 贴图 保存).
enum ToolbarItem: Hashable {
    case tool(Tool)
    case undo, redo
    case save
    case cancel, confirm

    /// Separators go between groups.
    static let groups: [[ToolbarItem]] = [
        Tool.allCases.map { .tool($0) },
        [.undo, .redo],
        [.save],
        [.cancel, .confirm],
    ]

    var symbolName: String {
        switch self {
        case .tool(.rectangle): "rectangle"
        case .tool(.ellipse): "circle"
        case .tool(.arrow): "arrow.up.right"
        case .tool(.pen): "pencil"
        case .tool(.text): "textformat"
        case .tool(.mosaic): "checkerboard.rectangle"
        case .tool(.counter): "1.circle"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .save: "square.and.arrow.down"
        case .cancel: "xmark"
        case .confirm: "checkmark"
        }
    }

    var title: String {
        switch self {
        case .tool(.rectangle): "矩形"
        case .tool(.ellipse): "椭圆"
        case .tool(.arrow): "箭头"
        case .tool(.pen): "画笔"
        case .tool(.text): "文字"
        case .tool(.mosaic): "马赛克"
        case .tool(.counter): "序号"
        case .undo: "撤销"
        case .redo: "重做"
        case .save: "保存"
        case .cancel: "取消"
        case .confirm: "完成"
        }
    }

    /// Shown in the tooltip next to the name (design doc §3.3).
    var shortcut: String {
        switch self {
        case .tool(let tool): tool.shortcut.uppercased()
        case .undo: "⌘Z"
        case .redo: "⇧⌘Z"
        case .save: "⌘S"
        case .cancel: "Esc"
        case .confirm: "↩"
        }
    }

    var toolTip: String { "\(title)（\(shortcut)）" }
}
```

SF Symbols 名称（`rectangle`、`circle`、`arrow.up.right`、`pencil`、`textformat`、`checkerboard.rectangle`、`1.circle`、`arrow.uturn.backward`、`arrow.uturn.forward`、`square.and.arrow.down`、`xmark`、`checkmark`）在 macOS 14 上都存在；万一某个取不到，`ToolbarButton` 会退回显示文字，不会出现空按钮。

- [ ] **Step 3：ToolbarButton**

`App/Sources/Toolbar/ToolbarButton.swift`：

```swift
import AppKit

/// A 30 × 30 icon button with an 8pt continuous corner (design doc §4.3). Selected: accent fill, white
/// icon and an accent glow (`.on` in the mockup). Never takes key focus, so keys keep going to the
/// selection view.
/// Its tooltip is drawn by the overlay (see `onHover`), not by AppKit: AppKit's tooltip window sits
/// below the `.screenSaver` overlay and would be hidden behind it.
final class ToolbarButton: NSButton {
    static let side: CGFloat = 30
    /// The mockup's 17pt is the icon box: the glyphs drawn in it are about 8–11pt with 1.2pt strokes.
    /// SF Symbols regular strokes are about 0.09 × the point size, and 13pt gives both the glyph size
    /// (rectangle 18 × 14 image) and the stroke (about 1.17pt); 17pt is half as big again and heavier.
    static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    private static let cornerRadius: CGFloat = 8

    let item: ToolbarItem
    /// True once the mouse has rested on the button for `hoverDelay`; false when it leaves or presses.
    var onHover: ((ToolbarButton, Bool) -> Void)?
    private static let hoverDelay: TimeInterval = 0.6

    var isSelectedTool = false {
        didSet {
            if isSelectedTool != oldValue { refreshColors() }
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            alphaValue = isEnabled ? 1 : 0.35
            refreshColors()
        }
    }

    private var isHovered = false {
        didSet {
            if isHovered != oldValue { refreshColors() }
        }
    }

    /// Our own tracking area; NSButton keeps others that must not be removed.
    private var hoverArea: NSTrackingArea?

    init(item: ToolbarItem, target: AnyObject, action: Selector) {
        self.item = item
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        (cell as? NSButtonCell)?.imageDimsWhenDisabled = false // disabled look comes from alphaValue alone
        image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)?
            .withSymbolConfiguration(Self.symbolConfiguration)
        if image == nil { title = item.title } // unknown symbol name: still a usable button
        setAccessibilityLabel(item.toolTip)
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        // The glow is the rounded box's shadow, not the icon's.
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                                   transform: nil)
        self.target = target
        self.action = action
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
        // A new area sends neither an exit nor an enter event, so settle the hover by hand: the mouse is on
        // the button's new position (a nudge moved the toolbar by a point) -> keep hovering and show the
        // tooltip again at the new spot; the button moved away from the mouse -> end the hover.
        guard let window else { return }
        if bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            if !isHidden { beginHover() }
        } else {
            resetHover()
        }
    }

    /// Forgets any hover: clears the highlight and cancels a pending tooltip. Called when the toolbar moves
    /// or hides under a mouse that did not move, which produces no exit event.
    func resetHover() {
        isHovered = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
    }

    override func viewDidHide() {
        super.viewDidHide()
        resetHover()
    }

    override func mouseEntered(with event: NSEvent) {
        beginHover()
    }

    /// Highlights the button and starts the tooltip timer (restarting it if one is pending).
    private func beginHover() {
        isHovered = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
        perform(#selector(hoverDelayElapsed), with: nil, afterDelay: Self.hoverDelay)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        endHover()
    }

    override func mouseDown(with event: NSEvent) {
        endHover() // pressing hides the tooltip, as in AppKit
        super.mouseDown(with: event)
    }

    @objc private func hoverDelayElapsed() {
        onHover?(self, true)
    }

    private func endHover() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
        onHover?(self, false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    /// Layer colours are CGColors and do not follow appearance changes on their own; resolve them here.
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill: NSColor?
            if isSelectedTool {
                fill = .controlAccentColor
            } else if isHovered && isEnabled {
                fill = NSColor.labelColor.withAlphaComponent(0.12)
            } else {
                fill = nil
            }
            layer?.backgroundColor = fill?.cgColor
            // Glow under the selected button: 0 2px 8px at 45% in light, 0 2px 10px at 60% in dark.
            // AppKit gives a flipped view's layer a y-down space, so the offset's sign follows isFlipped.
            let dark = effectiveAppearance.isDark
            layer?.shadowColor = NSColor.controlAccentColor.cgColor
            layer?.shadowOpacity = isSelectedTool ? (dark ? 0.6 : 0.45) : 0
            layer?.shadowRadius = dark ? 5 : 4
            layer?.shadowOffset = CGSize(width: 0, height: isFlipped ? 2 : -2)
            if isSelectedTool {
                contentTintColor = .white
            } else {
                contentTintColor = item == .confirm ? .controlAccentColor : .materialText
            }
        }
    }
}
```

- [ ] **Step 4：ToolbarView 和 ToolRollout**

`App/Sources/Toolbar/ToolbarView.swift`：

```swift
import AppKit
import GlimpseCore

@MainActor
protocol ToolbarViewDelegate: AnyObject {
    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem)
    /// Show the tooltip for `item` next to `buttonFrame` (in the toolbar's coordinates), or hide it (nil).
    func toolbarView(_ view: ToolbarView, showToolTipFor item: ToolbarItem?, buttonFrame: CGRect)
}

/// The editing toolbar (design doc §3.3): one row of 30pt buttons on the material, groups split
/// by separators. Sizes itself in `init`; the overlay only positions it.
/// Metrics follow the mockup's `.tb`: 6pt above and below, 8pt at the ends, 2pt between items,
/// and 5pt more on each side of a separator.
final class ToolbarView: MaterialView {
    weak var delegate: ToolbarViewDelegate?

    private static let verticalPadding: CGFloat = 6
    private static let horizontalPadding: CGFloat = 8
    private static let spacing: CGFloat = 2
    private static let separatorMargin: CGFloat = 5

    private var buttons: [ToolbarItem: ToolbarButton] = [:]

    private struct State: Equatable {
        let selectedTool: Tool?
        let canUndo: Bool
        let canRedo: Bool
    }
    private var appliedState: State?

    init() {
        super.init(cornerRadius: 12)
        let height = ToolbarButton.side + Self.verticalPadding * 2
        var x = Self.horizontalPadding
        for (index, group) in ToolbarItem.groups.enumerated() {
            if index > 0 {
                let separator = MaterialSeparatorView(origin: CGPoint(
                    x: x + Self.separatorMargin, y: (height - MaterialSeparatorView.size.height) / 2))
                contentView.addSubview(separator)
                x += Self.separatorMargin * 2 + MaterialSeparatorView.size.width + Self.spacing
            }
            for item in group {
                let button = ToolbarButton(item: item, target: self, action: #selector(buttonPressed(_:)))
                button.onHover = { [weak self] button, hovering in self?.hoverChanged(button, hovering: hovering) }
                button.frame.origin = CGPoint(x: x, y: Self.verticalPadding)
                contentView.addSubview(button)
                buttons[item] = button
                x += ToolbarButton.side + Self.spacing
            }
        }
        x -= Self.spacing
        frame.size = CGSize(width: x + Self.horizontalPadding, height: height)
        update(selectedTool: nil, canUndo: false, canRedo: false)
    }

    /// Selected tool, undo / redo availability, and which tools are usable yet (see ToolRollout).
    func update(selectedTool: Tool?, canUndo: Bool, canRedo: Bool) {
        let state = State(selectedTool: selectedTool, canUndo: canUndo, canRedo: canRedo)
        guard state != appliedState else { return } // layout runs often; the buttons rarely change
        appliedState = state
        for tool in Tool.allCases {
            buttons[.tool(tool)]?.isEnabled = ToolRollout.enabled.contains(tool)
            buttons[.tool(tool)]?.isSelectedTool = tool == selectedTool
        }
        buttons[.undo]?.isEnabled = canUndo
        buttons[.redo]?.isEnabled = canRedo
    }

    /// The toolbar moved or hid without the mouse moving: drop every hover and pending tooltip.
    func resetHover() {
        buttons.values.forEach { $0.resetHover() }
    }

    private func hoverChanged(_ button: ToolbarButton, hovering: Bool) {
        delegate?.toolbarView(self, showToolTipFor: hovering ? button.item : nil,
                              buttonFrame: convert(button.frame, from: contentView))
    }

    @objc private func buttonPressed(_ sender: ToolbarButton) {
        delegate?.toolbarView(self, didPress: sender.item)
    }
}
```

`App/Sources/Toolbar/ToolRollout.swift`：

```swift
import GlimpseCore

/// Tools whose behaviour has landed. The toolbar shows every tool from the start (design doc §3.3)
/// but disables the rest, and their letter keys do nothing. Each tool task adds its tool here;
/// Task 8 deletes this file once all seven exist.
enum ToolRollout {
    static let enabled: Set<Tool> = []
}
```

- [ ] **Step 5：GlassLabelView（尺寸标签和工具提示共用）**

`App/Sources/Overlay/GlassLabelView.swift`：

```swift
import AppKit

/// One line of text on the shared material: the selection's pixel size (replaces P1's temporary dark
/// label) and the toolbar's tooltips. Clicks pass through it to the selection view underneath.
/// Metrics follow the mockup's `.size`: 4pt above and below the text, 9pt at the ends, and the toolbar's
/// 12pt corner, which on a label this short makes it nearly a capsule.
final class GlassLabelView: MaterialView {
    private static let verticalPadding: CGFloat = 4
    private static let horizontalPadding: CGFloat = 9
    private static let maxCornerRadius: CGFloat = 12

    private let label = NSTextField(labelWithString: "")

    init(font: NSFont) {
        super.init(cornerRadius: Self.maxCornerRadius)
        label.font = font
        label.textColor = .materialText
        contentView.addSubview(label)
    }

    /// Updates the text and resizes to fit it.
    func setText(_ text: String) {
        label.stringValue = text
        let size = label.intrinsicContentSize
        let width = ceil(size.width), height = ceil(size.height)
        label.frame = CGRect(x: Self.horizontalPadding, y: Self.verticalPadding, width: width, height: height)
        frame.size = CGSize(width: width + Self.horizontalPadding * 2, height: height + Self.verticalPadding * 2)
        cornerRadius = min(Self.maxCornerRadius, frame.height / 2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
```

- [ ] **Step 6：OverlayContentView 整体替换**

`App/Sources/Overlay/OverlayContentView.swift`：

```swift
import AppKit
import GlimpseCore

/// One screen's overlay, bottom to top:
/// - a plain layer-backed view whose layer shows the frozen CGImage directly (no NSImage redraws)
/// - SelectionView: dim, selection, handles, and all mouse / keyboard input
/// - the chrome on the shared material: size label, toolbar, toolbar tooltip
/// Flipped, so every frame here is screen-local points like the selection.
final class OverlayContentView: NSView {
    let selectionView: SelectionView

    private let captured: CapturedScreen
    private let toolbar = ToolbarView()
    private let sizeLabel = GlassLabelView(font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
    /// Toolbar tooltips are drawn here: AppKit's tooltip window would sit behind the `.screenSaver` overlay.
    private let toolTipLabel = GlassLabelView(font: .systemFont(ofSize: 11, weight: .medium))
    private var toolbarSide: OverlayLayout.ToolbarPosition.Side = .below

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        self.captured = captured
        let frame = CGRect(origin: .zero, size: captured.info.frame.size)
        selectionView = SelectionView(frame: frame, captured: captured, windows: windows,
                                      primaryScreenHeight: primaryScreenHeight)
        super.init(frame: frame)

        let imageView = NSView(frame: frame)
        imageView.wantsLayer = true
        imageView.layer?.contents = captured.image
        imageView.layer?.contentsGravity = .resize
        imageView.autoresizingMask = [.width, .height]
        selectionView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        addSubview(selectionView)

        for chrome in [sizeLabel, toolbar, toolTipLabel] as [NSView] {
            chrome.isHidden = true
            addSubview(chrome)
        }
        toolbar.delegate = self
        selectionView.chromeDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// A right click on the toolbar's padding or buttons bubbles up to here, not to the sibling selection
    /// view: forward it so it still means "start over" (design doc §3.2).
    override func rightMouseDown(with event: NSEvent) {
        selectionView.rightMouseDown(with: event)
    }

    // MARK: - Chrome layout

    /// Puts the size label and toolbar around the current selection (design doc §3.2, §3.3).
    private func layoutChrome() {
        guard let rect = selectionView.selectionRect else {
            hideToolbar()
            sizeLabel.isHidden = true
            return
        }
        let screen = chromeArea
        var toolbarFrame: CGRect?
        if case .selecting = selectionView.phase {
            hideToolbar() // still dragging out the selection
        } else {
            let position = OverlayLayout.toolbar(size: toolbar.frame.size, selection: rect, screen: screen,
                                                     obstacle: notchObstacle)
            if toolbar.isHidden || toolbar.frame != position.frame {
                // Moving under a stationary mouse sends no exit event: drop stale hover and tooltip by hand.
                toolbar.resetHover()
                toolTipLabel.isHidden = true
            }
            show(toolbar, at: position.frame)
            toolbarFrame = position.frame
            toolbarSide = position.side
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: rect, scale: captured.info.scale)
        sizeLabel.setText("\(Int(pixels.width)) × \(Int(pixels.height))")
        sizeLabel.frame = OverlayLayout.sizeLabel(size: sizeLabel.frame.size, selection: rect, screen: screen,
                                                  avoiding: toolbarFrame, obstacle: notchObstacle)
        sizeLabel.isHidden = false
    }

    /// Chrome may use the whole screen except the camera housing (`notchObstacle`).
    private var chromeArea: CGRect { CGRect(origin: .zero, size: bounds.size) }

    /// The camera housing in this view's flipped local coordinates: the gap between the two top areas the
    /// system leaves usable, as tall as the top safe-area inset. nil on screens without a notch.
    private var notchObstacle: CGRect? {
        let screen = captured.nsScreen
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        // The areas are in global screen coordinates; subtract the screen's origin (they are already local
        // when that origin is 0, or when a system reports them relative to the screen).
        let originX = abs(left.minX - screen.frame.minX) < 1 ? screen.frame.minX : 0
        return CGRect(x: left.maxX - originX, y: 0, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private func hideToolbar() {
        toolbar.isHidden = true
        toolbar.resetHover()
        toolTipLabel.isHidden = true
    }

    /// Puts a chrome view at `frame` and shows it at once: the toolbar is there the moment the selection is
    /// made, with no fade or slide (design doc §4.3).
    private func show(_ view: NSView, at frame: CGRect) {
        view.frame = frame
        view.isHidden = false
    }
}

extension OverlayContentView: SelectionViewChromeDelegate {
    func selectionViewDidChangeLayout(_ view: SelectionView) {
        layoutChrome()
        toolbar.update(selectedTool: nil, canUndo: false, canRedo: false)
    }

    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool {
        !toolbar.isHidden && toolbar.frame.contains(point)
    }
}

extension OverlayContentView: ToolbarViewDelegate {
    /// Name and shortcut after a short hover (design doc §3.3), on the material like the rest of the chrome.
    func toolbarView(_ view: ToolbarView, showToolTipFor item: ToolbarItem?, buttonFrame: CGRect) {
        guard let item, !toolbar.isHidden else {
            toolTipLabel.isHidden = true
            return
        }
        toolTipLabel.setText(item.toolTip)
        toolTipLabel.frame = OverlayLayout.toolTip(size: toolTipLabel.frame.size, button: convert(buttonFrame, from: toolbar),
                                                   toolbarSide: toolbarSide, screen: chromeArea,
                                                   obstacle: notchObstacle)
        toolTipLabel.isHidden = false
    }

    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem) {
        switch item {
        case .tool, .undo, .redo:
            break // tools arrive with their tasks; ToolRollout keeps those buttons disabled until then
        case .save:
            selectionView.perform(.save)
        case .cancel:
            selectionView.perform(.exit)
        case .confirm:
            selectionView.perform(.finishCopy)
        }
    }
}
```

- [ ] **Step 7：修改 SelectionView**

在 `App/Sources/Overlay/SelectionView.swift` 里按顺序做下面 13 处替换（每段原文在文件里只出现一次）。作用：新增 `SelectionViewChromeDelegate`；`phase` 变化和每次 `refreshDisplay()` 都通知 chrome 重新摆放；对外提供 `selectionRect`；`perform(_:)` 改为对内对外都能调用；鼠标在工具栏上时光标为箭头；删掉 P1 的临时深色尺寸标签（改由 `GlassLabelView` 显示）。

（1）把

```swift
    func selectionViewDidRightClick(_ view: SelectionView)
}
```

替换为

```swift
    func selectionViewDidRightClick(_ view: SelectionView)
}

/// The overlay's chrome (toolbar, size label) follows the selection through this delegate.
@MainActor
protocol SelectionViewChromeDelegate: AnyObject {
    /// The selection rect or the phase changed: reposition the chrome.
    func selectionViewDidChangeLayout(_ view: SelectionView)
    /// True over the toolbar, where the cursor is the arrow.
    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool
}
```

（2）把

```swift
/// Draws the dim, window highlight, selection, handles and size label for one screen,
/// and turns mouse/keyboard input into selection changes.
```

替换为

```swift
/// Draws the dim, window highlight, selection and handles for one screen,
/// and turns mouse/keyboard input into selection changes.
```

（3）把

```swift
    weak var delegate: SelectionViewDelegate?
```

替换为

```swift
    weak var delegate: SelectionViewDelegate?
    weak var chromeDelegate: SelectionViewChromeDelegate?
```

（4）把

```swift
    private(set) var phase: EditorPhase = .selecting
```

替换为

```swift
    private(set) var phase: EditorPhase = .selecting {
        didSet {
            if phase != oldValue { chromeDelegate?.selectionViewDidChangeLayout(self) }
        }
    }
```

（5）把

```swift
    var hasSelection: Bool { selection != nil }
```

替换为

```swift
    var hasSelection: Bool { selection != nil }
    var selectionRect: CGRect? { selection?.rect }
```

（6）把

```swift
        if !dirty.isNull { setNeedsDisplay(dirty.intersection(bounds)) }
    }
```

替换为

```swift
        if !dirty.isNull { setNeedsDisplay(dirty.intersection(bounds)) }
        chromeDelegate?.selectionViewDidChangeLayout(self)
    }
```

（7）把

```swift
    /// Invalidates only the area that changed: the previous and the new extent of the clear rect,
    /// border, handles and size label.
```

替换为

```swift
    /// Invalidates only the area that changed: the previous and the new extent of the clear rect,
    /// border and handles.
```

（8）把

```swift
        guard let clear = selection?.rect ?? hoveredRect else { return .null }
        var extent = clear.insetBy(dx: -10, dy: -10)
        if let selection { extent = extent.union(labelFrame(for: selection.rect).insetBy(dx: -2, dy: -2)) }
        return extent
```

替换为

```swift
        guard let clear = selection?.rect ?? hoveredRect else { return .null }
        return clear.insetBy(dx: -10, dy: -10)
```

（9）把

```swift
    private func perform(_ action: EditorAction) {
```

替换为

```swift
    /// Keys and toolbar buttons both end up here.
    func perform(_ action: EditorAction) {
```

（10）把

```swift
    private func updateCursor(at point: CGPoint) {
        guard case .editing(let tool) = phase, let selection else {
```

替换为

```swift
    private func updateCursor(at point: CGPoint) {
        if chromeDelegate?.selectionView(self, isChromeAt: point) == true {
            NSCursor.arrow.set()
            return
        }
        guard case .editing(let tool) = phase, let selection else {
```

（11）把

```swift
        guard let selection else { return }
        drawSizeLabel(for: selection.rect)
        if case .editing = phase {
```

替换为

```swift
        guard let selection else { return }
        if case .editing = phase {
```

（12）把

```swift

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func labelText(for rect: CGRect) -> NSString {
        let pixels = CoordinateSpace.pixelRect(fromLocal: rect, scale: captured.info.scale)
        return "\(Int(pixels.width)) × \(Int(pixels.height))" as NSString
    }

    /// Above the selection when there is room, otherwise inside its top-left; always fully on screen.
    private func labelFrame(for rect: CGRect) -> CGRect {
        let size = labelText(for: rect).size(withAttributes: Self.labelAttributes)
        let width = size.width + 14, height = size.height + 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - height - 6)
        if origin.y < 4 { origin = CGPoint(x: rect.minX + 6, y: rect.minY + 6) }
        origin.x = max(4, min(origin.x, bounds.maxX - width - 4))
        origin.y = max(4, min(origin.y, bounds.maxY - height - 4))
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    /// Temporary dark label; P2 restyles it with the glass material.
    private func drawSizeLabel(for rect: CGRect) {
        let background = labelFrame(for: rect)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        labelText(for: rect).draw(at: CGPoint(x: background.minX + 7, y: background.minY + 3),
                                  withAttributes: Self.labelAttributes)
    }
}
```

替换为

```swift
}
```

（13）把

```swift
    /// What was last drawn outside the dim (border, handles, label); the next redraw covers old ∪ new.
```

替换为

```swift
    /// What was last drawn outside the dim (border, handles); the next redraw covers old ∪ new.
```

- [ ] **Step 8：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行输出 `build/Build/Products/Debug/Glimpse.app`。开发者证书被吊销期间 stderr 会有 `warning: … signing ad-hoc …`，属于正常。

Run: `cd Core && swift test`
Expected: `Test run with 80 tests in 10 suites passed`（本任务没有改 Core）

- [ ] **Step 9：手动检查（用户在真机上做）**

Run: `cd . && scripts/run.sh`，按 ⌘⇧A 后：
- 拖出一个选区松手：松手的同时选区下方出现工具栏（没有淡入、没有上移），右边缘和选区右边缘对齐；单击选中窗口 / 整屏同样立即出现
- 工具栏从左到右：矩形 椭圆 箭头 画笔 文字 马赛克 序号 │ 撤销 重做 │ 保存 │ ✕ ✓；分隔线位置对；没有「识别文字」「贴图」
- 工具按钮、撤销、重做都是灰的，点了没反应；按 R / O / A / P / T / M / N 也没反应
- 悬停时按钮有浅色底；停约 0.6 秒，按钮旁出现玻璃小标签，例如「矩形（R）」「保存（⌘S）」「完成（↩）」：工具栏在选区下方时标签在按钮上方，工具栏在选区上方时在按钮下方；移开或点按钮立即消失；置灰的按钮也有提示
- 不会同时出现系统自带的黄色 / 灰色提示框
- 置灰按钮只是变淡一次，图标没有比正常按钮暗两层
- 在 macOS 26 上工具栏是液态玻璃，圆角 12pt、按钮圆角 8pt；后面的冻结画面透过来有折射 / 模糊感。（如有 macOS 14 / 15 的机器：是毛玻璃，圆角和布局一样）
- 对照视觉稿 `radius-v2.html`「中等圆角」一行：工具栏边缘有一圈细高光（左上最亮、中段淡出、右下再亮一点），顶部有一道淡淡的反光（在按钮下面），下方有柔和投影（投影落在工具栏下方，不在上方，也不让玻璃本身变暗）；分隔线是短竖线，选中的工具按钮有强调色光晕；图标大小和线条粗细与视觉稿接近
- 系统切到深色外观后再截一次：玻璃偏深、图标变浅；切回浅色：玻璃偏白、图标深色。✓ 图标是系统强调色
- 拖动选区内部、拖手柄缩放、按方向键微调：工具栏实时跟着走
- 选区贴近屏幕底部：工具栏跑到选区上方；整屏选区（空格）：工具栏在选区内部右下角
- 选区贴近屏幕左边且很窄：工具栏不出屏幕，离左边约 4pt
- 尺寸标签变成同样的玻璃材质，文字跟随日夜间；工具栏在选区上方且挡住标签时，标签移进选区左上角里面；在标签上按下拖动，照样能移动选区（标签不挡鼠标）
- 鼠标移到工具栏上光标变成箭头；移回选区内是手形
- 点 ✓：覆盖层关闭，剪贴板里是选区图片（同 P1 的 Enter）
- 点保存：`~/Downloads` 出现 PNG，剪贴板里也有（同 P1 的 ⌘S）
- 点 ✕：直接退出
- 点按钮之后按 Esc / Enter / 方向键：照常生效（键盘焦点没被按钮抢走）
- 两块屏幕时：只有有选区的那块屏上有工具栏；到另一块屏上单击改选后，工具栏跟着搬过去

- [ ] **Step 10：停下，不 commit**

**批次 A 检查点：** 用户按 Task 2 的手动检查确认工具栏可用，再进入批次 B。

---

## 批次 B：标注模型 + 矩形 / 椭圆 / 箭头

### Task 3：标注模型、撤销栈、样式记忆（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/Annotation/AnnotationStyle.swift`
- Create: `Core/Sources/GlimpseCore/Annotation/TextLayout.swift`
- Create: `Core/Sources/GlimpseCore/Annotation/Annotation.swift`
- Create: `Core/Sources/GlimpseCore/Annotation/AnnotationDocument.swift`
- Create: `Core/Sources/GlimpseCore/Settings/AnnotationStyleStore.swift`
- Test: `Core/Tests/GlimpseCoreTests/AnnotationModelTests.swift`
- Test: `Core/Tests/GlimpseCoreTests/AnnotationStyleStoreTests.swift`

要点：
- `Annotation` 的所有坐标和尺寸都是**所在屏冻结画面的像素**（左上角原点），不相对选区；所以移动 / 缩放选区不影响标注（§5.2）。`size` 按形状解释为线宽、笔刷直径、序号圆直径或字号。
- 标注画完就不再编辑（§1「明确不做」），所以撤销栈就是「标注列表 + 被撤销的列表」，每次加一个标注是一步。
- `bounds` 用于界面只重绘变化的区域。文字的 `bounds` 需要量文字宽度，所以 `TextLayout` 在本任务一起加（Task 6 序号用粗体、Task 8 文字绘制都会用到它）。
- 类型都是值类型且 `Sendable`；`AnnotationStyleStore` 和 `SettingsStore` 一样只包一个线程安全的 `UserDefaults`。颜色和粗细档所有工具共用一份（第 6 条），所以 store 只有一个 `style` 属性、一个键。`AnnotationStyle` 逐字段解码：某个字段读不出来（比如以后版本存的新颜色名）只让这一项回到默认值，另一项保留（有测试）。
- `StrokeWidth` 按名字（`thin` / `medium` / `thick`）存，不按 0 / 1 / 2 存；查各工具尺寸表用 `index`，不用 `rawValue`。
- `prefersDarkText` 的亮度阈值是 0.7：6 个预设色里只有黄色（以及夜间的白色）用黑字，橙色（亮度约 0.64）仍用白字（第 11 条）。
- 标注的 `bounds` 每次重绘都会算，文字要量宽度；`TextLayout.font` 按（字号、粗细）缓存字体（加锁的字典，Swift 6 下线程安全）。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/AnnotationModelTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

private func counter(_ number: Int) -> Annotation {
    Annotation(shape: .counter(center: CGPoint(x: 10, y: 10), number: number), color: RGBA(hex: 0xFF3B30), size: 40)
}

private let red = RGBA(hex: 0xFF3B30)

struct AnnotationStyleTests {
    @Test func paletteOrder() {
        #expect(PaletteColor.allCases == [.red, .orange, .yellow, .green, .blue, .black])
    }

    @Test func blackTurnsWhiteInDarkAppearance() {
        #expect(PaletteColor.black.rgba(darkAppearance: false) == RGBA(red: 0, green: 0, blue: 0))
        #expect(PaletteColor.black.rgba(darkAppearance: true) == RGBA(red: 1, green: 1, blue: 1))
        #expect(PaletteColor.red.rgba(darkAppearance: true) == PaletteColor.red.rgba(darkAppearance: false))
    }

    @Test func widthLevelsPerTool() {
        #expect(Tool.rectangle.size(for: .thin) == 2)
        #expect(Tool.pen.size(for: .thick) == 6)
        #expect(Tool.text.size(for: .medium) == 20)
        #expect(Tool.mosaic.size(for: .thick) == 40)
        #expect(Tool.counter.size(for: .thin) == 20)
    }

    @Test func onlyYellowAndWhitePreferDarkText() {
        let dark = PaletteColor.allCases.filter { $0.rgba(darkAppearance: false).prefersDarkText }
        #expect(dark == [.yellow]) // red, orange, green, blue and black keep white text
        #expect(PaletteColor.black.rgba(darkAppearance: true).prefersDarkText) // black drawn as white
    }
}

struct AnnotationDocumentTests {
    @Test func undoAndRedo() {
        var doc = AnnotationDocument()
        #expect(!doc.canUndo && !doc.canRedo)
        doc.add(counter(1))
        doc.add(counter(2))
        #expect(doc.undo() == counter(2))
        #expect(doc.annotations == [counter(1)])
        #expect(doc.canRedo)
        #expect(doc.redo() == counter(2))
        #expect(doc.annotations == [counter(1), counter(2)])
        #expect(!doc.canRedo)
    }

    @Test func undoAndRedoOnAnEmptyDocumentDoNothing() {
        var doc = AnnotationDocument()
        #expect(doc.undo() == nil)
        #expect(doc.redo() == nil)
        #expect(doc.annotations.isEmpty)
    }

    @Test func addingAfterUndoDropsRedo() {
        var doc = AnnotationDocument()
        doc.add(counter(1))
        doc.undo()
        doc.add(counter(1))
        #expect(!doc.canRedo)
        #expect(doc.redo() == nil)
    }

    @Test func counterNumberRollsBackOnUndo() {
        var doc = AnnotationDocument()
        #expect(doc.nextCounterNumber == 1)
        doc.add(counter(doc.nextCounterNumber))
        doc.add(Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 5, height: 5)), color: red, size: 4))
        doc.add(counter(doc.nextCounterNumber))
        #expect(doc.nextCounterNumber == 3)
        doc.undo()
        #expect(doc.nextCounterNumber == 2)
        doc.redo()
        #expect(doc.nextCounterNumber == 3)
    }

    @Test func removeAllClearsUndoAndRedo() {
        var doc = AnnotationDocument()
        doc.add(counter(1))
        doc.add(counter(2))
        doc.undo()
        doc.removeAll()
        #expect(doc.annotations.isEmpty)
        #expect(!doc.canUndo && !doc.canRedo)
    }
}

struct AnnotationBoundsTests {
    @Test func rectangleBoundsCoverTheStroke() {
        let a = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)), color: red, size: 4)
        #expect(a.bounds == CGRect(x: 7, y: 7, width: 106, height: 56))
    }

    @Test func arrowBoundsCoverTheHead() {
        // Width 10: the head's half-width (22) is the widest part, plus a pixel.
        let a = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: red, size: 10)
        #expect(a.bounds == CGRect(x: -23, y: -23, width: 146, height: 46))
    }

    @Test func textBoundsGrowByOneLineHeightPerLine() {
        let one = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi"), color: red, size: 40)
        let two = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi\nthere"), color: red, size: 40)
        #expect(one.bounds.origin == CGPoint(x: 9, y: 19))
        #expect(two.bounds.height - one.bounds.height == TextLayout.lineHeight(fontSize: 40))
        #expect(two.bounds.width > one.bounds.width)
    }
}
```

`Core/Tests/GlimpseCoreTests/AnnotationStyleStoreTests.swift`：

```swift
import Foundation
import Testing
@testable import GlimpseCore

struct AnnotationStyleStoreTests {
    /// Runs `body` with a throwaway suite, removing its plist afterwards.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "glimpse-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func startsRedMedium() {
        withDefaults { defaults in
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .red, width: .medium))
        }
    }

    @Test func styleIsRememberedAcrossInstances() {
        withDefaults { defaults in
            AnnotationStyleStore(defaults: defaults).style = AnnotationStyle(color: .blue, width: .thick)
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .blue, width: .thick))
        }
    }

    @Test func corruptValueFallsBackToTheStandardStyle() {
        withDefaults { defaults in
            defaults.set(Data([0xFF]), forKey: AnnotationStyleStore.key)
            #expect(AnnotationStyleStore(defaults: defaults).style == .standard)
        }
    }

    @Test func anUnreadableFieldKeepsTheOther() {
        withDefaults { defaults in
            // A colour this version does not know (say, from a later one): only the colour falls back.
            defaults.set(Data(#"{"color":"purple","width":"thick"}"#.utf8), forKey: AnnotationStyleStore.key)
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .red, width: .thick))
        }
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "AnnotationStyleTests|AnnotationDocumentTests|AnnotationBoundsTests|AnnotationStyleStoreTests"`
Expected: 编译失败，`cannot find 'RGBA' in scope` / `cannot find 'PaletteColor' in scope` 等

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Annotation/AnnotationStyle.swift`：

```swift
import CoreGraphics

/// A colour as sRGB components in 0...1.
public struct RGBA: Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`, opaque.
    public init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Light fills (yellow, white) need dark text on top, e.g. the counter's number.
    /// Orange (luma ≈ 0.64) stays below the threshold and keeps white text (plan decision 11).
    public var prefersDarkText: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.7
    }
}

/// The six preset annotation colours, in palette order (design doc §4.3).
public enum PaletteColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, blue, black

    /// `black` becomes white in dark appearance so it stays visible (design doc §4.3).
    /// The resolved colour is stored in the annotation, so switching appearance later does not repaint it.
    public func rgba(darkAppearance: Bool) -> RGBA {
        switch self {
        case .red: RGBA(hex: 0xFF3B30)
        case .orange: RGBA(hex: 0xFF9500)
        case .yellow: RGBA(hex: 0xFFCC00)
        case .green: RGBA(hex: 0x34C759)
        case .blue: RGBA(hex: 0x007AFF)
        case .black: darkAppearance ? RGBA(hex: 0xFFFFFF) : RGBA(hex: 0x000000)
        }
    }
}

/// The three width levels in the style palette. Persisted by name, so reordering cases cannot
/// change what a stored style means.
public enum StrokeWidth: String, CaseIterable, Codable, Sendable {
    case thin, medium, thick

    /// Position in the palette, thin first; indexes the per-tool size tables.
    public var index: Int {
        switch self {
        case .thin: 0
        case .medium: 1
        case .thick: 2
        }
    }
}

/// The colour and width level every tool draws with. One for all tools, so switching tools keeps it
/// (design doc §3.3); mosaic uses only the width.
public struct AnnotationStyle: Equatable, Codable, Sendable {
    public var color: PaletteColor
    public var width: StrokeWidth

    public init(color: PaletteColor, width: StrokeWidth) {
        self.color = color
        self.width = width
    }

    public static let standard = AnnotationStyle(color: .red, width: .medium)

    /// Each field falls back to `.standard` on its own, so one unreadable value (say, a colour name from
    /// a later version) does not reset the other.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? container.decode(PaletteColor.self, forKey: .color)) ?? Self.standard.color
        width = (try? container.decode(StrokeWidth.self, forKey: .width)) ?? Self.standard.width
    }
}

extension Tool {
    /// What a width level means for this tool, in points: stroke width (rectangle, ellipse, arrow, pen),
    /// font size (text), brush diameter (mosaic) or badge diameter (counter).
    public func size(for width: StrokeWidth) -> CGFloat {
        let sizes: [CGFloat] = switch self {
        case .rectangle, .ellipse, .arrow, .pen: [2, 4, 6]
        case .text: [14, 20, 28]
        case .mosaic: [12, 24, 40]
        case .counter: [20, 26, 34]
        }
        return sizes[width.index]
    }
}
```

`Core/Sources/GlimpseCore/Annotation/TextLayout.swift`：

```swift
import CoreGraphics
import CoreText
import Foundation

/// Line metrics for text annotations, shared by the renderer and the text box shown while typing.
public enum TextLayout {
    /// The system UI font, the same one `NSFont.systemFont(ofSize:)` returns; bold for counter numbers.
    /// Cached per size, because annotation bounds are measured on every redraw.
    public static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        fontCache.font(size: size, bold: bold) {
            let regular = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            guard bold else { return regular }
            return CTFontCreateCopyWithSymbolicTraits(regular, size, nil, .traitBold, .traitBold) ?? regular
        }
    }

    private static let fontCache = FontCache()

    /// Fixed distance between baselines. The text box uses the same value so typing and the
    /// committed annotation line up.
    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// Distance from the top of a line to its baseline.
    public static func ascent(fontSize: CGFloat) -> CGFloat {
        CTFontGetAscent(font(size: fontSize))
    }

    /// Splits on any newline ("\n", "\r\n", "\r"); keeps empty lines.
    public static func lines(of string: String) -> [String] {
        string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    public static func line(_ text: String, fontSize: CGFloat, color: CGColor, bold: Bool = false) -> CTLine {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font(size: fontSize, bold: bold),
                                           kCTForegroundColorAttributeName: color]
        let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        return CTLineCreateWithAttributedString(string)
    }

    /// Draws `line` upright with its baseline starting at `origin`, in a context whose CTM is y-down
    /// (CoreText assumes y-up, so the text is flipped locally).
    public static func draw(_ line: CTLine, baselineOrigin origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Width of the widest line × (line count × line height).
    public static func size(of string: String, fontSize: CGFloat) -> CGSize {
        let lines = lines(of: string)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let width = lines.map { CGFloat(CTLineGetTypographicBounds(line($0, fontSize: fontSize, color: black), nil, nil, nil)) }.max() ?? 0
        return CGSize(width: ceil(width), height: lineHeight(fontSize: fontSize) * CGFloat(lines.count))
    }
}

/// Fonts by (size, bold), shared by every thread that measures or draws text.
// Safe: `fonts` is only touched while holding `lock`, and CTFont is immutable.
private final class FontCache: @unchecked Sendable {
    private struct Key: Hashable {
        let size: CGFloat
        let bold: Bool
    }

    private let lock = NSLock()
    private var fonts: [Key: CTFont] = [:]

    func font(size: CGFloat, bold: Bool, make: () -> CTFont) -> CTFont {
        lock.withLock {
            let key = Key(size: size, bold: bold)
            if let font = fonts[key] { return font }
            let font = make()
            fonts[key] = font
            return font
        }
    }
}
```

`Core/Sources/GlimpseCore/Annotation/Annotation.swift`：

```swift
import CoreGraphics

/// One vector annotation. Every coordinate and size is in pixels of its screen's frozen image
/// (top-left origin), not relative to the selection: moving or resizing the selection leaves
/// annotations where they are on the picture (design doc §5.2).
public struct Annotation: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        /// Raw pointer samples; smoothed when drawn.
        case pen([CGPoint])
        /// The brush path. The area it covers shows the original frame in `blockSize`-pixel blocks.
        case mosaic([CGPoint], blockSize: Int)
        case counter(center: CGPoint, number: Int)
        /// `origin` is the top-left of the first line; lines are split on newlines.
        case text(origin: CGPoint, string: String)
    }

    public var shape: Shape
    public var color: RGBA
    /// Stroke width (rectangle, ellipse, arrow, pen), brush diameter (mosaic),
    /// badge diameter (counter) or font size (text), in pixels.
    public var size: CGFloat

    public init(shape: Shape, color: RGBA, size: CGFloat) {
        self.shape = shape
        self.color = color
        self.size = size
    }

    /// Everything this annotation may paint, with a pixel to spare for anti-aliasing.
    public var bounds: CGRect {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .arrow(let from, let to):
            let head = ArrowMetrics.headHalfWidth(lineWidth: size)
            return Self.boundingBox([from, to]).insetBy(dx: -head - 1, dy: -head - 1)
        case .pen(let points), .mosaic(let points, _):
            return Self.boundingBox(points).insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .counter(let center, _):
            return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size).insetBy(dx: -1, dy: -1)
        case .text(let origin, let string):
            return CGRect(origin: origin, size: TextLayout.size(of: string, fontSize: size)).insetBy(dx: -1, dy: -1)
        }
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Arrow proportions, all scaling with the line width (design doc §3.4): the shaft tapers from a thin
/// tail to its full width where the head starts, and the head is clearly wider than that.
/// The head's half-width is the widest part, so it alone sizes `Annotation.bounds`.
public enum ArrowMetrics {
    /// Half the shaft's width at the tail; the tail stays at least a pixel wide.
    public static func tailHalfWidth(lineWidth: CGFloat) -> CGFloat { max(0.5, lineWidth * 0.15) }
    /// Half the shaft's width where it meets the head.
    public static func shaftHalfWidth(lineWidth: CGFloat) -> CGFloat { lineWidth * 0.8 }
    public static func headLength(lineWidth: CGFloat) -> CGFloat { lineWidth * 4.5 }
    public static func headHalfWidth(lineWidth: CGFloat) -> CGFloat { lineWidth * 2.2 }
}
```

`Core/Sources/GlimpseCore/Annotation/AnnotationDocument.swift`：

```swift
/// The annotations on one selection, with undo / redo. Every edit adds exactly one annotation
/// (annotations are never edited after they are drawn, design doc §1), so undo removes the last one
/// and redo puts it back.
public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    /// Adding after an undo drops what could have been redone, as in every editor.
    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undone.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Annotation? {
        guard let last = annotations.popLast() else { return nil }
        undone.append(last)
        return last
    }

    @discardableResult
    public mutating func redo() -> Annotation? {
        guard let next = undone.popLast() else { return nil }
        annotations.append(next)
        return next
    }

    public mutating func removeAll() {
        annotations.removeAll()
        undone.removeAll()
    }

    /// One more than the highest counter on the canvas, so undoing ③ makes the next one ③ again (design doc §3.4).
    public var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.shape { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }
}
```

`Core/Sources/GlimpseCore/Settings/AnnotationStyleStore.swift`：

```swift
import Foundation

/// Remembers the colour and width level all tools share, across captures and launches (design doc §3.3).
// Safe: the only state is a `UserDefaults`, which is thread-safe.
public final class AnnotationStyleStore: @unchecked Sendable {
    static let key = "annotationStyle"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `.standard` until something is picked, or when the stored value cannot be read at all; a single
    /// unreadable field falls back alone (see `AnnotationStyle.init(from:)`).
    public var style: AnnotationStyle {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let style = try? JSONDecoder().decode(AnnotationStyle.self, from: data) else { return .standard }
            return style
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                assertionFailure("Failed to encode AnnotationStyle")
                return
            }
            defaults.set(data, forKey: Self.key)
        }
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "AnnotationStyleTests|AnnotationDocumentTests|AnnotationBoundsTests|AnnotationStyleStoreTests"`
Expected: `Test run with 16 tests in 4 suites passed`

Run: `cd Core && swift test`
Expected: `Test run with 96 tests in 14 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 4：形状几何、拖拽草稿、Renderer.draw（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/Annotation/ShapeGeometry.swift`
- Create: `Core/Sources/GlimpseCore/Annotation/AnnotationDraft.swift`
- Create: `Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`
- Modify: `Core/Tests/GlimpseCoreTests/TestImage.swift`
- Test: `Core/Tests/GlimpseCoreTests/ShapeToolTests.swift`

要点：
- `Renderer.draw` 是**唯一**的标注绘制代码，覆盖层显示和 Task 9 的导出都调它（§5.2「所见即所得」）。它要求调用方把上下文的 CTM 设成「冻结画面像素、左上角原点、y 向下」。覆盖层视图本身是翻转的，只需再缩放 `1 / scale`；导出时平移到选区。
- `AnnotationDraft` 覆盖所有拖拽类工具（矩形、椭圆、箭头、画笔、马赛克），本任务先只把矩形、椭圆、箭头画出来；画笔、序号、马赛克、文字的绘制在 Task 6 / 7 / 8 补上，`switch` 里先留一个空分支并注明。
- `pixelated` 参数是 Task 7 马赛克要用的入口，默认不提供。
- `mosaicBlockSize` 只对马赛克有意义，马赛克必须传（`precondition`），其他工具不传；避免漏传时悄悄画成 1 像素的马赛克。
- ⇧ 吸附用 8 个方向的精确单位向量，不用 `cos` / `sin`，水平、竖直的箭头不会带 1e-16 级的偏差。
- 箭头外形按第 7 条：箭杆从细尾渐粗到箭头处，箭头明显更宽；箭头最多占全长 60%，短箭头整体按比例缩小但仍有箭杆。测试分别检查尾部比箭杆末端窄、箭头比箭杆末端宽、`bounds` 盖住整个外形、短箭头保留箭杆。

- [ ] **Step 1：给 TestImage 加一个渲染工具，写失败的测试**

在 `Core/Tests/GlimpseCoreTests/TestImage.swift` 里做 2 处替换：

（1）把

```swift
import CoreGraphics
import Foundation
```

替换为

```swift
import CoreGraphics
import Foundation
@testable import GlimpseCore
```

（2）把

```swift
    /// RGBA of pixel (x, y).
```

替换为

```swift
    /// A white `width` × `height` sRGB image with `annotations` drawn on it, through the same
    /// y-down pixel transform the export uses.
    static func render(_ annotations: [Annotation], width: Int, height: Int,
                       pixelated: (Int) -> CGImage? = { _ in nil }) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        Renderer.draw(annotations, in: ctx, pixelated: pixelated)
        return ctx.makeImage()!
    }

    /// RGBA of pixel (x, y).
```

`Core/Tests/GlimpseCoreTests/ShapeToolTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

private let red = RGBA(hex: 0xFF3B30)
private let redPixel: [UInt8] = [255, 59, 48, 255]
private let white: [UInt8] = [255, 255, 255, 255]

private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
    abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
}

struct ShapeGeometryTests {
    @Test func dragRectIsStandardized() {
        #expect(ShapeGeometry.rect(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 10), square: false)
                == CGRect(x: 10, y: 10, width: 30, height: 10))
    }

    @Test func shiftMakesASquareInTheDragDirection() {
        #expect(ShapeGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 20), square: true)
                == CGRect(x: 10, y: 10, width: 30, height: 30))
        #expect(ShapeGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: -20, y: 15), square: true)
                == CGRect(x: -20, y: 10, width: 30, height: 30))
    }

    @Test func shiftSnapsArrowsTo45DegreesKeepingLength() {
        let diagonal = ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: 30, y: 40))
        let side = 50 / CGFloat(2).squareRoot()
        #expect(close(diagonal, CGPoint(x: side, y: side)))
        let flat = ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: 100, y: -10))
        #expect(flat == CGPoint(x: CGFloat(10100).squareRoot(), y: 0)) // exactly level
    }

    @Test func snappingWorksInEveryDirection() {
        let side = 50 / CGFloat(2).squareRoot()
        #expect(close(ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: -30, y: -40)), CGPoint(x: -side, y: -side)))
        #expect(ShapeGeometry.snapped45(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: -90))
                == CGPoint(x: 10, y: 10 - CGFloat(10004).squareRoot())) // exactly vertical
    }

    @Test func arrowShaftTapersTowardsAWiderHead() {
        // Width 4: the shaft widens from half-width 0.6 at the tail to 3.2 where the head starts (x = 82);
        // the head is 18 long, half-width 8.8 at its base, 0 at the tip.
        let path = ShapeGeometry.arrowPath(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(path.contains(CGPoint(x: 5, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 5, y: 1)))     // thin tail
        #expect(path.contains(CGPoint(x: 80, y: 3)))
        #expect(!path.contains(CGPoint(x: 80, y: 3.4)))  // the shaft's wide end
        #expect(path.contains(CGPoint(x: 83, y: 8)))     // the head is much wider than the shaft's end
        #expect(path.contains(CGPoint(x: 91, y: 4.2)))   // half-width 4.4 halfway along the head
        #expect(!path.contains(CGPoint(x: 91, y: 4.7)))
        let annotation = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: red, size: 4)
        #expect(annotation.bounds.contains(path.boundingBoxOfPath))
    }

    @Test func shortArrowShrinksButKeepsAShaft() {
        // 10 long at width 4: the head may take only 60% (6 of its full 18), so the outline scales by
        // 1 / 3 and a tapering shaft still runs from x = 0 to the head's base at x = 4.
        let path = ShapeGeometry.arrowPath(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 4)
        let box = path.boundingBoxOfPath
        #expect(box.minX == 0 && box.maxX == 10)
        #expect(abs(box.height - 2 * 8.8 / 3) < 1e-9)
        #expect(path.contains(CGPoint(x: 3, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 3, y: 1.2)))  // the shaft, narrower than the head
        #expect(path.contains(CGPoint(x: 5, y: 2.2)))   // the head, just past its base
    }
}

struct AnnotationDraftTests {
    @Test func rectangleFollowsTheDragAndShiftSquaresIt() throws {
        var draft = try #require(AnnotationDraft(tool: .rectangle, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        draft.extend(to: CGPoint(x: 50, y: 30), constrained: false)
        #expect(draft.annotation == Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 40, height: 20)),
                                               color: red, size: 4))
        draft.setConstrained(true) // ⇧ pressed without moving
        #expect(draft.annotation?.shape == .rectangle(CGRect(x: 10, y: 10, width: 40, height: 40)))
    }

    @Test func shiftMakesTheEllipseACircle() throws {
        var draft = try #require(AnnotationDraft(tool: .ellipse, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        draft.extend(to: CGPoint(x: 0, y: 40), constrained: true)
        #expect(draft.annotation?.shape == .ellipse(CGRect(x: -20, y: 10, width: 30, height: 30)))
    }

    @Test func clickWithoutDragDrawsNoShape() throws {
        var rect = try #require(AnnotationDraft(tool: .ellipse, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        #expect(rect.annotation == nil)
        rect.extend(to: CGPoint(x: 10, y: 10), constrained: false)
        #expect(rect.annotation == nil)
        var arrow = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        arrow.extend(to: CGPoint(x: 1, y: 0), constrained: false)
        #expect(arrow.annotation == nil)
    }

    @Test func arrowSnapsWithShift() throws {
        var draft = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        draft.extend(to: CGPoint(x: 100, y: -10), constrained: true)
        guard case .arrow(_, let end)? = draft.annotation?.shape else {
            Issue.record("expected an arrow")
            return
        }
        #expect(close(end, CGPoint(x: CGFloat(10100).squareRoot(), y: 0)))
    }

    @Test func shiftSnapsTheArrowWithoutMovingTheMouse() throws {
        var draft = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        draft.extend(to: CGPoint(x: 100, y: -10), constrained: false)
        draft.setConstrained(true)
        #expect(draft.annotation?.shape == .arrow(from: .zero, to: CGPoint(x: CGFloat(10100).squareRoot(), y: 0)))
        draft.setConstrained(false)
        #expect(draft.annotation?.shape == .arrow(from: .zero, to: CGPoint(x: 100, y: -10)))
    }

    @Test func mosaicCarriesItsBlockSize() throws {
        var draft = try #require(AnnotationDraft(tool: .mosaic, start: .zero, color: red, size: 24, mosaicBlockSize: 16))
        draft.extend(to: CGPoint(x: 10, y: 0), constrained: false)
        #expect(draft.annotation?.shape == .mosaic([.zero, CGPoint(x: 10, y: 0)], blockSize: 16))
    }

    @Test func penKeepsSamplesAtLeastAPixelApart() throws {
        var draft = try #require(AnnotationDraft(tool: .pen, start: .zero, color: red, size: 4))
        #expect(draft.annotation?.shape == .pen([.zero])) // a click draws a dot
        draft.extend(to: CGPoint(x: 0.5, y: 0), constrained: false)
        draft.extend(to: CGPoint(x: 5, y: 0), constrained: false)
        draft.extend(to: CGPoint(x: 10, y: 0), constrained: true)
        #expect(draft.annotation?.shape == .pen([.zero, CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)]))
    }

    @Test func clickToolsHaveNoDraft() {
        #expect(AnnotationDraft(tool: .counter, start: .zero, color: red, size: 4) == nil)
        #expect(AnnotationDraft(tool: .text, start: .zero, color: red, size: 4) == nil)
    }
}

struct AnnotationRendererTests {
    @Test func rectangleStrokeIsCentredOnTheEdge() {
        let image = TestImage.render([Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 10, y: 20) == redPixel) // left edge, stroke covers x 9...11
        #expect(TestImage.pixel(image, x: 20, y: 10) == redPixel) // top edge
        #expect(TestImage.pixel(image, x: 20, y: 20) == white)    // inside stays clear
        #expect(TestImage.pixel(image, x: 5, y: 20) == white)
    }

    @Test func ellipseIsStrokedNotFilled() {
        let image = TestImage.render([Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        let top = TestImage.pixel(image, x: 20, y: 10)
        #expect(top[0] > 200 && top[1] < 120)
        #expect(TestImage.pixel(image, x: 20, y: 20) == white)
        #expect(TestImage.pixel(image, x: 11, y: 11) == white) // the corner of the box is outside the ellipse
    }

    @Test func arrowIsFilledShaftAndHead() {
        // Width 2: the shaft widens from half-width 0.5 at x = 5 to 1.6 at x = 26; the head runs from
        // there to the tip at 35, half-width 4.4 at its base.
        let image = TestImage.render([Annotation(shape: .arrow(from: CGPoint(x: 5, y: 20), to: CGPoint(x: 35, y: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 15, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 6, y: 21) == white)     // thin near the tail
        #expect(TestImage.pixel(image, x: 24, y: 21) != white)    // wider near the head
        #expect(TestImage.pixel(image, x: 15, y: 23) == white)
        #expect(TestImage.pixel(image, x: 26, y: 22) == redPixel) // head is wider than the shaft
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "ShapeGeometryTests|AnnotationDraftTests|AnnotationRendererTests"`
Expected: 编译失败，`cannot find 'ShapeGeometry' in scope` / `type 'Renderer' has no member 'draw'`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Annotation/ShapeGeometry.swift`：

```swift
import CoreGraphics
import Foundation

/// Geometry behind the shape tools (design doc §3.4). Pixel coordinates, top-left origin.
public enum ShapeGeometry {
    /// The rect a drag spans. With `square` (⇧) both sides take the longer one, growing in the drag's direction.
    public static func rect(from start: CGPoint, to end: CGPoint, square: Bool) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
    }

    /// ⇧ on the arrow: the end moves to the nearest multiple of 45° around `start`, keeping the drag length.
    public static func snapped45(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let octant = Int((atan2(dy, dx) / (CGFloat.pi / 4)).rounded())
        let (ux, uy) = directions45[(octant % 8 + 8) % 8]
        return CGPoint(x: start.x + length * ux, y: start.y + length * uy)
    }

    /// Unit vectors at 0°, 45°, … 315°, exact so horizontal and vertical arrows have no stray
    /// 1e-16 component from cos / sin.
    private static let directions45: [(CGFloat, CGFloat)] = {
        let d = CGFloat(0.5).squareRoot()
        return [(1, 0), (d, d), (0, 1), (-d, d), (-1, 0), (-d, -d), (0, -1), (d, -d)]
    }()

    /// A solid arrow as one filled outline (ArrowMetrics): a shaft that tapers from a thin tail to its
    /// full width where the head starts, and a wider pointed head. The head takes at most 60% of the
    /// length, so a short arrow keeps a shaft: its head shortens and every width shrinks with it.
    /// Empty for a zero-length arrow.
    public static func arrowPath(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let dx = tip.x - start.x, dy = tip.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return path }
        let fullHead = ArrowMetrics.headLength(lineWidth: lineWidth)
        let headLength = min(fullHead, length * 0.6)
        let shrink = headLength / fullHead
        let headHalf = ArrowMetrics.headHalfWidth(lineWidth: lineWidth) * shrink
        let shaftHalf = ArrowMetrics.shaftHalfWidth(lineWidth: lineWidth) * shrink
        let tailHalf = min(ArrowMetrics.tailHalfWidth(lineWidth: lineWidth), shaftHalf)
        let ux = dx / length, uy = dy / length   // along the arrow
        let nx = -uy, ny = ux                    // across it
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        func offset(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + nx * d, y: p.y + ny * d) }
        path.addLines(between: [
            offset(start, tailHalf), offset(base, shaftHalf), offset(base, headHalf), tip,
            offset(base, -headHalf), offset(base, -shaftHalf), offset(start, -tailHalf),
        ])
        path.closeSubpath()
        return path
    }
}
```

`Core/Sources/GlimpseCore/Annotation/AnnotationDraft.swift`：

```swift
import CoreGraphics

/// An annotation being dragged out: rectangle, ellipse, arrow, pen or mosaic. Points are image pixels.
/// Counter and text are placed with a click and never need a draft.
public struct AnnotationDraft: Equatable, Sendable {
    public let tool: Tool
    public let color: RGBA
    public let size: CGFloat
    private let mosaicBlockSize: Int
    private var points: [CGPoint]
    private var constrained = false

    /// Nil for tools that are not dragged (counter, text). `mosaicBlockSize` is required for the
    /// mosaic (in pixels, from the screen's scale) and ignored by every other tool.
    public init?(tool: Tool, start: CGPoint, color: RGBA, size: CGFloat, mosaicBlockSize: Int? = nil) {
        guard tool != .counter, tool != .text else { return nil }
        precondition(tool != .mosaic || mosaicBlockSize != nil, "A mosaic draft needs its block size")
        self.tool = tool
        self.color = color
        self.size = size
        self.mosaicBlockSize = mosaicBlockSize ?? 1
        points = [start]
    }

    /// `constrained` is ⇧: square / circle for rectangle and ellipse, 45° steps for the arrow.
    /// Pen and mosaic keep every sample at least a pixel from the previous one.
    public mutating func extend(to point: CGPoint, constrained: Bool) {
        self.constrained = constrained
        switch tool {
        case .rectangle, .ellipse, .arrow:
            points = [points[0], point]
        case .pen, .mosaic:
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
            points.append(point)
        case .counter, .text:
            break
        }
    }

    /// ⇧ pressed or released without moving the mouse.
    public mutating func setConstrained(_ constrained: Bool) {
        self.constrained = constrained
    }

    /// What the draft would commit now; nil while a shape or arrow is too small to see (a click, no drag).
    /// A pen or mosaic click keeps its single point and draws a dot.
    public var annotation: Annotation? {
        let start = points[0]
        let shape: Annotation.Shape
        switch tool {
        case .rectangle, .ellipse:
            guard points.count == 2 else { return nil }
            let rect = ShapeGeometry.rect(from: start, to: points[1], square: constrained)
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            shape = tool == .rectangle ? .rectangle(rect) : .ellipse(rect)
        case .arrow:
            guard points.count == 2 else { return nil }
            let end = constrained ? ShapeGeometry.snapped45(from: start, to: points[1]) : points[1]
            guard hypot(end.x - start.x, end.y - start.y) >= 2 else { return nil }
            shape = .arrow(from: start, to: end)
        case .pen:
            shape = .pen(points)
        case .mosaic:
            shape = .mosaic(points, blockSize: mosaicBlockSize)
        case .counter, .text:
            return nil
        }
        return Annotation(shape: shape, color: color, size: size)
    }
}
```

`Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`：

```swift
import CoreGraphics

extension Renderer {
    /// Draws `annotations` in order. The context's CTM must map frozen-image pixels (top-left origin,
    /// y down) onto the target: the overlay view scales points to pixels, the export translates to the crop.
    /// Both call this, so what is on screen is what gets copied (design doc §5.2).
    /// `pixelated(blockSize)` returns the frozen frame pixelated in blocks of that size, for mosaic.
    public static func draw(_ annotations: [Annotation], in context: CGContext,
                            pixelated: (Int) -> CGImage? = { _ in nil }) {
        for annotation in annotations {
            context.saveGState()
            draw(annotation, in: context, pixelated: pixelated)
            context.restoreGState()
        }
    }

    private static func draw(_ annotation: Annotation, in context: CGContext, pixelated: (Int) -> CGImage?) {
        let color = annotation.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.size)
        switch annotation.shape {
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .arrow(let from, let to):
            context.addPath(ShapeGeometry.arrowPath(from: from, to: to, lineWidth: annotation.size))
            context.fillPath()
        case .pen, .mosaic, .counter, .text:
            break // drawn from Task 6 (pen, counter), Task 7 (mosaic) and Task 8 (text) on
        }
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "ShapeGeometryTests|AnnotationDraftTests|AnnotationRendererTests"`
Expected: `Test run with 17 tests in 3 suites passed`

Run: `cd Core && swift test`
Expected: `Test run with 113 tests in 17 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 5：标注层、二级栏、矩形 / 椭圆 / 箭头、撤销重做

**Files:**
- Create: `App/Sources/Annotation/AnnotationCanvasView.swift`
- Create: `App/Sources/Toolbar/StylePaletteView.swift`
- Modify: `App/Sources/Overlay/OverlayContentView.swift`（整体替换）
- Modify: `App/Sources/Overlay/SelectionView.swift`（10 处替换）
- Modify: `App/Sources/Overlay/OverlayWindow.swift`（1 处替换）
- Modify: `App/Sources/Overlay/CaptureSessionController.swift`（2 处替换）
- Modify: `App/Sources/Toolbar/ToolRollout.swift`（1 处替换）

要点：
- **图层顺序**（下 → 上）：冻结画面 → `AnnotationCanvasView` → `SelectionView`（遮罩、边框、手柄）→ 尺寸标签、工具栏、二级栏。标注在遮罩下面，所以画出选区的部分看起来是暗的，和导出时被裁掉一致。
- `AnnotationCanvasView` 不接收鼠标（`hitTest` 返回 nil）。所有鼠标、键盘仍由 `SelectionView` 接收：有工具时，在选区内按下 → 交给画布；按在手柄上 → 照样缩放选区（§3.2「选了工具后手柄仍可拖动」）；方向键微调照常。
- 画布把屏幕本地点乘以缩放倍数存成像素；绘制时 `scaleBy(1/scale)` 再调 `Renderer.draw`，只重绘变化区域（用 `Annotation.bounds`）。
- 工具状态就是 `EditorPhase.editing(tool:)`：`SelectionView.perform` 处理 `.selectTool` / `.deselectTool` / `.undo` / `.redo`；工具栏按钮和字母键走同一条路。再按一次同一工具按钮 = 取消工具（§3.2）。
- 右键清除：P1 的 `CaptureSessionController.selectionViewDidRightClick` 已经对所有屏调 `resetSelection()`，本任务让 `resetSelection()` 同时清空画布，所以右键 = 清除选区和标注、回到选区阶段（§3.2）。另一块屏开始新选区时，旧屏的标注也随之清掉（选区只能在一块屏上，标注属于选区）。
- `AnnotationStyleStore` 由 `CaptureSessionController` 持有一个，传给每块屏，所以颜色 / 粗细在所有工具、多屏和多次截图之间共享、并持久化（第 6 条）。画布对外只有一个 `style` 属性；二级栏选了什么就写回它，换工具时二级栏照常显示同一份样式。

- [ ] **Step 1：AnnotationCanvasView**

`App/Sources/Annotation/AnnotationCanvasView.swift`：

```swift
import AppKit
import GlimpseCore

/// One screen's annotations: the document (with undo / redo), the shape being dragged out, and the
/// colour and width all tools share. Draws through `Renderer.draw`, the same code the export uses.
///
/// Sits between the frozen image and SelectionView, so the dim also covers the parts of annotations
/// that stick out of the selection (they are cropped on export). It takes no mouse input itself:
/// SelectionView forwards tool gestures in screen-local points, and they are stored in image pixels.
final class AnnotationCanvasView: NSView {
    /// Undo / redo availability may have changed.
    var onDocumentChange: (() -> Void)?

    private(set) var document = AnnotationDocument()
    private var draft: AnnotationDraft?
    private let scale: CGFloat
    private let styleStore: AnnotationStyleStore

    init(frame: CGRect, scale: CGFloat, styleStore: AnnotationStyleStore) {
        self.scale = scale
        self.styleStore = styleStore
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Styles

    /// The colour and width level all tools share (design doc §3.3).
    var style: AnnotationStyle {
        get { styleStore.style }
        set { styleStore.style = newValue }
    }

    /// Colour and size (in pixels) a new annotation of `tool` gets: the shared style, sized for the tool.
    private func resolvedStyle(for tool: Tool) -> (color: RGBA, size: CGFloat) {
        let style = styleStore.style
        return (style.color.rgba(darkAppearance: effectiveAppearance.isDark), tool.size(for: style.width) * scale)
    }

    private func pixels(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    // MARK: - Drag tools (rectangle, ellipse, arrow, pen, mosaic)

    /// Starts a drag-drawn annotation at `point` (screen-local). False for click tools.
    func beginDraft(tool: Tool, at point: CGPoint) -> Bool {
        let (color, size) = resolvedStyle(for: tool)
        draft = AnnotationDraft(tool: tool, start: pixels(point), color: color, size: size)
        if let bounds = draft?.annotation?.bounds { invalidate(pixelRect: bounds) }
        return draft != nil
    }

    func extendDraft(to point: CGPoint, constrained: Bool) {
        updateDraft { $0.extend(to: pixels(point), constrained: constrained) }
    }

    /// ⇧ pressed or released mid-drag.
    func setDraftConstrained(_ constrained: Bool) {
        updateDraft { $0.setConstrained(constrained) }
    }

    /// Adds the draft to the document; a click without a drag adds nothing for shapes and arrows.
    func commitDraft() {
        guard let annotation = draft?.annotation else {
            draft = nil
            return
        }
        draft = nil
        add(annotation)
    }

    /// Esc mid-drag: drops the shape being drawn; the tool stays selected.
    func cancelDraft() {
        guard let pending = draft else { return }
        draft = nil
        if let bounds = pending.annotation?.bounds { invalidate(pixelRect: bounds) }
    }

    private func updateDraft(_ change: (inout AnnotationDraft) -> Void) {
        guard var current = draft else { return }
        let before = current.annotation?.bounds ?? .null
        change(&current)
        draft = current
        invalidate(pixelRect: before.union(current.annotation?.bounds ?? .null))
    }

    // MARK: - Document

    private func add(_ annotation: Annotation) {
        document.add(annotation)
        invalidate(pixelRect: annotation.bounds)
        onDocumentChange?()
    }

    func undo() {
        guard let removed = document.undo() else { return }
        invalidate(pixelRect: removed.bounds)
        onDocumentChange?()
    }

    func redo() {
        guard let restored = document.redo() else { return }
        invalidate(pixelRect: restored.bounds)
        onDocumentChange?()
    }

    /// Right click / a new selection on another screen: annotations go with the selection (design doc §3.2).
    func removeAll() {
        draft = nil
        document.removeAll()
        needsDisplay = true
        onDocumentChange?()
    }

    // MARK: - Drawing

    private func invalidate(pixelRect: CGRect) {
        guard !pixelRect.isNull else { return }
        let points = CGRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                            width: pixelRect.width / scale, height: pixelRect.height / scale)
        setNeedsDisplay(points.insetBy(dx: -2, dy: -2).intersection(bounds))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The view is flipped, so the CTM is already y-down; scaling makes one unit one image pixel.
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        let dirtyPixels = CGRect(x: dirtyRect.minX * scale, y: dirtyRect.minY * scale,
                                 width: dirtyRect.width * scale, height: dirtyRect.height * scale)
        var visible = document.annotations
        if let pending = draft?.annotation { visible.append(pending) }
        Renderer.draw(visible.filter { $0.bounds.intersects(dirtyPixels) }, in: context)
    }
}
```

- [ ] **Step 2：StylePaletteView**

`colorsEnabled` 参数在 Task 7 给马赛克用（马赛克没有颜色），本任务里一直是默认的 `true`。

`App/Sources/Toolbar/StylePaletteView.swift`：

```swift
import AppKit
import GlimpseCore

@MainActor
protocol StylePaletteViewDelegate: AnyObject {
    func stylePaletteView(_ view: StylePaletteView, didPick style: AnnotationStyle)
}

/// The secondary bar under the toolbar (design doc §3.3): 6 preset colours | 3 widths. Shown only while
/// a tool is selected. Laid out like the mockup's `.sub` row: 14pt colour dots and 5 / 8 / 11pt width dots,
/// 8pt apart, 7pt above and below, 12pt at the ends, 2pt more on each side of the separator.
/// The dots are small, so each button is as tall as the bar and reaches half a gap past its dot on each
/// side: the click targets touch, with no dead space between neighbours.
final class StylePaletteView: MaterialView {
    weak var delegate: StylePaletteViewDelegate?

    private static let verticalPadding: CGFloat = 7
    private static let horizontalPadding: CGFloat = 12
    private static let spacing: CGFloat = 8
    private static let separatorMargin: CGFloat = 2
    /// The separator is the tallest item.
    private static let height = MaterialSeparatorView.size.height + verticalPadding * 2
    private var buttons: [PaletteButton] = []
    private var style = AnnotationStyle.standard
    private var colorsEnabled = true

    init() {
        super.init(cornerRadius: 12)
        // x is where the next dot starts, already past the gap after the previous one.
        var x = Self.horizontalPadding
        for color in PaletteColor.allCases {
            add(.color(color), x: &x)
        }
        contentView.addSubview(MaterialSeparatorView(origin: CGPoint(
            x: x + Self.separatorMargin, y: (Self.height - MaterialSeparatorView.size.height) / 2)))
        x += Self.separatorMargin * 2 + MaterialSeparatorView.size.width + Self.spacing
        for width in StrokeWidth.allCases {
            add(.width(width), x: &x)
        }
        frame.size = CGSize(width: x - Self.spacing + Self.horizontalPadding, height: Self.height)
    }

    private func add(_ choice: PaletteButton.Choice, x: inout CGFloat) {
        let dot = PaletteButton.dotDiameter(for: choice)
        let target = CGRect(x: x - Self.spacing / 2, y: 0, width: dot + Self.spacing, height: Self.height)
        let button = PaletteButton(choice: choice, frame: target, target: self, action: #selector(pressed(_:)))
        contentView.addSubview(button)
        buttons.append(button)
        x += dot + Self.spacing
    }

    /// Marks the shared colour and width. Mosaic has no colour, so its swatches are disabled.
    func show(_ style: AnnotationStyle, colorsEnabled: Bool = true) {
        self.style = style
        self.colorsEnabled = colorsEnabled
        for button in buttons {
            switch button.choice {
            case .color(let color):
                button.isChosen = colorsEnabled && color == style.color
                button.isEnabled = colorsEnabled
                button.alphaValue = colorsEnabled ? 1 : 0.35
            case .width(let width):
                button.isChosen = width == style.width
            }
        }
    }

    @objc private func pressed(_ sender: PaletteButton) {
        var picked = style
        switch sender.choice {
        case .color(let color): picked.color = color
        case .width(let width): picked.width = width
        }
        show(picked, colorsEnabled: colorsEnabled)
        delegate?.stylePaletteView(self, didPick: picked)
    }
}

/// A colour swatch or a width dot, centred in a larger click target. Draws itself so the swatch follows
/// light / dark (black ↔ white).
final class PaletteButton: NSButton {
    enum Choice {
        case color(PaletteColor)
        case width(StrokeWidth)
    }

    let choice: Choice

    var isChosen = false {
        didSet { if isChosen != oldValue { needsDisplay = true } }
    }

    /// Drawn sizes from the mockup: 14pt colour dots; 5, 8 and 11pt width dots.
    static func dotDiameter(for choice: Choice) -> CGFloat {
        switch choice {
        case .color: 14
        case .width(let width): [5, 8, 11][width.index]
        }
    }

    init(choice: Choice, frame: CGRect, target: AnyObject, action: Selector) {
        self.choice = choice
        super.init(frame: frame)
        title = ""
        isBordered = false
        refusesFirstResponder = true
        focusRingType = .none
        self.target = target
        self.action = action
        // VoiceOver names only: AppKit tooltips would sit behind the overlay (see ToolbarButton).
        switch choice {
        case .color(let color): setAccessibilityLabel(Self.colorNames[color])
        case .width(let width): setAccessibilityLabel(["细", "中", "粗"][width.index])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let colorNames: [PaletteColor: String] = [
        .red: "红", .orange: "橙", .yellow: "黄", .green: "绿", .blue: "蓝", .black: "黑（夜间为白）",
    ]

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = Self.dotDiameter(for: choice) / 2
        func circle(_ r: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        switch choice {
        case .color(let color):
            if isChosen {
                // `.dot.cur`: a 2pt white ring, then 1.5pt of accent
                // (box-shadow: 0 0 0 2px white, 0 0 0 3.5px accent).
                NSColor.controlAccentColor.setFill()
                circle(radius + 3.5).fill()
                NSColor(white: 1, alpha: 0.95).setFill()
                circle(radius + 2).fill()
            }
            color.rgba(darkAppearance: effectiveAppearance.isDark).nsColor.setFill()
            circle(radius).fill()
            // A 1pt inner hairline (inset 0 0 0 1px, 12% black) keeps the white and black swatches visible.
            let edge = circle(radius - 0.5)
            edge.lineWidth = 1
            NSColor(white: 0, alpha: 0.12).setStroke()
            edge.stroke()
        case .width:
            // `.w`: the text colour, full strength for the current width and 75% for the others.
            NSColor.materialText.withAlphaComponent(isChosen ? 1 : 0.75).setFill()
            circle(radius).fill()
        }
    }
}

extension RGBA {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
```

- [ ] **Step 3：OverlayContentView 整体替换**

`selectedTool` 已经把 `.typing` 视为文字工具（Task 8 才会进入这个阶段，提前写好免得 Task 8 再改这里）。

`App/Sources/Overlay/OverlayContentView.swift`：

```swift
import AppKit
import GlimpseCore

/// One screen's overlay, bottom to top:
/// - a plain layer-backed view whose layer shows the frozen CGImage directly (no NSImage redraws)
/// - AnnotationCanvasView: the annotations, under the dim so parts outside the selection look dimmed
/// - SelectionView: dim, selection, handles, and all mouse / keyboard input
/// - the chrome on the shared material: size label, toolbar, style palette, toolbar tooltip
/// Flipped, so every frame here is screen-local points like the selection.
final class OverlayContentView: NSView {
    let selectionView: SelectionView

    private let captured: CapturedScreen
    private let canvas: AnnotationCanvasView
    private let toolbar = ToolbarView()
    private let palette = StylePaletteView()
    private let sizeLabel = GlassLabelView(font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
    /// Toolbar tooltips are drawn here: AppKit's tooltip window would sit behind the `.screenSaver` overlay.
    private let toolTipLabel = GlassLabelView(font: .systemFont(ofSize: 11, weight: .medium))
    private var toolbarSide: OverlayLayout.ToolbarPosition.Side = .below
    /// The tool the palette last showed; it is only refreshed when the tool changes (see layoutChrome).
    private var paletteTool: Tool?

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat, styleStore: AnnotationStyleStore) {
        self.captured = captured
        let frame = CGRect(origin: .zero, size: captured.info.frame.size)
        canvas = AnnotationCanvasView(frame: frame, scale: captured.info.scale, styleStore: styleStore)
        selectionView = SelectionView(frame: frame, captured: captured, windows: windows,
                                      primaryScreenHeight: primaryScreenHeight, canvas: canvas)
        super.init(frame: frame)

        let imageView = NSView(frame: frame)
        imageView.wantsLayer = true
        imageView.layer?.contents = captured.image
        imageView.layer?.contentsGravity = .resize
        for view in [imageView, canvas, selectionView] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        for chrome in [sizeLabel, toolbar, palette, toolTipLabel] as [NSView] {
            chrome.isHidden = true
            addSubview(chrome)
        }
        toolbar.delegate = self
        palette.delegate = self
        selectionView.chromeDelegate = self
        canvas.onDocumentChange = { [weak self] in self?.refreshToolbarState() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// A right click on the toolbar's padding or buttons bubbles up to here, not to the sibling selection
    /// view: forward it so it still means "start over" (design doc §3.2).
    override func rightMouseDown(with event: NSEvent) {
        selectionView.rightMouseDown(with: event)
    }

    /// The tool whose button is highlighted and whose style the palette shows; typing belongs to the text tool.
    private var selectedTool: Tool? {
        switch selectionView.phase {
        case .selecting: nil
        case .editing(let tool): tool
        case .typing: .text
        }
    }

    private func refreshToolbarState() {
        toolbar.update(selectedTool: selectedTool, canUndo: canvas.document.canUndo, canRedo: canvas.document.canRedo)
    }

    // MARK: - Chrome layout

    /// Puts the size label, toolbar and palette around the current selection (design doc §3.2, §3.3).
    private func layoutChrome() {
        guard let rect = selectionView.selectionRect else {
            hideToolbar()
            sizeLabel.isHidden = true
            return
        }
        let screen = chromeArea
        var toolbarFrame: CGRect?
        if case .selecting = selectionView.phase {
            hideToolbar() // still dragging out the selection
        } else {
            let position = OverlayLayout.toolbar(size: toolbar.frame.size, selection: rect, screen: screen,
                                                     obstacle: notchObstacle)
            if toolbar.isHidden || toolbar.frame != position.frame {
                // Moving under a stationary mouse sends no exit event: drop stale hover and tooltip by hand.
                toolbar.resetHover()
                toolTipLabel.isHidden = true
            }
            show(toolbar, at: position.frame)
            toolbarFrame = position.frame
            toolbarSide = position.side
            if let tool = selectedTool {
                // Not on every move or resize: reading the style decodes it from UserDefaults. A pick in
                // the palette updates the palette itself.
                if palette.isHidden || tool != paletteTool {
                    palette.show(canvas.style)
                    paletteTool = tool
                }
                show(palette, at: OverlayLayout.palette(size: palette.frame.size, toolbar: position, screen: screen,
                                                        obstacle: notchObstacle))
            } else {
                palette.isHidden = true
            }
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: rect, scale: captured.info.scale)
        sizeLabel.setText("\(Int(pixels.width)) × \(Int(pixels.height))")
        sizeLabel.frame = OverlayLayout.sizeLabel(size: sizeLabel.frame.size, selection: rect, screen: screen,
                                                  avoiding: toolbarFrame, obstacle: notchObstacle)
        sizeLabel.isHidden = false
    }

    /// Chrome may use the whole screen except the camera housing (`notchObstacle`).
    private var chromeArea: CGRect { CGRect(origin: .zero, size: bounds.size) }

    /// The camera housing in this view's flipped local coordinates: the gap between the two top areas the
    /// system leaves usable, as tall as the top safe-area inset. nil on screens without a notch.
    private var notchObstacle: CGRect? {
        let screen = captured.nsScreen
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        // The areas are in global screen coordinates; subtract the screen's origin (they are already local
        // when that origin is 0, or when a system reports them relative to the screen).
        let originX = abs(left.minX - screen.frame.minX) < 1 ? screen.frame.minX : 0
        return CGRect(x: left.maxX - originX, y: 0, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private func hideToolbar() {
        toolbar.isHidden = true
        palette.isHidden = true
        toolbar.resetHover()
        toolTipLabel.isHidden = true
    }

    /// Puts a chrome view at `frame` and shows it at once: the toolbar is there the moment the selection is
    /// made, with no fade or slide (design doc §4.3).
    private func show(_ view: NSView, at frame: CGRect) {
        view.frame = frame
        view.isHidden = false
    }
}

extension OverlayContentView: SelectionViewChromeDelegate {
    func selectionViewDidChangeLayout(_ view: SelectionView) {
        layoutChrome()
        refreshToolbarState()
    }

    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool {
        [toolbar, palette].contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

extension OverlayContentView: ToolbarViewDelegate {
    /// Name and shortcut after a short hover (design doc §3.3), on the material like the rest of the chrome.
    func toolbarView(_ view: ToolbarView, showToolTipFor item: ToolbarItem?, buttonFrame: CGRect) {
        guard let item, !toolbar.isHidden else {
            toolTipLabel.isHidden = true
            return
        }
        toolTipLabel.setText(item.toolTip)
        toolTipLabel.frame = OverlayLayout.toolTip(size: toolTipLabel.frame.size, button: convert(buttonFrame, from: toolbar),
                                                   toolbarSide: toolbarSide, screen: chromeArea,
                                                   obstacle: notchObstacle)
        toolTipLabel.isHidden = false
    }

    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem) {
        switch item {
        case .tool(let tool):
            selectionView.perform(tool == selectedTool ? .deselectTool : .selectTool(tool))
        case .undo:
            selectionView.perform(.undo)
        case .redo:
            selectionView.perform(.redo)
        case .save:
            selectionView.perform(.save)
        case .cancel:
            selectionView.perform(.exit)
        case .confirm:
            selectionView.perform(.finishCopy)
        }
    }
}

extension OverlayContentView: StylePaletteViewDelegate {
    func stylePaletteView(_ view: StylePaletteView, didPick style: AnnotationStyle) {
        canvas.style = style
    }
}
```

- [ ] **Step 4：修改 SelectionView**

在 `App/Sources/Overlay/SelectionView.swift` 里按顺序做 10 处替换：

（1）把

```swift
    private let captured: CapturedScreen
    private let windows: [WindowInfo]
    private let primaryScreenHeight: CGFloat
```

替换为

```swift
    private let captured: CapturedScreen
    private let windows: [WindowInfo]
    private let primaryScreenHeight: CGFloat
    /// Annotations live in their own view; tool gestures are forwarded to it.
    private let canvas: AnnotationCanvasView
```

（2）把

```swift
        case resizing(Handle, original: CGRect)
    }
```

替换为

```swift
        case resizing(Handle, original: CGRect)
        case annotating                                 // a drag tool is drawing; points go to the canvas
    }
```

（3）把

```swift
    init(frame: CGRect, captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        self.captured = captured
        self.windows = windows
        self.primaryScreenHeight = primaryScreenHeight
        super.init(frame: frame)
```

替换为

```swift
    init(frame: CGRect, captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat,
         canvas: AnnotationCanvasView) {
        self.captured = captured
        self.windows = windows
        self.primaryScreenHeight = primaryScreenHeight
        self.canvas = canvas
        super.init(frame: frame)
```

（4）把

```swift
        phase = .selecting
        drag = .none
        refreshDisplay()
        // Callers
```

替换为

```swift
        phase = .selecting
        drag = .none
        canvas.removeAll() // annotations belong to the selection (design doc §3.2: right click clears both)
        refreshDisplay()
        // Callers
```

（5）把

```swift
            if let handle = selection.handle(at: point) {
                drag = .resizing(handle, original: selection.rect)
            } else if tool == nil, selection.rect.contains(point) {
```

替换为

```swift
            if let handle = selection.handle(at: point) {
                drag = .resizing(handle, original: selection.rect) // handles work with a tool too (§3.2)
            } else if let tool, selection.rect.contains(point) {
                drag = canvas.beginDraft(tool: tool, at: point) ? .annotating : .none
            } else if tool == nil, selection.rect.contains(point) {
```

（6）把

```swift
        case .resizing(let handle, let original):
            selection?.resize(handle, to: point, original: original)
        }
        refreshDisplay()
    }
```

替换为

```swift
        case .resizing(let handle, let original):
            selection?.resize(handle, to: point, original: original)
        case .annotating:
            canvas.extendDraft(to: point, constrained: event.modifierFlags.contains(.shift))
            return
        }
        refreshDisplay()
    }

    /// ⇧ pressed or released mid-drag re-shapes the draft without waiting for the mouse to move.
    override func flagsChanged(with event: NSEvent) {
        if case .annotating = drag {
            canvas.setDraftConstrained(event.modifierFlags.contains(.shift))
        }
        super.flagsChanged(with: event)
    }
```

（7）把

```swift
        case .moving, .none:
            break
        }
        refreshDisplay()
```

替换为

```swift
        case .annotating:
            canvas.commitDraft()
        case .moving, .none:
            break
        }
        refreshDisplay()
```

（8）把

```swift
    override func keyDown(with event: NSEvent) {
        perform(KeyRouter.route(KeyInput(event: event), phase: phase))
    }
```

替换为

```swift
    override func keyDown(with event: NSEvent) {
        let input = KeyInput(event: event)
        if case .annotating = drag {
            // Mid-drag (design doc §3.2.1): Esc drops the shape being drawn and keeps the tool;
            // every other key waits for mouse-up.
            if input.key == .escape {
                canvas.cancelDraft()
                drag = .none
            }
            return
        }
        perform(KeyRouter.route(input, phase: phase))
    }
```

（9）把

```swift
        case .reselect, .copyColor, .passToTextField, .endTyping, .selectTool, .deselectTool, .undo, .redo, .ignore:
            break // tools, colour picking and undo arrive in P2
        }
```

替换为

```swift
        case .selectTool(let tool):
            guard case .editing = phase, ToolRollout.enabled.contains(tool) else { return }
            phase = .editing(tool: tool)
            refreshHoverAtMouse() // cursor
        case .deselectTool:
            guard case .editing(.some) = phase else { return }
            phase = .editing(tool: nil)
            refreshHoverAtMouse()
        case .undo:
            canvas.undo()
        case .redo:
            canvas.redo()
        case .reselect, .copyColor, .passToTextField, .endTyping, .ignore:
            break // colour picking arrives in Task 10, typing in Task 8; reselect is decided by the controller
        }
```

（10）把

```swift
        if let handle = selection.handle(at: point) {
            resizeCursor(for: handle).set()
        } else if tool == nil, selection.rect.contains(point) {
            NSCursor.openHand.set()
        } else {
```

替换为

```swift
        if let handle = selection.handle(at: point) {
            resizeCursor(for: handle).set()
        } else if tool == nil, selection.rect.contains(point) {
            NSCursor.openHand.set()
        } else if tool != nil, selection.rect.contains(point) {
            NSCursor.crosshair.set()
        } else {
```

- [ ] **Step 5：修改 OverlayWindow、CaptureSessionController、ToolRollout**

`App/Sources/Overlay/OverlayWindow.swift`：

（1）把

```swift
    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        let content = OverlayContentView(captured: captured, windows: windows, primaryScreenHeight: primaryScreenHeight)
```

替换为

```swift
    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat, styleStore: AnnotationStyleStore) {
        let content = OverlayContentView(captured: captured, windows: windows, primaryScreenHeight: primaryScreenHeight,
                                         styleStore: styleStore)
```

`App/Sources/Overlay/CaptureSessionController.swift`：

（1）把

```swift
    private let capture = CaptureService()
```

替换为

```swift
    private let capture = CaptureService()
    /// The colour and width all tools share, on every screen and across captures.
    private let styleStore = AnnotationStyleStore()
```

（2）把

```swift
            let window = OverlayWindow(captured: screen, windows: result.windows,
                                       primaryScreenHeight: result.primaryScreenHeight)
```

替换为

```swift
            let window = OverlayWindow(captured: screen, windows: result.windows,
                                       primaryScreenHeight: result.primaryScreenHeight, styleStore: styleStore)
```

`App/Sources/Toolbar/ToolRollout.swift`：

（1）把

```swift
    static let enabled: Set<Tool> = []
```

替换为

```swift
    static let enabled: Set<Tool> = [.rectangle, .ellipse, .arrow]
```

- [ ] **Step 6：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

Run: `cd Core && swift test`
Expected: `Test run with 113 tests in 17 suites passed`

- [ ] **Step 7：手动检查（用户在真机上做）**

Run: `cd . && scripts/run.sh`，选好区域后：
- 进入编辑阶段时没有选中任何工具，二级栏不显示（§3.2）
- 矩形、椭圆、箭头按钮可点；画笔、文字、马赛克、序号仍是灰的
- 点「矩形」或按 R：按钮变成强调色实底 + 白色图标；工具栏另一侧出现二级栏（6 个 14pt 色块 │ 5 / 8 / 11pt 三个粗细点，样子对照视觉稿 `radius-v2.html` 的二级栏），当前颜色外面是一圈白环加一圈强调色环，当前粗细的点颜色最实、其余略淡；色块之间的空隙点下去也算点中相邻的色块
- 在选区内拖拽：实时出现矩形描边；松手后保留。按住 ⇧ 拖：正方形；拖到一半按下 / 松开 ⇧：不移动鼠标也立即在正方形和长方形之间切换
- 椭圆（O）同上，⇧ 为正圆；箭头（A）：实心箭头，箭杆从尾部细到箭头处渐粗，箭头明显比箭杆宽，整体大小随粗细变化（对照微信 / Snipaste 的箭头看是否顺眼）；很短的箭头整体按比例缩小，但仍能看出细尾和箭杆，不是一个胖三角；⇧ 时只能是 0° / 45° / 90° … 方向
- 只点一下不拖：什么都不画
- 拖画到一半按 Esc：这一笔消失，工具仍选中，松手后也不会画出来；拖画到一半按 ⌘Z、字母键（如 O）、方向键、Enter：都不起作用，松手后这一笔照常保留，工具和选区都没变
- 选区外按下拖动：不画；从选区内拖到选区外：超出部分被遮罩压暗
- 有工具时拖手柄：选区照样缩放；方向键：选区照样微调；**已画的标注留在画面原位，不跟着选区走**
- 有工具时在选区内是十字光标，在手柄上是缩放光标；无工具时选区内是手形
- 二级栏点「蓝」「粗」：之后画的都是蓝色粗线；切到椭圆、箭头：二级栏仍选中蓝色和粗档，画出来也是蓝色粗线（颜色和粗细全局共用，换工具不重置）；退出再截图、甚至重启应用后，仍是蓝色粗档
- 深色外观下：二级栏最后一个色块显示为白色，画出来也是白色；已画的黑色标注切换外观后不变
- ⌘Z 撤销最后一个标注，⌘⇧Z 重做；工具栏的撤销 / 重做按钮同样可用，没有可撤销 / 可重做时按钮变灰；撤销后再画新标注，重做按钮变灰
- 再点一次当前工具按钮、再按一次同一字母、或按 Esc：取消工具，二级栏消失；无工具时再按 Esc：退出截图（§3.2.1）
- 有工具时双击选区内部：不会完成截图；无工具时双击：完成（同 P1）
- 右键：选区和标注一起清除，回到选区阶段的悬停高亮；再截一次，前一次的标注不会残留
- 此时 ✓ / ⌘S 输出的仍是**不含标注**的原图（Task 9 接上合成）

- [ ] **Step 8：停下，不 commit**

**批次 B 检查点：** 用户确认 Task 5 的手动检查，再进入批次 C。

---

## 批次 C：画笔 / 序号 / 马赛克

### Task 6：画笔 + 序号

**Files:**
- Modify: `Core/Sources/GlimpseCore/Annotation/ShapeGeometry.swift`（1 处替换：新增 `smoothedPath`）
- Modify: `Core/Sources/GlimpseCore/Annotation/AnnotationDraft.swift`（1 处替换：新增 `tailBounds`）
- Modify: `Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`（2 处替换）
- Test: `Core/Tests/GlimpseCoreTests/PenCounterTests.swift`
- Modify: `App/Sources/Overlay/SelectionView.swift`（1 处替换）
- Modify: `App/Sources/Annotation/AnnotationCanvasView.swift`（3 处替换）
- Modify: `App/Sources/Toolbar/ToolRollout.swift`（1 处替换）

要点：
- 画笔平滑（§3.4）：采样点之间至少相隔 1 像素（`AnnotationDraft` 已做），绘制时用「以采样点为控制点、经过相邻采样点中点」的二次曲线，鼠标抖动造成的折角会被磨圆；圆头圆角。
- 序号按下即放置；号码由 `AnnotationDocument.nextCounterNumber` 决定，撤销自动回退（Task 3 已测）。三位数的号码字号更小，数字留在圆内（有测试）。
- 拖画时只重画会变的部分：画笔 / 马赛克的新采样点只影响笔画末尾（最后 3 个采样点围成的范围，加半个笔宽和 1 像素），所以用 `AnnotationDraft.tailBounds` 而不是整条笔画的外框；否则越画越长，每个鼠标事件都重画接近全屏，5K 屏 120Hz 下会卡。形状和箭头仍整个重画。⇧ 对画笔 / 马赛克不起作用，按下松开不重画。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/PenCounterTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

private let redPixel: [UInt8] = [255, 59, 48, 255]
private let white: [UInt8] = [255, 255, 255, 255]

/// Element kinds of a path, in order.
private func elements(_ path: CGPath) -> [CGPathElementType] {
    var kinds: [CGPathElementType] = []
    path.applyWithBlock { kinds.append($0.pointee.type) }
    return kinds
}

/// Pixels of `image` inside `rect` that satisfy `test`.
private func count(in image: CGImage, _ rect: CGRect, where test: ([UInt8]) -> Bool) -> Int {
    var n = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
        for x in Int(rect.minX)..<Int(rect.maxX) where test(TestImage.pixel(image, x: x, y: y)) { n += 1 }
    }
    return n
}

struct PenTests {
    @Test func smoothedPathCurvesThroughMidpointsAndEndsOnTheLastSample() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10)]
        let path = ShapeGeometry.smoothedPath(through: points)
        #expect(elements(path) == [.moveToPoint, .addQuadCurveToPoint, .addQuadCurveToPoint, .addLineToPoint])
        #expect(path.currentPoint == CGPoint(x: 20, y: 10))
    }

    @Test func twoSamplesAreAStraightLine() {
        let path = ShapeGeometry.smoothedPath(through: [.zero, CGPoint(x: 5, y: 5)])
        #expect(elements(path) == [.moveToPoint, .addLineToPoint])
    }

    @Test func penStrokeHasRoundEnds() {
        let image = TestImage.render([Annotation(shape: .pen([CGPoint(x: 5, y: 20), CGPoint(x: 35, y: 20)]),
                                                 color: RGBA(hex: 0xFF3B30), size: 4)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 4, y: 20) == redPixel)  // the round cap reaches past the first sample
        #expect(TestImage.pixel(image, x: 20, y: 24) == white)
    }

    @Test func aClickDrawsADot() {
        let image = TestImage.render([Annotation(shape: .pen([CGPoint(x: 20, y: 20)]), color: RGBA(hex: 0xFF3B30), size: 6)],
                                     width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 20, y: 25) == white)
    }

    @Test func dragRedrawsOnlyTheStrokeTail() throws {
        var pen = try #require(AnnotationDraft(tool: .pen, start: .zero, color: RGBA(hex: 0xFF3B30), size: 4))
        for x in stride(from: 10, through: 100, by: 10) {
            pen.extend(to: CGPoint(x: x, y: 0), constrained: false)
        }
        // The last three samples (x 80...100), widened by half the 4-pixel brush plus a pixel.
        #expect(pen.tailBounds == CGRect(x: 77, y: -3, width: 26, height: 6))
        #expect(pen.annotation?.bounds.minX == -3) // the whole stroke reaches back to the start
        var box = try #require(AnnotationDraft(tool: .rectangle, start: .zero, color: RGBA(hex: 0xFF3B30), size: 4))
        box.extend(to: CGPoint(x: 50, y: 30), constrained: false)
        #expect(box.tailBounds == box.annotation?.bounds) // shapes redraw whole
    }
}

struct CounterTests {
    @Test func badgeIsFilledWithAWhiteNumber() {
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 1),
                                                 color: RGBA(hex: 0xFF3B30), size: 30)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 8) == redPixel)  // above the digit, inside the badge
        #expect(TestImage.pixel(image, x: 2, y: 2) == white)      // outside the badge
        let digit = count(in: image, CGRect(x: 14, y: 12, width: 12, height: 16)) { $0[1] > 200 && $0[2] > 200 }
        #expect(digit > 10)
    }

    @Test func lightBadgeGetsADarkNumber() {
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 7),
                                                 color: RGBA(hex: 0xFFCC00), size: 30)], width: 40, height: 40)
        let digit = count(in: image, CGRect(x: 14, y: 12, width: 12, height: 16)) { $0[0] < 80 }
        #expect(digit > 10)
    }

    @Test func threeDigitsFitInsideTheBadge() {
        // Dark digits on a yellow badge of radius 15: every dark pixel stays at least a pixel inside the edge.
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 100),
                                                 color: RGBA(hex: 0xFFCC00), size: 30)], width: 40, height: 40)
        var outside = 0
        for y in 0..<40 {
            for x in 0..<40 where hypot(CGFloat(x) + 0.5 - 20, CGFloat(y) + 0.5 - 20) > 14 {
                if TestImage.pixel(image, x: x, y: y)[0] < 128 { outside += 1 }
            }
        }
        #expect(outside == 0)
        let digits = count(in: image, CGRect(x: 6, y: 12, width: 28, height: 16)) { $0[0] < 80 }
        #expect(digits > 20)
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "PenTests|CounterTests"`
Expected: 编译失败，`type 'ShapeGeometry' has no member 'smoothedPath'`、`value of type 'AnnotationDraft' has no member 'tailBounds'`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Annotation/ShapeGeometry.swift`：

（1）把

```swift
        path.closeSubpath()
        return path
    }
}
```

替换为

```swift
        path.closeSubpath()
        return path
    }

    /// The pen's smoothed stroke (design doc §3.4): quadratic curves through the midpoints of the samples,
    /// using each sample as the control point, so corners from jittery mouse input round off.
    /// One sample gives a zero-length segment, which a round cap draws as a dot.
    public static func smoothedPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: last)
            return path
        }
        for i in 1..<(points.count - 1) {
            let next = points[i + 1]
            let mid = CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: last)
        return path
    }
}
```

`Core/Sources/GlimpseCore/Annotation/AnnotationDraft.swift`：

（1）把

```swift
        case .counter, .text:
            return nil
        }
        return Annotation(shape: shape, color: color, size: size)
    }
}
```

替换为

```swift
        case .counter, .text:
            return nil
        }
        return Annotation(shape: shape, color: color, size: size)
    }

    /// What the latest change can repaint, for redrawing while dragging. Shapes and arrows are redrawn
    /// whole. A pen or mosaic stroke only grows at its end: with midpoint smoothing
    /// (`ShapeGeometry.smoothedPath`), appending a sample replaces the closing line from the midpoint of
    /// the previous two samples with a curve through the last sample, plus a new closing line. Both lie
    /// within the hull of the last three samples, so comparing this before and after a change covers
    /// the old and the new end, widened by half the brush and a pixel for anti-aliasing.
    public var tailBounds: CGRect {
        switch tool {
        case .pen, .mosaic:
            return Annotation.boundingBox(Array(points.suffix(3))).insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .rectangle, .ellipse, .arrow, .counter, .text:
            return annotation?.bounds ?? .null
        }
    }
}
```

`Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`（序号的数字用 CoreText 画）：

（1）把

```swift
import CoreGraphics

extension Renderer
```

替换为

```swift
import CoreGraphics
import CoreText

extension Renderer
```

（2）把

```swift
        case .pen, .mosaic, .counter, .text:
            break // drawn from Task 6 (pen, counter), Task 7 (mosaic) and Task 8 (text) on
        }
    }
}
```

替换为

```swift
        case .pen(let points):
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(ShapeGeometry.smoothedPath(through: points))
            context.strokePath()
        case .counter(let center, let number):
            drawCounter(number, center: center, diameter: annotation.size, color: annotation.color, in: context)
        case .mosaic, .text:
            break // drawn from Task 7 (mosaic) and Task 8 (text) on
        }
    }

    /// A filled badge with a bold number; dark digits on light fills (yellow, white), white digits otherwise.
    private static func drawCounter(_ number: Int, center: CGPoint, diameter: CGFloat, color: RGBA, in context: CGContext) {
        context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                       width: diameter, height: diameter))
        let digits = String(number)
        let fontSize = diameter * (digits.count == 1 ? 0.6 : digits.count == 2 ? 0.5 : 0.38)
        let textColor = color.prefersDarkText ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                                              : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let line = TextLayout.line(digits, fontSize: fontSize, color: textColor, bold: true)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let capHeight = CTFontGetCapHeight(TextLayout.font(size: fontSize, bold: true))
        TextLayout.draw(line, baselineOrigin: CGPoint(x: center.x - width / 2, y: center.y + capHeight / 2), in: context)
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "PenTests|CounterTests"`
Expected: `Test run with 8 tests in 2 suites passed`

Run: `cd Core && swift test`
Expected: `Test run with 121 tests in 19 suites passed`

- [ ] **Step 5：接上界面**

`App/Sources/Annotation/AnnotationCanvasView.swift`：

（1）把

```swift
    // MARK: - Document
```

替换为

```swift
    // MARK: - Click tools

    /// Places the next number (design doc §3.4); undoing it hands the number back.
    func placeCounter(at point: CGPoint) {
        let (color, size) = resolvedStyle(for: .counter)
        add(Annotation(shape: .counter(center: pixels(point), number: document.nextCounterNumber),
                       color: color, size: size))
    }

    // MARK: - Document
```

（2）把

```swift
    /// ⇧ pressed or released mid-drag.
    func setDraftConstrained(_ constrained: Bool) {
        updateDraft { $0.setConstrained(constrained) }
    }
```

替换为

```swift
    /// ⇧ pressed or released mid-drag. Pen and mosaic ignore ⇧, so nothing needs redrawing for them.
    func setDraftConstrained(_ constrained: Bool) {
        guard let tool = draft?.tool, tool != .pen, tool != .mosaic else { return }
        updateDraft { $0.setConstrained(constrained) }
    }
```

（3）把

```swift
        let before = current.annotation?.bounds ?? .null
        change(&current)
        draft = current
        invalidate(pixelRect: before.union(current.annotation?.bounds ?? .null))
```

替换为

```swift
        // Only the part that can change: the stroke's tail for pen and mosaic, so a long stroke does not
        // redraw its whole bounding box on every mouse event; the whole shape for the others.
        let before = current.tailBounds
        change(&current)
        draft = current
        invalidate(pixelRect: before.union(current.tailBounds))
```

`App/Sources/Overlay/SelectionView.swift`：

（1）把

```swift
            } else if let tool, selection.rect.contains(point) {
                drag = canvas.beginDraft(tool: tool, at: point) ? .annotating : .none
```

替换为

```swift
            } else if let tool, selection.rect.contains(point) {
                switch tool {
                case .counter:
                    canvas.placeCounter(at: point) // placed on press, so fast clicking never misses one
                    drag = .none
                default:
                    drag = canvas.beginDraft(tool: tool, at: point) ? .annotating : .none
                }
```

`App/Sources/Toolbar/ToolRollout.swift`：

（1）把

```swift
    static let enabled: Set<Tool> = [.rectangle, .ellipse, .arrow]
```

替换为

```swift
    static let enabled: Set<Tool> = [.rectangle, .ellipse, .arrow, .pen, .counter]
```

- [ ] **Step 6：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

- [ ] **Step 7：手动检查（用户在真机上做）**

- 画笔（P）：快速画一条折线和一个圈，线条平滑、没有明显折角；圆头；点一下画一个点
- 画笔在 5K / 4K 屏上连续画一条很长的线（来回绕十几圈）：越画越长也一直跟手，不变卡；画到一半按 ⇧ 不影响画笔；拖到一半按 Esc 丢弃这一笔
- 序号（N）：连续点 3 次出现 ① ② ③（快速连点也不丢号、不会触发完成）；⌘Z 撤销 ③，再点一次出来的还是 ③；撤销到只剩 ①，再点出来 ②
- 序号选黄色：数字是黑色；其他颜色：白色数字；粗细三档对应三种圆大小；连点到 10 以上，两位数仍在圆内
- 序号和其他标注混着画，撤销 / 重做顺序正确
- 选区移动后序号留在画面原处

- [ ] **Step 8：停下，不 commit**

---

### Task 7：马赛克

**Files:**
- Create: `Core/Sources/GlimpseCore/Rendering/MosaicSource.swift`
- Modify: `Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`（2 处替换）
- Test: `Core/Tests/GlimpseCoreTests/MosaicTests.swift`
- Modify: `App/Sources/Annotation/AnnotationCanvasView.swift`（4 处替换）
- Modify: `App/Sources/Overlay/OverlayContentView.swift`（2 处替换）
- Modify: `App/Sources/Overlay/SelectionView.swift`（1 处替换）
- Modify: `App/Sources/Toolbar/StylePaletteView.swift`（1 处替换）
- Modify: `App/Sources/Toolbar/ToolRollout.swift`（1 处替换）

要点：
- `MosaicSource` 把冻结画面缩小成「每块一个像素」的小图（缩小时 `.high` 插值，相当于按块取平均），按块大小缓存。绘制马赛克时用笔刷路径（圆头、宽度 = 笔刷直径）裁剪，再把小图以 `.none` 插值放大回原尺寸画进去，块边缘是硬的。
- 小图从冻结画面左上角对齐网格，所以各笔、屏幕和导出的块完全一致。画面尺寸不是块大小整数倍时，最后一行 / 列的块只覆盖一部分：先把整张图拉伸铺满小图，再按精确比例画一次，避免边缘块混进透明而发暗（有测试）。
- `CGContext.draw(_:in:)` 按 y 向上画图；在 y 向下的上下文里要先局部翻转，否则图是倒的（`drawUpright`，Task 9 的导出也用它）。
- 小图的位图先用冻结画面的色彩空间，建不出来退回 sRGB（同 `Renderer.crop`）；建失败也缓存（存 `nil`），不会每次重绘都重试。画面尺寸正好是块大小整数倍时不画拉伸的底图。
- 5K / 6K 画面生成小图要一点时间：选中马赛克工具时就预先生成（`prepareMosaic`），第一笔不卡。
- 隐私：`Renderer.draw` 的 `pixelated` 参数去掉默认值，调用方必须显式传入，免得漏传后马赛克区域被悄悄跳过、原文直接露出；拿不到小图时 `assertionFailure`（调试版直接暴露问题）。只有测试辅助 `TestImage.render` 保留自己的默认值。
- 二级栏的色块置灰时，VoiceOver 说明「马赛克不使用颜色」。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/MosaicTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

private let white: [UInt8] = [255, 255, 255, 255]

struct MosaicTests {
    /// A mosaic stroke over the whole 16 × 16 gradient, in 8-pixel blocks.
    private func mosaicOverGradient() -> CGImage {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        let stroke = Annotation(shape: .mosaic([CGPoint(x: 0, y: 8), CGPoint(x: 16, y: 8)], blockSize: 8),
                                color: RGBA(hex: 0), size: 40)
        return TestImage.render([stroke], width: 16, height: 16) { source.pixelated(blockSize: $0) }
    }

    @Test func eachBlockIsOneColour() {
        let image = mosaicOverGradient()
        let corner = TestImage.pixel(image, x: 0, y: 0)
        for (x, y) in [(7, 0), (0, 7), (7, 7), (3, 4)] {
            #expect(TestImage.pixel(image, x: x, y: y) == corner)
        }
        #expect(TestImage.pixel(image, x: 8, y: 0) != corner)
    }

    @Test func blocksAverageTheOriginalPixels() {
        // Source red = x, green = y: block (0, 0) averages 0...7, block (1, 1) averages 8...15.
        let image = mosaicOverGradient()
        let first = TestImage.pixel(image, x: 0, y: 0)
        let last = TestImage.pixel(image, x: 15, y: 15)
        #expect((2...5).contains(first[0]) && (2...5).contains(first[1]))
        #expect((10...13).contains(last[0]) && (10...13).contains(last[1]))
        #expect(first[3] == 255)
    }

    @Test func onlyTheBrushAreaChanges() {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        let dab = Annotation(shape: .mosaic([CGPoint(x: 3, y: 3)], blockSize: 4), color: RGBA(hex: 0), size: 4)
        let image = TestImage.render([dab], width: 16, height: 16) { source.pixelated(blockSize: $0) }
        #expect(TestImage.pixel(image, x: 3, y: 3) != white)
        #expect(TestImage.pixel(image, x: 12, y: 12) == white)
    }

    @Test func partialEdgeBlocksStayOpaque() throws {
        // 10 × 6 in 4-pixel blocks: 3 × 2 blocks, the last column and row only partly covered.
        let solid = TestImage.render([], width: 10, height: 6)
        let blocks = try #require(MosaicSource.pixelate(solid, blockSize: 4))
        #expect(blocks.width == 3 && blocks.height == 2)
        #expect(TestImage.pixel(blocks, x: 2, y: 1) == white)
    }

    @Test func pixelatedImageIsCachedPerBlockSize() {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        #expect(source.pixelated(blockSize: 4) === source.pixelated(blockSize: 4))
        #expect(source.pixelated(blockSize: 4) !== source.pixelated(blockSize: 8))
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter MosaicTests`
Expected: 编译失败，`cannot find 'MosaicSource' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Rendering/MosaicSource.swift`：

```swift
import CoreGraphics

/// The frozen frame pixelated into blocks, built once per block size. Mosaic strokes show this image
/// through their brush shape, so pixels always come from the original frame (design doc §3.4), blocks
/// sit on one grid anchored at the image's top-left (overlapping strokes line up), and the overlay and
/// the export see identical blocks.
// Not Sendable: one per overlay, used on the main thread only.
public final class MosaicSource {
    public let image: CGImage
    /// A failed build is cached as nil too, so a redraw never retries it.
    private var cache: [Int: CGImage?] = [:]

    public init(image: CGImage) {
        self.image = image
    }

    /// One pixel per block, `ceil(width / blockSize)` × `ceil(height / blockSize)`.
    public func pixelated(blockSize: Int) -> CGImage? {
        if let cached = cache[blockSize] { return cached }
        let result = Self.pixelate(image, blockSize: blockSize)
        cache[blockSize] = .some(result)
        return result
    }

    static func pixelate(_ image: CGImage, blockSize: Int) -> CGImage? {
        guard blockSize > 0 else { return nil }
        let width = (image.width + blockSize - 1) / blockSize
        let height = (image.height + blockSize - 1) / blockSize
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        // The frame's own colour space first (P3 stays P3), sRGB if that cannot back a bitmap.
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        guard let context = spaces.lazy.compactMap({
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: $0, bitmapInfo: bitmapInfo)
        }).first else { return nil }
        context.interpolationQuality = .high // averages each block when shrinking
        // When the size is not a multiple of the block, the last row / column of blocks is only partly
        // covered. Stretching the image underneath first fills that remainder with nearby colours
        // instead of transparency; the exact-scale draw on top then keeps the grid anchored at the top-left.
        if image.width % blockSize != 0 || image.height % blockSize != 0 {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scaledWidth = CGFloat(image.width) / CGFloat(blockSize)
        let scaledHeight = CGFloat(image.height) / CGFloat(blockSize)
        context.draw(image, in: CGRect(x: 0, y: CGFloat(height) - scaledHeight, width: scaledWidth, height: scaledHeight))
        return context.makeImage()
    }
}
```

`Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`：

（1）把

```swift
        case .mosaic, .text:
            break // drawn from Task 7 (mosaic) and Task 8 (text) on
        }
    }
```

替换为

```swift
        case .mosaic(let points, let blockSize):
            guard let blocks = pixelated(blockSize) else {
                assertionFailure("mosaic drawn without a pixelated source")
                break
            }
            // Clip to the brush stroke, then show the pixelated frame through it.
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(ShapeGeometry.smoothedPath(through: points))
            context.replacePathWithStrokedPath()
            context.clip()
            context.interpolationQuality = .none // hard block edges
            drawUpright(blocks, in: CGRect(x: 0, y: 0, width: blocks.width * blockSize,
                                           height: blocks.height * blockSize), context: context)
        case .text:
            break // drawn from Task 8 on
        }
    }

    /// `CGContext.draw(_:in:)` assumes y-up; in a y-down context it would draw the image upside down.
    static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }
```

（2）把

```swift
    /// `pixelated(blockSize)` returns the frozen frame pixelated in blocks of that size, for mosaic.
    public static func draw(_ annotations: [Annotation], in context: CGContext,
                            pixelated: (Int) -> CGImage? = { _ in nil }) {
```

替换为

```swift
    /// `pixelated(blockSize)` returns the frozen frame pixelated in blocks of that size, for mosaic.
    /// It has no default: a caller that forgot it would leave mosaicked areas unredacted.
    public static func draw(_ annotations: [Annotation], in context: CGContext,
                            pixelated: (Int) -> CGImage?) {
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter MosaicTests`
Expected: `Test run with 5 tests in 1 suite passed`

Run: `cd Core && swift test`
Expected: `Test run with 126 tests in 20 suites passed`

- [ ] **Step 5：接上界面**

`App/Sources/Annotation/AnnotationCanvasView.swift`（画布持有本屏的 `MosaicSource`，块大小 8pt）：

（1）把

```swift
    private let scale: CGFloat
    private let styleStore: AnnotationStyleStore

    init(frame: CGRect, scale: CGFloat, styleStore: AnnotationStyleStore) {
        self.scale = scale
        self.styleStore = styleStore
        super.init(frame: frame)
    }
```

替换为

```swift
    private let scale: CGFloat
    private let styleStore: AnnotationStyleStore
    /// Pixelated copies of this screen's frozen frame; mosaic shows them through the brush.
    let mosaicSource: MosaicSource
    /// Mosaic blocks are 8pt, in this screen's pixels.
    private var mosaicBlockSize: Int { max(1, Int((8 * scale).rounded())) }

    init(frame: CGRect, scale: CGFloat, image: CGImage, styleStore: AnnotationStyleStore) {
        self.scale = scale
        self.styleStore = styleStore
        mosaicSource = MosaicSource(image: image)
        super.init(frame: frame)
    }
```

（2）把

```swift
        draft = AnnotationDraft(tool: tool, start: pixels(point), color: color, size: size)
```

替换为

```swift
        draft = AnnotationDraft(tool: tool, start: pixels(point), color: color, size: size,
                                mosaicBlockSize: mosaicBlockSize)
```

（3）把

```swift
        Renderer.draw(visible.filter { $0.bounds.intersects(dirtyPixels) }, in: context)
```

替换为

```swift
        Renderer.draw(visible.filter { $0.bounds.intersects(dirtyPixels) }, in: context) { [mosaicSource] in
            mosaicSource.pixelated(blockSize: $0)
        }
```

（4）把

```swift
    // MARK: - Click tools
```

替换为

```swift
    /// Builds the pixelated frame before the first mosaic stroke, which would otherwise stall on 5K / 6K frames.
    func prepareMosaic() {
        _ = mosaicSource.pixelated(blockSize: mosaicBlockSize)
    }

    // MARK: - Click tools
```

`App/Sources/Overlay/SelectionView.swift`（选中马赛克时预先生成小图）：

（1）把

```swift
            phase = .editing(tool: tool)
            refreshHoverAtMouse() // cursor
```

替换为

```swift
            phase = .editing(tool: tool)
            if tool == .mosaic { canvas.prepareMosaic() }
            refreshHoverAtMouse() // cursor
```

`App/Sources/Toolbar/StylePaletteView.swift`（置灰的色块告诉 VoiceOver 原因）：

（1）把

```swift
                button.alphaValue = colorsEnabled ? 1 : 0.35
```

替换为

```swift
                button.alphaValue = colorsEnabled ? 1 : 0.35
                button.setAccessibilityHelp(colorsEnabled ? nil : "马赛克不使用颜色")
```

`App/Sources/Overlay/OverlayContentView.swift`（传入冻结画面；马赛克时色块置灰）：

（1）把

```swift
        canvas = AnnotationCanvasView(frame: frame, scale: captured.info.scale, styleStore: styleStore)
```

替换为

```swift
        canvas = AnnotationCanvasView(frame: frame, scale: captured.info.scale, image: captured.image, styleStore: styleStore)
```

（2）把

```swift
                    palette.show(canvas.style)
```

替换为

```swift
                    palette.show(canvas.style, colorsEnabled: tool != .mosaic)
```

`App/Sources/Toolbar/ToolRollout.swift`：

（1）把

```swift
    static let enabled: Set<Tool> = [.rectangle, .ellipse, .arrow, .pen, .counter]
```

替换为

```swift
    static let enabled: Set<Tool> = [.rectangle, .ellipse, .arrow, .pen, .counter, .mosaic]
```

- [ ] **Step 6：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

- [ ] **Step 7：手动检查（用户在真机上做）**

- 马赛克（M）：在文字上涂抹，涂过的地方变成方块，块大小一致（Retina 屏上每块约 8pt）；三档粗细对应三种笔刷宽度
- 来回涂同一处：块的位置不变、不会越涂越糊（像素取自原图）
- 先画一个红框，再用马赛克涂过红框：涂到的地方红框消失，露出原图的马赛克（§3.4「像素取自原图」）
- 选中马赛克时二级栏的 6 个色块是灰的，粗细可选；在马赛克上换粗细档后切回矩形，矩形也是这一档，颜色还是之前选的颜色
- 在屏幕右边缘 / 下边缘涂：边缘的块颜色正常，不发黑
- 在 5K / 4K 外接屏上涂：按 M 选中马赛克时可能有一次很短的停顿（预先生成像素化缓存），第一笔和之后都跟手；一笔涂很长也不变卡
- 马赛克拖到一半按 Esc：这一笔被丢弃，其他按键无效
- 开 VoiceOver，焦点移到置灰的色块：读出「马赛克不使用颜色」；换回其他工具后不再读这句

- [ ] **Step 8：停下，不 commit**

**批次 C 检查点：** 用户确认 Task 6、7 的手动检查，再进入批次 D。

---

## 批次 D：文字与输入层

### Task 8：文字工具 + 输入层

**Files:**
- Create: `Core/Sources/GlimpseCore/Annotation/TextAnnotation.swift`
- Modify: `Core/Sources/GlimpseCore/Annotation/Annotation.swift`（2 处替换）
- Modify: `Core/Sources/GlimpseCore/Annotation/TextLayout.swift`（1 处替换）
- Modify: `Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`（1 处替换）
- Test: `Core/Tests/GlimpseCoreTests/TextAnnotationTests.swift`
- Modify: `Core/Tests/GlimpseCoreTests/AnnotationModelTests.swift`（1 处替换）
- Create: `App/Sources/Annotation/AnnotationTextView.swift`
- Modify: `App/Sources/Annotation/AnnotationCanvasView.swift`（4 处替换）
- Modify: `App/Sources/Overlay/SelectionView.swift`（7 处替换）
- Modify: `App/Sources/Overlay/CaptureSessionController.swift`（1 处替换）
- Modify: `App/Sources/Toolbar/ToolbarView.swift`（1 处替换）
- Modify: `App/Sources/Overlay/OverlayContentView.swift`（3 处替换）
- Delete: `App/Sources/Toolbar/ToolRollout.swift`

**输入层怎么落到代码上**（§3.2.1 第一行）：
- 单击（文字工具、选区内）→ 画布在点击处打开一个 `AnnotationTextView`（`NSTextView` 子类），插到 `OverlayContentView` 里 `SelectionView` 之上、所有 chrome 之下（`canvas.lowestChromeView = sizeLabel`，用 `addSubview(_:positioned: .below, relativeTo:)`）：文本框能收到点击，工具栏、二级栏、尺寸标签、工具提示始终在它上面；然后 `SelectionView.phase = .typing`，并 `makeFirstResponder(文本框)`。文本框一创建就用解析好的字体、行高、颜色，不先放占位值再改。
- 文本框在遮罩上面：延伸到选区外的部分输入时不压暗，结束输入变成标注后才被遮罩压暗（导出时照样裁掉）。接受这个差别（决定 14）。
- 右键：`NSTextView` 默认弹出上下文菜单，右键到不了 `SelectionView.rightMouseDown`。所以文本框关掉上下文菜单（`menu(for:)` 返回 nil），`rightMouseDown` 调 `onRightClick`，`SelectionView` 把它接到 `delegate?.selectionViewDidRightClick(self)`，和在别处右键一样清除选区和标注（§3.2）。
- 文本框是第一响应者，**所有按键直接进文本框**：字母（含 R/O/A/P/T/M/N）照常输入，Enter 由 `NSTextView` 插入换行。这就是 `KeyRouter` 的 `.passToTextField`。Tab / ⇧Tab 什么都不输入（`insertTab` / `insertBacktab` 不做事），只有 Enter 换行。
- Esc：文本框的 `keyDown` 先问 `KeyRouter.route(_, phase: .typing)`，得到 `.endTyping` 就结束输入（输入法组字中除外：组字时所有按键都交给输入法）。
- ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z / ⇧⌘Z：菜单栏应用没有「编辑」菜单，这些快捷键平时靠菜单项分发，所以文本框在 `performKeyEquivalent` 里自己处理，只作用于文字。窗口会把快捷键先问一遍所有视图，所以只在自己是第一响应者时处理。其余 ⌘ 加字符键（⌘S、⌘R…）没人处理，会落到 `keyDown` 让 `NSTextView` 发出提示音，所以 `keyDown` 直接吞掉它们；⌘ 加方向键、删除键不是字符键，照常移动、删除。
- 工具栏的撤销 / 重做：输入期间同 ⌘Z / ⇧⌘Z，只作用于文本框（发给文本框的 `undoManager`），不结束输入；两个按钮的可用状态这时跟随文本框的撤销记录（文本框每次改动都刷新一次）。
- 点击文本框外部：`SelectionView.mouseDown` 在 `.typing` 阶段只调 `endTyping()` 然后返回，**不会**在点击处新建文本框（§3.2.1）。点工具栏其他按钮前也先结束输入。在**另一块屏**上单击也一样：那块屏处于选区阶段，按下鼠标前先问 `delegate?.selectionViewShouldBeginPress`；控制器发现有屏正在输入，就让它结束输入、把键盘还给它，并吞掉这次点击。不这样的话，那块屏会开始新选区，正在输入的屏会被连文字带标注一起清掉。
- 结束输入：文本框先交出键盘（`makeFirstResponder(nil)`，输入法借此结束会话、收起候选窗），然后移除；**还没上屏的组字丢弃**，和组字中按 Esc 一致。读取的是去掉组字部分的文字（`committedString`，在交出键盘之前读），所以结果不取决于输入法失去焦点时怎么处理组字；交出键盘时文本框还会 `discardMarkedText()` 通知输入法。只含空白就丢弃，否则变成一个 `.text` 标注（一个撤销步骤）；键盘焦点还给 `SelectionView`；文字工具保持选中。
- 改样式与撤销：输入中在二级栏改颜色 / 字号，整段文字立即跟着变。`NSTextView` 的撤销会把旧属性一起恢复，所以文本框每次改动后都按当前样式重刷整段（组字中不刷，免得冲掉输入法的标记，组字结束那次改动再刷）。
- 提交前后文字不动：文本框在点坐标里排版（系统字体、点字号、点行高），而中文、日文、emoji 等由系统换用的后备字体（PingFang、Hiragino、Apple Color Emoji）按**点字号**取大小；如果 Core 按像素字号排版，Retina 屏上这些字提交后会变宽或变窄（2× 屏 28pt 的「你好」差 2px，3× 屏 20pt 的两个 emoji 差 20px，40 个汉字差约 20px）。所以文字标注记下屏幕的缩放倍数（`.text(origin:string:scale:)`，`size` 仍是像素字号），Core 绘制时平移到起点、放大 `scale` 倍，再用点字号排版，和文本框是同一套排版；`bounds` 也按点排版的尺寸乘以 `scale`，上下各多留四分之一字号，罩住比固定行高更高的后备字形。基线：文本框固定用 TextKit 1（自己建 `NSTextStorage` / `NSLayoutManager` / `NSTextContainer`，用 `init(frame:textContainer:)`）。实测 TextKit 1 在固定行高（最小 = 最大行高）下把基线放在行底减去取整的下沉处，Core 也用这个公式（`TextLayout.baseline`：第 i 行 = (i + 1) × 行高 − 取整的下沉，点为单位）；但一行里出现后备字体时，TextKit 会把这一行的基线下移（中文实测下移 1pt），所以文本框做 `NSLayoutManager` 的代理，在 `shouldSetLineFragmentRect` 里把每行基线固定成这个值。在 1×、1.5×、2×、3×、14 / 20 / 28pt、多个非整数起点下逐像素比对过：拉丁字母、中文、中文标点、日文、韩文、带重音的字母、中英混排都完全重合；emoji 是位图字形，TextKit 会把它对齐到整像素，和 Core 最多差 1px 并有抗锯齿差别，接受。

**风险与退路（非激活面板里的文本输入）**：覆盖层是 `.nonactivatingPanel`、窗口层级 `.screenSaver`、应用从不激活。P1 已经证明这种窗口能成为 key window、能收键盘；`NSTextView` 在 key window 里能正常编辑和显示光标。两个风险：
1. **中文输入法候选窗被覆盖层挡住**：输入法候选窗的层级低于 `.screenSaver` 时，候选词会画在覆盖层后面看不见。候选窗的实际层级没有公开文档，Step 9 先用一个小脚本把它量出来；确实被挡就执行 Step 10 的退路：输入期间把这块屏的覆盖层降到「候选窗层级 − 1」（默认按弹出菜单层级 101 估计，量到别的值就用实测值），结束输入时恢复。
2. **文本框拿不到键盘**（理论上不会，因为 `SelectionView` 已经能拿到）：退路是不用独立 `NSTextView`，改用窗口的 field editor（`window.fieldEditor(true, for: nil)`）挂到同一位置，按键规则不变。只有 Step 9 发现打字无反应时才需要考虑，届时停下来和用户确认。
3. **输入法在非激活面板里根本不能组字**（拼音直接打出英文字母、没有候选）：这不是层级问题，Step 10 解决不了。出现时停下，把现象告诉用户，商量方案后再继续。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/TextAnnotationTests.swift`：

```swift
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import GlimpseCore

private let black = RGBA(hex: 0x000000)

/// Dark pixels of `image` in rows `rows`, across the whole width.
private func darkPixels(_ image: CGImage, rows: Range<Int>) -> Int {
    var n = 0
    for y in rows {
        for x in 0..<image.width where TestImage.pixel(image, x: x, y: y)[0] < 128 { n += 1 }
    }
    return n
}

private func bytes(_ image: CGImage) -> [UInt8] {
    Array(image.dataProvider!.data! as Data)
}

/// What the text box shows on a `scale` screen, built without TextLayout: the system font at the point
/// size, each baseline at the bottom of its fixed-height line minus the descent rounded to whole points
/// (the box tells TextKit to put it there), all scaled up to pixels.
private func boxEquivalent(_ string: String, origin: CGPoint, pointSize: CGFloat, scale: CGFloat,
                           width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    let font = CTFontCreateUIFontForLanguage(.system, pointSize, nil)!
    let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    for (index, line) in string.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !line.isEmpty {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: black.cgColor] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, String(line) as CFString, attributes)!
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(index + 1) * lineHeight - CTFontGetDescent(font).rounded())
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

struct TextAnnotationTests {
    @Test func blankTextBoxIsDropped() {
        #expect(Annotation.text(origin: .zero, string: "", color: black, size: 20, scale: 1) == nil)
        #expect(Annotation.text(origin: .zero, string: " \n\t", color: black, size: 20, scale: 1) == nil)
        #expect(Annotation.text(origin: .zero, string: "a\n", color: black, size: 40, scale: 2)?.shape
                == .text(origin: .zero, string: "a\n", scale: 2))
    }

    @Test func clickCentresTheFirstLine() {
        // 40 pixels on a 2x screen: a 20pt line, twice as tall in pixels.
        let origin = Annotation.textOrigin(forClickAt: CGPoint(x: 100, y: 100), fontSize: 40, scale: 2)
        #expect(origin == CGPoint(x: 100, y: 100 - TextLayout.lineHeight(fontSize: 20)))
    }

    @Test func textIsDrawnUpright() throws {
        // A "T": its bar (top of the capitals) is much wider than the foot of its stem (at the baseline).
        let annotation = try #require(Annotation.text(origin: .zero, string: "T", color: black, size: 40, scale: 1))
        let image = TestImage.render([annotation], width: 60, height: 60)
        let baseline = Int(TextLayout.baseline(line: 0, fontSize: 40))
        let capTop = baseline - Int(CTFontGetCapHeight(TextLayout.font(size: 40)).rounded())
        let bar = darkPixels(image, rows: capTop..<(capTop + 3))
        let foot = darkPixels(image, rows: (baseline - 3)..<baseline)
        #expect(bar > foot * 2)
    }

    @Test func secondLineStartsOneLineHeightLower() throws {
        let annotation = try #require(Annotation.text(origin: .zero, string: "\nT", color: black, size: 20, scale: 1))
        let image = TestImage.render([annotation], width: 40, height: 60)
        let lineHeight = Int(TextLayout.lineHeight(fontSize: 20))
        #expect(darkPixels(image, rows: 0..<lineHeight) == 0)
        #expect(darkPixels(image, rows: lineHeight..<(lineHeight * 2)) > 0)
    }

    @Test func baselineIsTheLineBottomMinusTheRoundedDescent() throws {
        let lineHeight = TextLayout.lineHeight(fontSize: 40)
        let descent = CTFontGetDescent(TextLayout.font(size: 40)).rounded()
        #expect(TextLayout.baseline(line: 1, fontSize: 40) == 2 * lineHeight - descent)
        // The renderer stands a "T" on that baseline.
        let annotation = try #require(Annotation.text(origin: .zero, string: "T", color: black, size: 40, scale: 1))
        let image = TestImage.render([annotation], width: 60, height: 60)
        let baseline = Int(TextLayout.baseline(line: 0, fontSize: 40))
        #expect(darkPixels(image, rows: (baseline - 2)..<baseline) > 0)
        #expect(darkPixels(image, rows: (baseline + 1)..<(baseline + 4)) == 0)
    }

    @Test func textIsLaidOutInPointsLikeTheTextBox() throws {
        // Fallback fonts (Chinese, Japanese, emoji) size themselves from the font size they are given, so
        // laying out at the pixel size would come out wider or narrower than the box on a Retina screen.
        let samples = ["中文标点，。！", "こんにちは", "😀👍", "Mixed 中英 text，ok！\nLine 2 第二行"]
        let origin = CGPoint(x: 3, y: 2.5)
        for scale in [1, 1.5, 2, 3] as [CGFloat] {
            for string in samples {
                let annotation = try #require(Annotation.text(origin: origin, string: string, color: black,
                                                              size: 20 * scale, scale: scale))
                let bounds = annotation.bounds
                let width = Int(bounds.maxX) + 20, height = Int(bounds.maxY) + 20
                let rendered = TestImage.render([annotation], width: width, height: height)
                #expect(bytes(rendered) == bytes(boxEquivalent(string, origin: origin, pointSize: 20, scale: scale,
                                                               width: width, height: height)))
                // The bounds cover every painted pixel, including fallback glyphs taller than the line.
                let pixels = bytes(rendered)
                var outside = 0
                for y in 0..<height {
                    for x in 0..<width where !bounds.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        let i = y * rendered.bytesPerRow + x * 4
                        if pixels[i..<(i + 3)].contains(where: { $0 < 250 }) { outside += 1 }
                    }
                }
                #expect(outside == 0, "\(string) at \(scale)x")
            }
        }
    }
}
```

`Core/Tests/GlimpseCoreTests/AnnotationModelTests.swift`（文字标注多了 `scale`）：

（1）把

```swift
        let one = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi"), color: red, size: 40)
        let two = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi\nthere"), color: red, size: 40)
        #expect(one.bounds.origin == CGPoint(x: 9, y: 19))
        #expect(two.bounds.height - one.bounds.height == TextLayout.lineHeight(fontSize: 40))
```

替换为

```swift
        // 40 pixels on a 2x screen: 20pt lines, scaled up.
        let one = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi", scale: 2), color: red, size: 40)
        let two = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi\nthere", scale: 2), color: red, size: 40)
        #expect(one.bounds.origin == CGPoint(x: 9, y: 9)) // a quarter of the size above, for tall fallback glyphs
        #expect(two.bounds.height - one.bounds.height == TextLayout.lineHeight(fontSize: 20) * 2)
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter TextAnnotationTests`
Expected: 编译失败，`type 'Annotation' has no member 'text'` / `has no member 'textOrigin'`，`extra argument 'scale' in call`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Annotation/TextAnnotation.swift`：

```swift
import CoreGraphics

extension Annotation {
    /// Where a text box opens for a click (pixels; `fontSize` in pixels on a screen with `scale` pixels per
    /// point): the first line is centred vertically on the click, so the caret appears where the user clicked.
    public static func textOrigin(forClickAt point: CGPoint, fontSize: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y - TextLayout.lineHeight(fontSize: fontSize / scale) * scale / 2)
    }

    /// The committed text annotation, or nil when the box holds only whitespace: an empty text box
    /// is dropped when typing ends (design doc §3.2.1).
    public static func text(origin: CGPoint, string: String, color: RGBA, size: CGFloat, scale: CGFloat) -> Annotation? {
        guard string.contains(where: { !$0.isWhitespace }) else { return nil }
        return Annotation(shape: .text(origin: origin, string: string, scale: scale), color: color, size: size)
    }
}
```

`Core/Sources/GlimpseCore/Annotation/Annotation.swift`（文字标注记下屏幕缩放倍数，按点排版）：

（1）把

```swift
        /// `origin` is the top-left of the first line; lines are split on newlines.
        case text(origin: CGPoint, string: String)
```

替换为

```swift
        /// `origin` is the top-left of the first line; lines are split on newlines. `scale` is the screen's
        /// pixels per point: the text is laid out at `size / scale` points and scaled up, like the text box it
        /// was typed in, because fallback fonts (Chinese, emoji, …) size themselves from the point size.
        case text(origin: CGPoint, string: String, scale: CGFloat)
```

（2）把

```swift
        case .text(let origin, let string):
            return CGRect(origin: origin, size: TextLayout.size(of: string, fontSize: size)).insetBy(dx: -1, dy: -1)
```

替换为

```swift
        case .text(let origin, let string, let scale):
            let points = TextLayout.size(of: string, fontSize: size / scale)
            // Fallback glyphs (Chinese, emoji) can stand out of the fixed-height lines by a fraction of the size.
            return CGRect(x: origin.x, y: origin.y, width: points.width * scale, height: points.height * scale)
                .insetBy(dx: -1, dy: -size / 4 - 1)
```

`Core/Sources/GlimpseCore/Annotation/TextLayout.swift`（基线改为行底对齐，跟 TextKit 1 一致）：

（1）把

```swift
    /// Distance from the top of a line to its baseline.
    public static func ascent(fontSize: CGFloat) -> CGFloat {
        CTFontGetAscent(font(size: fontSize))
    }
```

替换为

```swift
    /// Distance from the top of the text to the baseline of line `index` (0-based): the bottom of that
    /// fixed-height line minus the descent rounded to whole units. This is where TextKit 1 puts the baseline
    /// with a fixed line height; the text box also pins it there for lines with fallback fonts.
    /// The text is laid out in points, so this is in points too.
    public static func baseline(line index: Int, fontSize: CGFloat) -> CGFloat {
        CGFloat(index + 1) * lineHeight(fontSize: fontSize) - CTFontGetDescent(font(size: fontSize)).rounded()
    }
```

`Core/Sources/GlimpseCore/Rendering/AnnotationRenderer.swift`：

（1）把

```swift
        case .text:
            break // drawn from Task 8 on
        }
```

替换为

```swift
        case .text(let origin, let string, let scale):
            // Laid out in points and scaled up, exactly like the text box on screen (see Annotation.Shape.text).
            let pointSize = annotation.size / scale
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            for (index, text) in TextLayout.lines(of: string).enumerated() where !text.isEmpty {
                let baseline = CGPoint(x: 0, y: TextLayout.baseline(line: index, fontSize: pointSize))
                TextLayout.draw(TextLayout.line(text, fontSize: pointSize, color: color), baselineOrigin: baseline, in: context)
            }
        }
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter TextAnnotationTests`
Expected: `Test run with 6 tests in 1 suite passed`

Run: `cd Core && swift test`
Expected: `Test run with 132 tests in 21 suites passed`

- [ ] **Step 5：AnnotationTextView**

`App/Sources/Annotation/AnnotationTextView.swift`：

```swift
import AppKit
import GlimpseCore

/// The text box of the typing layer (design doc §3.2.1). While it is first responder every key goes
/// to it: letters type (R / T / … do not switch tools), Enter inserts a newline, ⌘C / ⌘V / ⌘X / ⌘A /
/// ⌘Z / ⇧⌘Z edit the text. Esc ends typing, unless an input method is composing, where Esc cancels
/// the composition first. Grows to fit its text; never wraps.
///
/// Pinned to TextKit 1 and laid out in points with the plain system font, like the committed annotation
/// (Core lays it out in points and scales it up). Every line's baseline is pinned to `TextLayout.baseline`:
/// TextKit would otherwise move it on lines where a fallback font (Chinese, emoji, …) appears.
final class AnnotationTextView: NSTextView, NSLayoutManagerDelegate {
    var onEndTyping: (() -> Void)?
    /// Right click on the box: same as anywhere else in the editing phase, clear and reselect (§3.2).
    var onRightClick: (() -> Void)?
    /// The text changed (typing, ⌘Z, …), so undo / redo availability may have too.
    var onTextChange: (() -> Void)?

    /// A text view built on a given text container does not own the text storage; this keeps it alive.
    private var ownedStorage: NSTextStorage?
    /// Font, colour and line height of all the text. Reapplied after every change, so undoing an edit made
    /// before a palette pick cannot bring the old style back.
    private var styleAttributes: [NSAttributedString.Key: Any] = [:]
    /// Distance from the top of each line to its baseline, in points.
    private var lineBaseline: CGFloat = 0

    /// `fontSize` is in points; line height and baselines are the committed annotation's,
    /// so the text does not move when typing ends.
    init(fontSize: CGFloat, color: NSColor) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: CGRect(x: 0, y: 0, width: 2, height: TextLayout.lineHeight(fontSize: fontSize)),
                   textContainer: container)
        ownedStorage = storage
        layoutManager.delegate = self
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isHorizontallyResizable = true
        isVerticallyResizable = true
        textContainerInset = .zero
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        apply(fontSize: fontSize, color: color)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // TextKit wants this initializer to exist on subclasses.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    /// Font size (points), colour and fixed line height, for the existing text and whatever is typed next.
    /// Also used when the palette changes the text tool's style mid-typing.
    func apply(fontSize: CGFloat, color: NSColor) {
        let lineHeight = TextLayout.lineHeight(fontSize: fontSize)
        lineBaseline = TextLayout.baseline(line: 0, fontSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        styleAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color, .paragraphStyle: paragraph]
        typingAttributes = styleAttributes
        // Not over a composition, which carries the input method's marking; didChangeText restyles after it.
        if !hasMarkedText() { restyleText() }
        insertionPointColor = color
        minSize = CGSize(width: 2, height: lineHeight)
        sizeToFit()
    }

    private func restyleText() {
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.setAttributes(styleAttributes, range: NSRange(location: 0, length: storage.length))
    }

    /// Pins every line's baseline where Core draws it (see the type's comment).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        baselineOffset.pointee = lineBaseline
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        if !hasMarkedText() { restyleText() }
        typingAttributes = styleAttributes
        sizeToFit()
        onTextChange?()
    }

    /// The text without what an input method is still composing. Ending typing drops an unfinished
    /// composition, as Esc does (design doc §3.2.1), so the result does not depend on the input method.
    var committedString: String {
        guard hasMarkedText() else { return string }
        return (string as NSString).replacingCharacters(in: markedRange(), with: "")
    }

    override func resignFirstResponder() -> Bool {
        if hasMarkedText() {
            // Dropped (see committedString); tell the input method too, so its candidate window closes.
            inputContext?.discardMarkedText()
            unmarkText()
        }
        return super.resignFirstResponder()
    }

    /// Enter is the only line break (design doc §3.4) and there are no tab stops: Tab and ⇧Tab type nothing.
    override func insertTab(_ sender: Any?) {}
    override func insertBacktab(_ sender: Any?) {}

    /// No context menu: a right click must reach the session's "clear selection and annotations".
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func keyDown(with event: NSEvent) {
        // While an input method composes, every key is its own: Esc cancels the composition, Enter confirms it.
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        let input = KeyInput(event: event)
        if KeyRouter.route(input, phase: .typing) == .endTyping {
            onEndTyping?()
            return
        }
        // ⌘ + a key that performKeyEquivalent does not map would only beep: nothing else acts on it while
        // typing. ⌘ with an arrow or Delete still moves and deletes.
        if input.command, case .character(let c) = input.key, c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol {
            return
        }
        super.keyDown(with: event)
    }

    /// A menu-bar app has no Edit menu, so the usual editing shortcuts are mapped here.
    /// The window offers key equivalents to every view, so only act while this view has the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, flags.contains(.command),
              !flags.contains(.option), !flags.contains(.control),
              case .character(let c) = KeyInput(event: event).key else {
            return super.performKeyEquivalent(with: event)
        }
        switch (c.lowercased(), flags.contains(.shift)) {
        case ("x", false): cut(nil)
        case ("c", false): copy(nil)
        case ("v", false): paste(nil)
        case ("a", false): selectAll(nil)
        case ("z", false): undoManager?.undo()
        case ("z", true): undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
```

- [ ] **Step 6：画布、SelectionView、控制器、工具栏接上输入层**

`App/Sources/Annotation/AnnotationCanvasView.swift`：

（1）把

```swift
        set { styleStore.style = newValue }
```

替换为

```swift
        set {
            styleStore.style = newValue
            restyleTextBox() // while typing, the open text box follows the palette
        }
```

（2）把

```swift
    private var draft: AnnotationDraft?
```

替换为

```swift
    private var draft: AnnotationDraft?
    /// The open text box while typing, and where its text goes in image pixels.
    private var textBox: AnnotationTextView?
    private var textOrigin: CGPoint = .zero
    /// The bottom-most chrome view in the overlay; text boxes are inserted just below it.
    weak var lowestChromeView: NSView?
```

（3）把

```swift
    // MARK: - Document
```

替换为

```swift
    // MARK: - Text (typing layer, design doc §3.2.1)

    /// Opens a text box at a click and returns it so the caller can give it the keyboard and wire its
    /// callbacks. The box goes in the overlay just below `lowestChromeView` (the canvas itself takes no
    /// input), so it receives clicks but the toolbar, palette and size label stay on top of it.
    func beginText(at point: CGPoint) -> AnnotationTextView? {
        guard let host = superview else { return nil }
        let (color, pixelSize) = resolvedStyle(for: .text)
        textOrigin = Annotation.textOrigin(forClickAt: pixels(point), fontSize: pixelSize, scale: scale)
        let box = AnnotationTextView(fontSize: pixelSize / scale, color: color.nsColor)
        box.frame.origin = CGPoint(x: textOrigin.x / scale, y: textOrigin.y / scale)
        box.onTextChange = { [weak self] in self?.onDocumentChange?() } // while typing, the toolbar's undo / redo follow the box
        textBox = box
        if let lowestChromeView, lowestChromeView.superview === host {
            host.addSubview(box, positioned: .below, relativeTo: lowestChromeView)
        } else {
            host.addSubview(box)
        }
        return box
    }

    /// While typing, undo / redo act on the text box only (design doc §3.2.1); nil when not typing.
    var textUndoManager: UndoManager? { textBox?.undoManager }

    /// Ends typing: adds the text as one annotation (one undo step), or drops a blank box.
    func commitText() {
        guard let box = textBox else { return }
        let string = box.committedString // read before the box resigns: an input method may still change it then
        closeTextBox()
        let (color, size) = resolvedStyle(for: .text)
        if let annotation = Annotation.text(origin: textOrigin, string: string, color: color, size: size, scale: scale) {
            add(annotation)
        }
    }

    private func closeTextBox() {
        guard let box = textBox else { return }
        textBox = nil
        // Give up the keyboard while the box is still in the window, so an input method ends its session and
        // closes its candidate window; an unfinished composition is dropped (see committedString).
        if box.window?.firstResponder === box { box.window?.makeFirstResponder(nil) }
        box.undoManager?.removeAllActions() // typing undo steps die with the box
        box.removeFromSuperview()
    }

    /// While typing, the open text box follows the palette. Its top-left stays put.
    private func restyleTextBox() {
        guard let box = textBox else { return }
        let (color, pixelSize) = resolvedStyle(for: .text)
        box.apply(fontSize: pixelSize / scale, color: color.nsColor)
    }

    // MARK: - Document
```

（4）把

```swift
    func removeAll() {
        draft = nil
```

替换为

```swift
    func removeAll() {
        closeTextBox() // right click while typing drops the text too
        draft = nil
```

`App/Sources/Overlay/SelectionView.swift`：

（1）把

```swift
    /// Right click. Whether it exits or clears the selection depends on all screens, so the controller decides.
    func selectionViewDidRightClick(_ view: SelectionView)
}
```

替换为

```swift
    /// Right click. Whether it exits or clears the selection depends on all screens, so the controller decides.
    func selectionViewDidRightClick(_ view: SelectionView)
    /// A press is about to start a selection on this screen. False swallows it: while another screen is typing,
    /// the click only ends typing there (design doc §3.2.1) instead of clearing that screen's text and selection.
    func selectionViewShouldBeginPress(_ view: SelectionView) -> Bool
}
```

（2）把

```swift
        case .selecting:
            // Computed here
```

替换为

```swift
        case .selecting:
            guard delegate?.selectionViewShouldBeginPress(self) ?? true else { return }
            // Computed here
```

（3）把

```swift
        case .typing:
            return // text annotations arrive in P2
```

替换为

```swift
        case .typing:
            endTyping() // a click outside the text box only ends typing; another click starts a new one (§3.2.1)
            return
```

（4）把

```swift
                case .counter:
                    canvas.placeCounter(at: point) // placed on press, so fast clicking never misses one
                    drag = .none
```

替换为

```swift
                case .counter:
                    canvas.placeCounter(at: point) // placed on press, so fast clicking never misses one
                    drag = .none
                case .text:
                    beginTyping(at: point)
                    drag = .none
```

（5）把

```swift
        case .selectTool(let tool):
            guard case .editing = phase, ToolRollout.enabled.contains(tool) else { return }
```

替换为

```swift
        case .selectTool(let tool):
            guard case .editing = phase else { return }
```

（6）把

```swift
        case .reselect, .copyColor, .passToTextField, .endTyping, .ignore:
            break // colour picking arrives in Task 10, typing in Task 8; reselect is decided by the controller
        }
    }
```

替换为

```swift
        case .endTyping:
            endTyping()
        case .reselect, .copyColor, .passToTextField, .ignore:
            break // colour picking arrives in Task 10; reselect is decided by the controller; the text box types
        }
    }

    // MARK: - Typing

    private func beginTyping(at point: CGPoint) {
        guard let box = canvas.beginText(at: point) else { return }
        box.onEndTyping = { [weak self] in self?.endTyping() }
        box.onRightClick = { [weak self] in
            guard let self else { return }
            self.delegate?.selectionViewDidRightClick(self)
        }
        phase = .typing
        window?.makeFirstResponder(box)
    }

    /// Commits the text box (a blank one is dropped; the box gives up the keyboard first, dropping an
    /// unfinished input-method composition) and gives the keyboard back to the selection.
    /// The text tool stays selected, as after any other annotation. No-op when not typing.
    func endTyping() {
        guard case .typing = phase else { return }
        canvas.commitText()
        phase = .editing(tool: .text)
        window?.makeFirstResponder(self)
    }
```

（7）把

```swift
        } else if tool != nil, selection.rect.contains(point) {
            NSCursor.crosshair.set()
```

替换为

```swift
        } else if let tool, selection.rect.contains(point) {
            (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
```

`App/Sources/Overlay/CaptureSessionController.swift`：

（1）把

```swift
    func selectionViewDidRightClick(_ view: SelectionView) {
```

替换为

```swift
    func selectionViewShouldBeginPress(_ view: SelectionView) -> Bool {
        // While typing, a click on another screen only ends typing (design doc §3.2.1); the keyboard goes back
        // to the screen with the selection, which the click had made key.
        guard let owner = overlays.first(where: { $0.selectionView.phase == .typing }) else { return true }
        owner.selectionView.endTyping()
        owner.makeKey()
        owner.makeFirstResponder(owner.selectionView)
        return false
    }

    func selectionViewDidRightClick(_ view: SelectionView) {
```

`App/Sources/Overlay/OverlayContentView.swift`：

（1）把

```swift
    private func refreshToolbarState() {
        toolbar.update(selectedTool: selectedTool, canUndo: canvas.document.canUndo, canRedo: canvas.document.canRedo)
    }
```

替换为

```swift
    private func refreshToolbarState() {
        // While typing, undo / redo belong to the text box (design doc §3.2.1).
        if let typing = canvas.textUndoManager {
            toolbar.update(selectedTool: selectedTool, canUndo: typing.canUndo, canRedo: typing.canRedo)
        } else {
            toolbar.update(selectedTool: selectedTool, canUndo: canvas.document.canUndo, canRedo: canvas.document.canRedo)
        }
    }
```

（2）把

```swift
    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem) {
        switch item {
```

替换为

```swift
    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem) {
        if let typing = canvas.textUndoManager, item == .undo || item == .redo {
            // Inside the text box, like ⌘Z / ⇧⌘Z; typing goes on (design doc §3.2.1).
            if item == .undo { typing.undo() } else { typing.redo() }
            refreshToolbarState()
            return
        }
        selectionView.endTyping() // any other button first ends typing, keeping the text (✓ then copies it)
        switch item {
```

（3）把

```swift
        canvas.onDocumentChange = { [weak self] in self?.refreshToolbarState() }
```

替换为

```swift
        canvas.onDocumentChange = { [weak self] in self?.refreshToolbarState() }
        canvas.lowestChromeView = sizeLabel // text boxes go under the chrome
```

`App/Sources/Toolbar/ToolbarView.swift`（7 个工具都已实现，不再按 `ToolRollout` 置灰）：

（1）把

```swift
    /// Selected tool, undo / redo availability, and which tools are usable yet (see ToolRollout).
    func update(selectedTool: Tool?, canUndo: Bool, canRedo: Bool) {
        let state = State(selectedTool: selectedTool, canUndo: canUndo, canRedo: canRedo)
        guard state != appliedState else { return } // layout runs often; the buttons rarely change
        appliedState = state
        for tool in Tool.allCases {
            buttons[.tool(tool)]?.isEnabled = ToolRollout.enabled.contains(tool)
            buttons[.tool(tool)]?.isSelectedTool = tool == selectedTool
```

替换为

```swift
    /// Selected tool and undo / redo availability.
    func update(selectedTool: Tool?, canUndo: Bool, canRedo: Bool) {
        let state = State(selectedTool: selectedTool, canUndo: canUndo, canRedo: canRedo)
        guard state != appliedState else { return } // layout runs often; the buttons rarely change
        appliedState = state
        for tool in Tool.allCases {
            buttons[.tool(tool)]?.isSelectedTool = tool == selectedTool
```

- [ ] **Step 7：删除 ToolRollout**

Run: `cd . && rm App/Sources/Toolbar/ToolRollout.swift && grep -rn ToolRollout App/Sources`
Expected: `grep` 没有输出（没有残留引用）

- [ ] **Step 8：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

- [ ] **Step 9：手动检查（用户在真机上做）**

按设计文档 §3.2.1 和 §8「按键分层」逐条：
- 7 个工具按钮全部可用
- 文字（T）：选区内是 I 形光标；单击出现闪烁的插入点，竖直位置在点击处
- 输入英文，包括 r o a p t m n 这些工具字母：全部作为文字输入，工具不切换
- Enter：换行，不完成截图；Tab / ⇧Tab：什么都不输入
- ⌘A 全选、⌘C 复制、⌘V 粘贴、⌘X 剪切、⌘Z / ⇧⌘Z：只作用于文本框里的文字；⌘S、⌘R 等其他 ⌘ 组合：没有效果（不保存、不切工具），也没有提示音；⌘← / ⌘→ 移到行首行尾、⌘⌫ 删到行首照常
- 输入中点工具栏的撤销 / 重做：只作用于文本框里的文字，输入继续（光标还在、能接着打字）；两个按钮的可用状态跟着文本框变（刚开始输入时撤销置灰，打字后可用，全部撤销后又置灰）
- Esc：结束输入，文字保留，工具仍是文字；再按 Esc：取消工具；再按 Esc：退出截图
- 输入中点击文本框外部：只结束输入，**不会**在点击处新建文本框；再点一次才新建
- 多屏：一块屏上正在输入时，在另一块屏上单击：只结束输入（文字保留、选区和标注都还在），另一块屏不开始新选区；键盘仍在原来那块屏（接着按 Esc 是取消文字工具）
- 什么都不输入就 Esc 或点外部：不留下任何东西，撤销栈里也没有多一步
- 结束输入的那一刻文字不跳动、不变宽变窄：在 1× 和 Retina 屏上各试三档字号，分别输入英文、中文（含「，。！」）、日文假名、emoji、中英混排的两行（逐像素比对过：除 emoji 可能上下差 1px 外应完全重合）
- 结束输入后 ⌘Z：整段文字一次撤销
- 输入中在二级栏改颜色 / 粗细：当前文本框的颜色和字号立即变化，键盘仍在文本框里；改完颜色再 ⌘Z：文字回退，颜色保持新的
- 输入中点 ✓：文字保留并结束输入，然后完成截图（Task 9 之前输出还不含标注）
- 输入中在文本框**外**右键、在文本框**上**右键：都是文本框和所有标注一起清除，回到选区阶段；文本框上右键不弹出系统的上下文菜单
- 输入时文本框不会盖住工具栏、二级栏、尺寸标签：在工具栏附近单击开始输入，打一长串让文字延伸到工具栏下面，工具栏仍在上层、仍能点
- 在选区右边缘附近打一长串让文字伸出选区：伸出去的部分输入时不压暗，结束输入后被遮罩压暗（预期，见决定 14）
- **中文输入法**（系统拼音）：输入 `nihao` 时出现候选窗且看得见、能选词上屏；组字过程中按 Esc 只取消组字，不结束输入；组字中按 Enter 上屏英文字母，不换行（上屏后再按 Enter 才换行）；组字中和上屏后按 ⌘Z 都只撤销文本框里的输入，不会撤掉已画的标注
- **组字中结束输入**：组字（候选窗开着）时点文本框外部、点工具栏按钮（如 ✓）、在另一块屏上单击：都结束输入，**还没上屏的组字丢弃**、已上屏的文字保留；候选窗随之消失，不残留在屏幕上
- 多行文字、深色外观下的白色文字显示正常
- **量候选窗层级**（不论候选窗看不看得见都做一次，把结果交给 agent）：在「终端」里运行下面的命令，然后在 10 秒内按 ⌘⇧A、选区、按 T、单击、用拼音输入 `nihao` 让候选窗出现，保持不动直到终端打印结果：

```bash
cat > "$TMPDIR/glimpse-list-windows.swift" <<'EOF'
// Prints every on-screen window with a layer above normal windows: layer, owner, bounds.
// Window titles need Screen Recording permission and are not used; owner name and layer do not.
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for entry in list {
    let layer = entry[kCGWindowLayer as String] as? Int ?? 0
    guard layer > 0 else { continue }
    let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
    let bounds = (entry[kCGWindowBounds as String] as? [String: Any]).map { "\($0["X"]!),\($0["Y"]!) \($0["Width"]!)×\($0["Height"]!)" } ?? ""
    print(String(format: "%6d  %@  %@", layer, owner, bounds))
}
EOF
sleep 10; swift "$TMPDIR/glimpse-list-windows.swift"
```

  每行是「层级 所属进程 位置尺寸」。`Glimpse` 那几行是覆盖层（层级 1000，即 `.screenSaver`）；候选窗那一行的所属进程是输入法（系统拼音一般是「简体中文输入法」「Pinyin」「TextInputMenuAgent」之类），位置在刚才输入处附近、尺寸是一条横向候选栏。记下它的层级 L：L < 1000 就会被覆盖层挡住，对应 Step 10。

- [ ] **Step 10（仅当 Step 9 发现输入法候选窗被挡住时执行）：输入期间降低覆盖层层级**

先看 Step 9 量到的候选窗层级 L：
- L = 101（`NSWindow.Level.popUpMenu`）：照下面的代码改，不用调整
- 25 < L < 1000 且 L ≠ 101：照下面的代码改，并把代码里的 `NSWindow.Level.popUpMenu.rawValue - 1` 换成数字 `L - 1`（菜单栏 / 状态栏是 24 / 25、Dock 是 20，所以降到 L − 1 仍能盖住它们）
- L ≥ 1000：候选窗本来就在覆盖层之上，看不见另有原因，不执行本步，停下来和用户确认
- L ≤ 25：降到它下面会露出菜单栏和 Dock，本步不适用，停下来和用户确认

在 `App/Sources/Overlay/SelectionView.swift` 里：

把

```swift
        phase = .typing
        window?.makeFirstResponder(box)
```

替换为

```swift
        phase = .typing
        // The input-method candidate window sits below .screenSaver (level measured in Task 8 Step 9); drop this
        // overlay just below it while typing (still above the menu bar and Dock) so the candidates stay visible.
        window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window?.makeFirstResponder(box)
```

把

```swift
        canvas.commitText()
        phase = .editing(tool: .text)
        window?.makeFirstResponder(self)
```

替换为

```swift
        canvas.commitText()
        phase = .editing(tool: .text)
        window?.level = .screenSaver
        window?.makeFirstResponder(self)
```

把

```swift
        canvas.removeAll() // annotations belong to the selection (design doc §3.2: right click clears both)
```

替换为

```swift
        canvas.removeAll() // annotations belong to the selection (design doc §3.2: right click clears both)
        window?.level = .screenSaver // typing may have lowered it
```

然后重新 `scripts/build.sh`，由用户重做 Step 9 的输入法检查。

- [ ] **Step 11：停下，不 commit**

**批次 D 检查点：** 用户确认 Task 8 的手动检查（特别是中文输入法），再进入批次 E。

---

## 批次 E：输出合成 + 放大镜

### Task 9：带标注的全分辨率输出

**Files:**
- Modify: `Core/Sources/GlimpseCore/Rendering/Renderer.swift`（整体替换）
- Test: `Core/Tests/GlimpseCoreTests/CompositeTests.swift`
- Modify: `App/Sources/Overlay/SelectionView.swift`（1 处替换）

要点：
- `Renderer.composite`：开一张选区大小的位图，CTM 设成「冻结画面像素、y 向下、选区左上角在原点」，先画整张冻结画面（裁剪区以外的部分自然落在位图外），再调 `Renderer.draw` 画标注。等价于「整屏合成后再裁剪」（§5.2），但不分配整屏大图。
- 保持 P1 的两条约定：结果是独立位图，不引用整屏冻结画面（复制到剪贴板的是小图，见 §1「数据不落盘」）；色彩空间跟冻结画面一致（P3 屏上仍是 Display P3），创建失败才退回 sRGB。
- 结果不透明：位图用 `noneSkipFirst`（冻结画面本来就不透明），导出的 PNG / TIFF 没有 alpha 通道，文件更小，也不会被当成透明图。剪贴板的延迟编码和保存都用 `NSBitmapImageRep(cgImage:)`，不用改；`MosaicSource` 的小图仍带 alpha，画进不透明位图没有影响。
- `crop` 改成「没有标注的 composite」，P1 的 5 个 `RendererTests` 原样通过。
- `composite` 的 `pixelated` 跟 `Renderer.draw` 一样没有默认值（漏传会让马赛克区域露出原文），`crop` 没有标注，显式传 `{ _ in nil }`。测试里用 `composite(_:_:cropTo:)` 辅助函数，按界面的方式从同一张画面建 `MosaicSource`。
- 马赛克块对齐整屏冻结画面的左上角，不对齐选区：选区从非块边界开始时，输出里的块边界仍落在画面坐标的块边界上（有测试）。
- 复制、保存、双击、Enter / ⌘C / ⌘S、✓ / 保存按钮都走 `SelectionView.finish`，改这一处就全部带上标注。`finish` 开头先 `endTyping()`：工具栏按钮本来就先结束输入，这里再兜一次底，以后新加的出口也不会丢掉打开着的文本框（输入中 Enter 是换行、⌘C 复制文本框里的文字，都不走 `finish`）。拖拽中除 Esc 外的按键都被忽略，所以正在画的草稿不会漏掉。
- 合成在主线程上做，做完才关覆盖层：6K 整屏选区约 80MB 位图、几十毫秒，可以接受，不另开线程；PNG 编码和写盘照旧在后台（`CaptureSessionController`）。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/CompositeTests.swift`：

```swift
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import GlimpseCore

private let red = RGBA(hex: 0xFF3B30)
private let redPixel: [UInt8] = [255, 59, 48, 255]

/// Rectangle stroke on the frame from (10, 10) to (30, 30), 2 pixels wide: its left edge covers x 9...11.
private let box = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: red, size: 2)

/// `Renderer.composite` the way the overlay calls it: mosaic blocks come from the same frame.
private func composite(_ frame: CGImage, _ annotations: [Annotation], cropTo rect: CGRect) throws -> CGImage {
    let source = MosaicSource(image: frame)
    return try #require(Renderer.composite(frame, annotations: annotations, toPixelRect: rect) {
        source.pixelated(blockSize: $0)
    })
}

struct CompositeTests {
    @Test func annotationsAreDrawnAtFullResolutionInsideTheCrop() throws {
        let frame = TestImage.gradient(width: 40, height: 40)
        let shot = try composite(frame, [box], cropTo: CGRect(x: 5, y: 5, width: 30, height: 30))
        #expect(shot.width == 30 && shot.height == 30)
        #expect(TestImage.pixel(shot, x: 5, y: 15) == redPixel)          // frame (10, 20): the left edge
        #expect(TestImage.pixel(shot, x: 15, y: 15) == [20, 20, 0, 255]) // frame (20, 20): untouched gradient
    }

    @Test func annotationsStayOnThePictureWhenTheSelectionMoves() throws {
        // Design doc §5.2 / §8: moving the selection does not move annotations relative to the picture.
        let frame = TestImage.gradient(width: 40, height: 40)
        let before = try composite(frame, [box], cropTo: CGRect(x: 0, y: 0, width: 40, height: 40))
        let after = try composite(frame, [box], cropTo: CGRect(x: 8, y: 8, width: 30, height: 30))
        #expect(TestImage.pixel(before, x: 10, y: 20) == redPixel)
        #expect(TestImage.pixel(after, x: 2, y: 12) == redPixel) // the same frame pixel (10, 20)
    }

    @Test func partsOutsideTheSelectionAreCropped() throws {
        let frame = TestImage.gradient(width: 40, height: 40)
        let shot = try composite(frame, [box], cropTo: CGRect(x: 20, y: 0, width: 20, height: 20))
        #expect(shot.width == 20 && shot.height == 20)
        #expect(TestImage.pixel(shot, x: 10, y: 15) == redPixel) // right edge, frame (30, 15)
        #expect(TestImage.pixel(shot, x: 5, y: 5) == [25, 5, 0, 255])
    }

    @Test func resultIsIndependentOpaqueAndKeepsTheFrameColourSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: p3, components: [0.2, 0.4, 0.6, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let frame = try #require(context.makeImage())
        let shot = try composite(frame, [box], cropTo: CGRect(x: 2, y: 2, width: 8, height: 8))
        #expect(shot.colorSpace?.name == CGColorSpace.displayP3)
        // Its own crop-sized buffer, not a window onto the 64 × 64 frame (which `CGImage.cropping` would keep).
        let shotBytes = try #require(shot.dataProvider?.data as Data?).count
        let frameBytes = try #require(frame.dataProvider?.data as Data?).count
        #expect(shotBytes == shot.bytesPerRow * shot.height)
        #expect(shotBytes * 8 <= frameBytes)
        // No alpha channel: the exported PNG / TIFF is opaque, like the screen it came from.
        #expect(shot.alphaInfo == .noneSkipFirst)
    }

    @Test func textLandsUprightAtItsPlaceInTheCrop() throws {
        // End to end on a 2x screen: a 20pt "T" at frame pixel (13, 11), cropped from (10, 8). The top of the
        // capital sits 2 × (baseline − cap height) pixels below the origin; a flipped or shifted text would
        // put ink in the rows above it, or the wide bar at the bottom instead of the top.
        let frame = TestImage.render([], width: 80, height: 80) // white
        let text = try #require(Annotation.text(origin: CGPoint(x: 13, y: 11), string: "T",
                                                color: RGBA(hex: 0x000000), size: 40, scale: 2))
        let shot = try composite(frame, [text], cropTo: CGRect(x: 10, y: 8, width: 60, height: 60))
        let font = TextLayout.font(size: 20)
        let baseline = 3 + Int(2 * TextLayout.baseline(line: 0, fontSize: 20))
        let capTop = 3 + Int((2 * (TextLayout.baseline(line: 0, fontSize: 20) - CTFontGetCapHeight(font))).rounded(.down))
        let ink = { (rows: Range<Int>) in
            rows.reduce(0) { n, y in n + (0..<shot.width).filter { TestImage.pixel(shot, x: $0, y: y)[0] < 128 }.count }
        }
        #expect(ink(0..<capTop) == 0)
        let bar = ink(capTop..<(capTop + 3))
        #expect(bar > 0)
        #expect(bar > ink((baseline - 3)..<baseline) * 2)
    }

    @Test func mosaicTakesPixelsFromTheOriginalNotFromAnnotationsBelowIt() throws {
        // A thick red box, then a mosaic over everything: no red survives, because mosaic samples the
        // original frame (design doc §3.4), whose blue channel is 0 everywhere.
        let frame = TestImage.gradient(width: 16, height: 16)
        let thick = Annotation(shape: .rectangle(CGRect(x: 4, y: 4, width: 8, height: 8)), color: red, size: 6)
        let mosaic = Annotation(shape: .mosaic([CGPoint(x: 0, y: 8), CGPoint(x: 16, y: 8)], blockSize: 4),
                                color: red, size: 40)
        let shot = try composite(frame, [thick, mosaic], cropTo: CGRect(x: 0, y: 0, width: 16, height: 16))
        for (x, y) in [(4, 4), (8, 4), (12, 12), (4, 10)] {
            #expect(TestImage.pixel(shot, x: x, y: y)[2] == 0)
        }
    }

    @Test func mosaicBlocksStayOnTheFrameGridWhenTheCropDoesNot() throws {
        // 8-pixel blocks are anchored at the frame's top-left, not the crop's. Cropping 17 × 13 from (3, 5)
        // puts the block edge at frame x = 8 on crop x = 5, frame x = 16 on crop x = 13, frame y = 8 on crop y = 3.
        let frame = TestImage.gradient(width: 24, height: 24)
        let mosaic = Annotation(shape: .mosaic([CGPoint(x: 0, y: 12), CGPoint(x: 24, y: 12)], blockSize: 8),
                                color: red, size: 60)
        let shot = try composite(frame, [mosaic], cropTo: CGRect(x: 3, y: 5, width: 17, height: 13))
        let pixel = { (x: Int, y: Int) in TestImage.pixel(shot, x: x, y: y) }
        #expect(pixel(0, 0) == pixel(4, 0))
        #expect(pixel(4, 0) != pixel(5, 0))
        #expect(pixel(5, 0) == pixel(12, 0))
        #expect(pixel(12, 0) != pixel(13, 0))
        #expect(pixel(0, 0) == pixel(0, 2))
        #expect(pixel(0, 2) != pixel(0, 3))
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter CompositeTests`
Expected: 编译失败，`type 'Renderer' has no member 'composite'`

- [ ] **Step 3：实现（整体替换 Renderer.swift）**

`Core/Sources/GlimpseCore/Rendering/Renderer.swift`：

```swift
import CoreGraphics

/// Turns a frozen screen image (plus annotations) into the final screenshot, at full pixel resolution.
public enum Renderer {
    /// `pixelRect` is in image pixels, top-left origin. Returns nil when nothing remains after clamping.
    public static func crop(_ image: CGImage, toPixelRect pixelRect: CGRect) -> CGImage? {
        composite(image, annotations: [], toPixelRect: pixelRect, pixelated: { _ in nil })
    }

    /// The frozen frame with `annotations` drawn over it, cut to `pixelRect` (image pixels, top-left origin).
    /// Same result as compositing the whole frame and cropping (design doc §5.2), but only the crop is
    /// allocated: the context is crop-sized and shifted, so annotations outside it are clipped away.
    /// The result is an independent, opaque bitmap in the frame's colour space (P3 stays P3): it holds no
    /// reference to the full frozen frame. Mosaic reads `pixelated`, which is built from the original frame;
    /// like `draw`, it has no default, so a caller cannot forget it and leave mosaicked areas unredacted.
    public static func composite(_ image: CGImage, annotations: [Annotation], toPixelRect pixelRect: CGRect,
                                 pixelated: (Int) -> CGImage?) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = pixelRect.integral.intersection(imageBounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        // Opaque, like the frozen frame: the PNG / TIFF then has no alpha channel (smaller, never read as transparent).
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in spaces {
            guard let context = CGContext(data: nil, width: Int(r.width), height: Int(r.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else { continue }
            context.interpolationQuality = .none
            // Image pixel space, y down, with the crop's top-left at the context's top-left.
            context.translateBy(x: 0, y: r.height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -r.minX, y: -r.minY)
            drawUpright(image, in: imageBounds, context: context)
            draw(annotations, in: context, pixelated: pixelated)
            if let result = context.makeImage() { return result }
        }
        return nil
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "CompositeTests|RendererTests"`
Expected: `Test run with 15 tests in 3 suites passed`（过滤串也匹配到 `AnnotationRendererTests`：5 + 7 + 3）

Run: `cd Core && swift test`
Expected: `Test run with 139 tests in 22 suites passed`

- [ ] **Step 5：输出改用合成**

`App/Sources/Overlay/SelectionView.swift`：

（1）把

```swift
    private func finish(_ action: OverlayFinishAction) {
        guard let selection = captureTarget else {
            NSSound.beep()
            return
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: selection.rect, scale: captured.info.scale)
        guard let image = Renderer.crop(captured.image, toPixelRect: pixels) else {
```

替换为

```swift
    private func finish(_ action: OverlayFinishAction) {
        endTyping() // an open text box is committed first, whichever path finishes (no-op when not typing)
        guard let selection = captureTarget else {
            NSSound.beep()
            return
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: selection.rect, scale: captured.info.scale)
        // Crop + annotations at full pixel resolution (design doc §3.2 step 4, §5.2). Runs on the main
        // thread before the overlay closes: a full 6K screen is a ~80MB bitmap and tens of ms. Accepted;
        // only PNG encoding and the disk write are moved off the main thread (by the session controller).
        guard let image = Renderer.composite(captured.image, annotations: canvas.document.annotations,
                                             toPixelRect: pixels,
                                             pixelated: { [canvas] in canvas.mosaicSource.pixelated(blockSize: $0) }) else {
```

- [ ] **Step 6：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

- [ ] **Step 7：手动检查（用户在真机上做）**

- 7 种标注各画一个，按 ✓：在「预览」里 ⌘N（从剪贴板新建），标注全在，位置和屏幕上一致；Retina 屏上图片是选区点数的 2 倍，线条边缘清晰（不是放大的低分辨率）
- 画一个标注一半在选区外：输出里只有选区内的一半
- 画好标注后移动选区再按 ✓：输出里标注在画面上的位置没变（跟着画面内容，不跟着选区）
- 保存按钮 / ⌘S：`~/Downloads` 里的 PNG 带标注；剪贴板里也是带标注的同一张图
- 无工具时双击选区、Enter、⌘C：都带标注
- 马赛克的输出与屏幕上看到的块完全一致（选区左上角不在块边界上时也一致）
- 文字的输出与屏幕上一致；P3 显示器上颜色没有偏（和屏幕上对比红色不发灰）
- 在外接 1 倍屏上画标注并输出：尺寸等于选区点数，标注粗细与屏幕一致
- 右键清除后重新选区直接 ✓：输出不含之前的标注
- 文字输入中直接点 ✓：输出里有这段文字
- 保存的 PNG 在「预览」→ 显示检查器里没有 alpha 通道（不透明）

- [ ] **Step 8：停下，不 commit**

---

### Task 10：放大镜 + 按 C / ⇧C 复制色值

**Files:**
- Create: `Core/Sources/GlimpseCore/Geometry/Magnifier.swift`
- Test: `Core/Tests/GlimpseCoreTests/MagnifierTests.swift`
- Modify: `Core/Sources/GlimpseCore/Input/EditorInput.swift`（2 处替换：⇧C）
- Modify: `Core/Tests/GlimpseCoreTests/KeyRouterTests.swift`（2 处替换）
- Create: `App/Sources/Overlay/MagnifierView.swift`
- Modify: `App/Sources/Overlay/SelectionView.swift`（7 处替换）
- Modify: `App/Sources/Overlay/OverlayContentView.swift`（5 处替换）

要点：
- 只在选区阶段显示（包括拖出选区的过程中）；进入编辑阶段、鼠标离开这块屏（`clearHover()` 由控制器在鼠标换屏时调用，借它隐藏）、或者另一块屏已经有选区时隐藏。
- 像素坐标 = 本地点 × 缩放倍数向下取整，夹在画面范围内（鼠标可以停在最后一行 / 列）。
- 色值先用 `cropping(to:)` 切出那一个像素，再画进 1×1 的 sRGB 位图读出来，由 CoreGraphics 做 P3 → sRGB 转换；不把整张 5K 画面拿去转换（每次鼠标移动都会取色）。放大镜显示三行：像素坐标、`RGB 255, 59, 48`、`#FF3B30`（第 16 条）。
- `KeyRouter` 在选区阶段已经把 C（不带 ⌘）路由为 `.copyColor`；本任务给它带上格式：C → `.copyColor(.hex)`，⇧C → `.copyColor(.rgb)`（只看 ⇧ 键：开着大写锁定按 C 仍是十六进制），然后实现它：复制色值文本（RGB 不带 `RGB` 前缀，方便直接粘贴），关闭覆盖层（第 17 条）。编辑阶段的 C / ⇧C 不是快捷键。

- [ ] **Step 1：写失败的测试**

`Core/Tests/GlimpseCoreTests/MagnifierTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct MagnifierTests {
    @Test func pixelUnderTheCursorOnRetinaIsClamped() {
        #expect(Magnifier.pixel(at: CGPoint(x: 10.7, y: 3.2), scale: 2, imageWidth: 100, imageHeight: 50) == CGPoint(x: 21, y: 6))
        #expect(Magnifier.pixel(at: CGPoint(x: 2000, y: -5), scale: 2, imageWidth: 100, imageHeight: 50) == CGPoint(x: 99, y: 0))
    }

    @Test func sourceIsCentredOnThePixel() {
        #expect(Magnifier.sourceRect(around: CGPoint(x: 20, y: 30)) == CGRect(x: 13, y: 23, width: 15, height: 15))
    }

    @Test func colourValueIsWrittenAsUppercaseHexOrRGB() throws {
        let image = TestImage.gradient(width: 32, height: 32) // pixel (x, y) = RGB(x, y, 0)
        let color = try #require(Magnifier.color(of: image, atPixel: CGPoint(x: 10, y: 20)))
        #expect(color.text(.hex) == "#0A1400")
        #expect(color.text(.rgb) == "10, 20, 0")
        #expect(Magnifier.color(of: image, atPixel: CGPoint(x: 31, y: 0))?.text(.hex) == "#1F0000")
        #expect(Magnifier.color(of: image, atPixel: CGPoint(x: 32, y: 0)) == nil)
    }

    @Test func panelSitsBelowRightOfTheCursor() {
        let frame = Magnifier.frame(size: CGSize(width: 120, height: 150), cursor: CGPoint(x: 100, y: 100),
                                    screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 120, y: 120, width: 120, height: 150))
    }

    @Test func panelTriesTheOtherSideWhenItWouldTouchTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = CGRect(x: 450, y: 0, width: 100, height: 40)
        let size = CGSize(width: 120, height: 150)
        // Below-right of a cursor at the left of the notch would sit under it; the left side is clear.
        #expect(Magnifier.frame(size: size, cursor: CGPoint(x: 440, y: 10), screen: screen, obstacle: notch)
                == CGRect(x: 300, y: 30, width: 120, height: 150))
        // No other side fits (above is off screen, left touches the notch): keep the first choice.
        #expect(Magnifier.frame(size: size, cursor: CGPoint(x: 500, y: 10), screen: screen, obstacle: notch)
                == CGRect(x: 520, y: 30, width: 120, height: 150))
    }

    @Test func panelFlipsAwayFromTheRightAndBottomEdges() {
        let frame = Magnifier.frame(size: CGSize(width: 120, height: 150), cursor: CGPoint(x: 950, y: 750),
                                    screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 810, y: 580, width: 120, height: 150))
    }
}
```

在 `Core/Tests/GlimpseCoreTests/KeyRouterTests.swift` 里做 2 处替换：

（1）把

```swift
        #expect(KeyRouter.route(char("c"), phase: phase) == .copyColor)
```

替换为

```swift
        #expect(KeyRouter.route(char("c"), phase: phase) == .copyColor(.hex))
```

（2）把

```swift
        #expect(KeyRouter.route(char("C"), phase: phase) == .copyColor)
    }
```

替换为

```swift
        #expect(KeyRouter.route(char("C"), phase: phase) == .copyColor(.hex)) // Caps Lock, no ⇧
    }

    @Test func shiftCCopiesTheRGBValueOnlyWhileSelecting() {
        #expect(KeyRouter.route(char("C", shift: true), phase: .selecting) == .copyColor(.rgb))
        #expect(KeyRouter.route(char("C", cmd: true, shift: true), phase: .selecting) == .finishCopy) // ⌘ wins
        #expect(KeyRouter.route(char("C", shift: true), phase: .editing(tool: nil)) == .ignore)
        #expect(KeyRouter.route(char("C", shift: true), phase: .editing(tool: .rectangle)) == .ignore)
    }
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "MagnifierTests|KeyRouterTests"`
Expected: 编译失败，`cannot find 'Magnifier' in scope`，以及 `.copyColor` 不接受参数

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Input/EditorInput.swift`：

（1）把

```swift
public enum EditorAction: Equatable, Sendable {
    case exit
    case reselect
    case selectFullScreen
    case copyColor
```

替换为

```swift
/// How C / ⇧C write the magnifier's colour as text (design doc §3.2).
public enum ColorFormat: Equatable, Sendable {
    /// `#FF3B30`
    case hex
    /// `255, 59, 48`
    case rgb
}

public enum EditorAction: Equatable, Sendable {
    case exit
    case reselect
    case selectFullScreen
    case copyColor(ColorFormat)
```

（2）把

```swift
            case ("c", false): return .copyColor
```

替换为

```swift
            case ("c", false): return .copyColor(input.shift ? .rgb : .hex)
```

`Core/Sources/GlimpseCore/Geometry/Magnifier.swift`：

```swift
import CoreGraphics
import Foundation

/// The selecting-phase magnifier (design doc §3.2): zoomed pixels around the cursor, its pixel
/// coordinate and colour value. Pixel coordinates are the frozen image's (top-left origin).
public enum Magnifier {
    /// Pixels shown per side; odd, so the cursor's pixel sits in the middle.
    public static let gridSize = 15
    /// Points per shown pixel.
    public static let zoom: CGFloat = 8
    /// Gap between the cursor and the panel.
    public static let cursorOffset: CGFloat = 20
    /// Colour values are reported in sRGB; made once, not on every mouse move.
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The pixel under a screen-local point, clamped into the image (the mouse can rest on the last row).
    public static func pixel(at point: CGPoint, scale: CGFloat, imageWidth: Int, imageHeight: Int) -> CGPoint {
        let x = min(max(Int((point.x * scale).rounded(.down)), 0), imageWidth - 1)
        let y = min(max(Int((point.y * scale).rounded(.down)), 0), imageHeight - 1)
        return CGPoint(x: x, y: y)
    }

    /// The `gridSize` square of pixels centred on `pixel`. It may reach past the image near an edge;
    /// that part is shown empty.
    public static func sourceRect(around pixel: CGPoint) -> CGRect {
        let half = CGFloat(gridSize / 2)
        return CGRect(x: pixel.x - half, y: pixel.y - half, width: CGFloat(gridSize), height: CGFloat(gridSize))
    }

    /// One pixel's colour in 8-bit sRGB.
    public struct PixelColor: Equatable, Sendable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        /// `#0A1400` (uppercase hex) or `10, 20, 0`.
        public func text(_ format: ColorFormat) -> String {
            switch format {
            case .hex: String(format: "#%02X%02X%02X", red, green, blue)
            case .rgb: "\(red), \(green), \(blue)"
            }
        }
    }

    /// One pixel's colour, converted to sRGB (what design tools and CSS expect); nil outside the image.
    /// The pixel is cut out first, so the colour conversion covers one pixel, not the whole frozen frame
    /// (this runs on every mouse move).
    public static func color(of image: CGImage, atPixel pixel: CGPoint) -> PixelColor? {
        let x = Int(pixel.x), y = Int(pixel.y)
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let single = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(single, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return PixelColor(red: rgba[0], green: rgba[1], blue: rgba[2])
    }

    /// Below-right of the cursor; flips to the left / above where it would leave the screen. When that
    /// would touch `obstacle` (the camera housing on a notch screen), the other flips are tried before
    /// giving up and keeping the first choice.
    public static func frame(size: CGSize, cursor: CGPoint, screen: CGRect, obstacle: CGRect? = nil) -> CGRect {
        let right = cursor.x + cursorOffset, left = cursor.x - cursorOffset - size.width
        let below = cursor.y + cursorOffset, above = cursor.y - cursorOffset - size.height
        let x = right + size.width > screen.maxX - OverlayLayout.screenMargin ? left : right
        let y = below + size.height > screen.maxY - OverlayLayout.screenMargin ? above : below
        let first = CGRect(origin: CGPoint(x: x, y: y), size: size)
        guard !OverlayLayout.isClear(first, of: obstacle) else { return first }
        let others = [CGRect(origin: CGPoint(x: x, y: y == below ? above : below), size: size),
                      CGRect(origin: CGPoint(x: x == right ? left : right, y: y), size: size),
                      CGRect(origin: CGPoint(x: x == right ? left : right, y: y == below ? above : below), size: size)]
        let fits = others.first { $0.minX >= screen.minX && $0.minY >= screen.minY
            && $0.maxX <= screen.maxX && $0.maxY <= screen.maxY && OverlayLayout.isClear($0, of: obstacle) }
        return fits ?? first
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "MagnifierTests|KeyRouterTests"`
Expected: `Test run with 15 tests in 2 suites passed`（6 + 9）

Run: `cd Core && swift test`
Expected: `Test run with 146 tests in 23 suites passed`

- [ ] **Step 5：MagnifierView**

`App/Sources/Overlay/MagnifierView.swift`：

```swift
import AppKit
import GlimpseCore

/// The selecting-phase magnifier next to the cursor (design doc §3.2): 15 × 15 frozen pixels at 8×,
/// the centre pixel outlined, then its pixel coordinate and colour value as RGB and hex. Clicks pass through.
final class MagnifierView: MaterialView {
    private let pixels: ZoomedPixelsView
    private let coordinateLabel = NSTextField(labelWithString: "")
    private let rgbLabel = NSTextField(labelWithString: "")
    private let hexLabel = NSTextField(labelWithString: "")
    private var shownPixel: CGPoint?

    init(image: CGImage) {
        let side = CGFloat(Magnifier.gridSize) * Magnifier.zoom
        pixels = ZoomedPixelsView(image: image, frame: CGRect(x: 6, y: 6, width: side, height: side))
        super.init(cornerRadius: 12)
        contentView.addSubview(pixels)
        for (index, label) in [coordinateLabel, rgbLabel, hexLabel].enumerated() {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .materialText
            label.frame = CGRect(x: 8, y: side + 10 + CGFloat(index) * 16, width: side - 4, height: 15)
            contentView.addSubview(label)
        }
        frame.size = CGSize(width: side + 12, height: side + 62) // three 16pt rows under the pixels
    }

    /// Shows the pixel at `pixel` (frozen-image coordinates). Moves within one pixel change nothing.
    func show(pixel: CGPoint) {
        guard pixel != shownPixel else { return }
        shownPixel = pixel
        pixels.center = pixel
        coordinateLabel.stringValue = "\(Int(pixel.x)), \(Int(pixel.y))"
        let color = Magnifier.color(of: pixels.image, atPixel: pixel)
        rgbLabel.stringValue = color.map { "RGB \($0.text(.rgb))" } ?? ""
        hexLabel.stringValue = color?.text(.hex) ?? ""
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Draws the zoomed pixels. Not flipped: CGImage drawing is y-up, so the maths stays plain.
private final class ZoomedPixelsView: NSView {
    let image: CGImage
    var center: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    init(image: CGImage, frame: CGRect) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        bounds.fill() // past the image edge
        let source = Magnifier.sourceRect(around: center)
        let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // cropping(to:) shares the frame's pixels; this small view never outlives the overlay.
        if !visible.isNull, let piece = image.cropping(to: visible) {
            let zoom = Magnifier.zoom
            context.interpolationQuality = .none
            context.draw(piece, in: CGRect(x: (visible.minX - source.minX) * zoom,
                                           y: (source.maxY - visible.maxY) * zoom,
                                           width: visible.width * zoom, height: visible.height * zoom))
        }
        // Outline the centre pixel: white inside black so it shows on any colour.
        let half = CGFloat(Magnifier.gridSize / 2)
        let cell = CGRect(x: half * Magnifier.zoom, y: half * Magnifier.zoom, width: Magnifier.zoom, height: Magnifier.zoom)
        NSColor.black.setStroke()
        NSBezierPath(rect: cell.insetBy(dx: -0.5, dy: -0.5)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: cell.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
```

- [ ] **Step 6：接上 SelectionView 和 OverlayContentView**

`App/Sources/Overlay/SelectionView.swift`：

（1）把

```swift
    /// True over the toolbar, where the cursor is the arrow.
    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool
}
```

替换为

```swift
    /// True over the toolbar, where the cursor is the arrow.
    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool
    /// Shows the magnifier for a screen-local point, or hides it (nil).
    func selectionView(_ view: SelectionView, moveMagnifierTo point: CGPoint?)
}
```

（2）把

```swift
    func refreshHoverAtMouse() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // Inclusive: the mouse can sit exactly on the last row/column of the screen.
        guard point.x >= bounds.minX, point.x <= bounds.maxX, point.y >= bounds.minY, point.y <= bounds.maxY else { return }
        updateHover(at: point)
        updateCursor(at: point)
    }
```

替换为

```swift
    func refreshHoverAtMouse() {
        guard let point = mouseLocation else {
            updateMagnifier(at: nil) // the mouse is on another screen
            return
        }
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
    }

    /// The mouse in this view's coordinates, or nil when it is on another screen.
    private var mouseLocation: CGPoint? {
        guard let window else { return nil }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // Inclusive: the mouse can sit exactly on the last row/column of the screen.
        guard point.x >= bounds.minX, point.x <= bounds.maxX, point.y >= bounds.minY, point.y <= bounds.maxY else { return nil }
        return point
    }

    /// The magnifier follows the mouse only while selecting (design doc §3.2), and not while another
    /// screen holds the selection. A selection on this screen while still selecting is the one being
    /// dragged out, which keeps the magnifier.
    private func updateMagnifier(at point: CGPoint?) {
        let visible = phase == .selecting && (hasSelection || (delegate?.selectionViewShouldShowHover(self) ?? true))
        chromeDelegate?.selectionView(self, moveMagnifierTo: visible ? point : nil)
    }
```

（3）把

```swift
    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
```

替换为

```swift
    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
```

（4）把

```swift
    func clearHover() {
        guard phase == .selecting, hoveredRect != nil else { return }
```

替换为

```swift
    func clearHover() {
        updateMagnifier(at: nil)
        guard phase == .selecting, hoveredRect != nil else { return }
```

（5）把

```swift
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
```

替换为

```swift
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
```

（6）把

```swift
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
```

替换为

```swift
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Still selecting while dragging out a selection; a drag can leave the screen, the magnifier cannot.
        updateMagnifier(at: CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                                    y: min(max(point.y, bounds.minY), bounds.maxY)))
```

（7）把

```swift
        case .reselect, .copyColor, .passToTextField, .ignore:
            break // colour picking arrives in Task 10; reselect is decided by the controller; the text box types
        }
    }
```

替换为

```swift
        case .copyColor(let format):
            copyColorUnderMouse(as: format)
        case .reselect, .passToTextField, .ignore:
            break // reselect is decided by the controller; while typing the text box gets the keys
        }
    }

    /// C / ⇧C while selecting: the magnifier's colour value goes to the clipboard as text (`#FF3B30` /
    /// `255, 59, 48`) and the capture ends, as Enter does with the image.
    private func copyColorUnderMouse(as format: ColorFormat) {
        guard let point = mouseLocation else {
            NSSound.beep()
            return
        }
        let pixel = Magnifier.pixel(at: point, scale: captured.info.scale,
                                    imageWidth: captured.image.width, imageHeight: captured.image.height)
        guard let color = Magnifier.color(of: captured.image, atPixel: pixel) else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.text(format), forType: .string)
        delegate?.selectionViewDidCancel(self)
    }
```

`App/Sources/Overlay/OverlayContentView.swift`：

（1）把

```swift
    private var toolbarSide: OverlayLayout.ToolbarPosition.Side = .below
```

替换为

```swift
    private var toolbarSide: OverlayLayout.ToolbarPosition.Side = .below
    private let magnifier: MagnifierView
```

（2）把

```swift
        canvas = AnnotationCanvasView(
```

替换为

```swift
        magnifier = MagnifierView(image: captured.image)
        canvas = AnnotationCanvasView(
```

（3）把

```swift
        for chrome in [sizeLabel, toolbar, palette, toolTipLabel] as [NSView] {
```

替换为

```swift
        for chrome in [sizeLabel, toolbar, palette, toolTipLabel, magnifier] as [NSView] {
```

（4）把

```swift
    func selectionViewDidChangeLayout(_ view: SelectionView) {
        layoutChrome()
        refreshToolbarState()
    }
```

替换为

```swift
    func selectionViewDidChangeLayout(_ view: SelectionView) {
        if view.phase != .selecting { magnifier.isHidden = true }
        layoutChrome()
        refreshToolbarState()
    }

    func selectionView(_ view: SelectionView, moveMagnifierTo point: CGPoint?) {
        guard let point else {
            magnifier.isHidden = true
            return
        }
        magnifier.show(pixel: Magnifier.pixel(at: point, scale: captured.info.scale,
                                              imageWidth: captured.image.width, imageHeight: captured.image.height))
        magnifier.frame = Magnifier.frame(size: magnifier.frame.size, cursor: point,
                                          screen: chromeArea, obstacle: notchObstacle)
        magnifier.isHidden = false
    }
```

（5）把

```swift
/// - the chrome on the shared material: size label, toolbar, style palette, toolbar tooltip
```

替换为

```swift
/// - the chrome on the shared material: size label, toolbar, style palette, toolbar tooltip, magnifier
```

- [ ] **Step 7：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行 `build/Build/Products/Debug/Glimpse.app`

- [ ] **Step 8：手动检查（用户在真机上做）**

- 按 ⌘⇧A：光标右下方立即出现放大镜（不用先动鼠标），玻璃材质、12pt 圆角
- 移动鼠标：放大的像素跟着变，中心格有黑白描边；下面三行依次是像素坐标（Retina 屏上大约是鼠标点坐标的 2 倍）、`RGB r, g, b`、`#RRGGBB`，三行都完整显示、不被截断（试一个三位数都很大的颜色，如白色 `RGB 255, 255, 255`）
- 鼠标移到屏幕右边缘 / 下边缘：放大镜翻到光标左边 / 上边，不出屏幕
- 在屏幕最左上角：坐标是 `0, 0`；越过画面边缘的格子显示黑色
- 把鼠标停在一块纯色（比如系统设置里的强调色色块）上按 C：覆盖层关闭；在任意文本框粘贴，得到 `#XXXXXX`；用「数码测色计」（选「以 sRGB 显示」）对比数值一致或只差 1
- 同一位置按 ⇧C：覆盖层关闭；粘贴得到 `r, g, b`（如 `255, 59, 48`，不带 `RGB` 前缀），与放大镜上那一行一致；开着大写锁定按 C（不按 ⇧）：仍复制十六进制
- 拖出选区的过程中放大镜继续跟随；松手进入编辑阶段：放大镜消失；右键回到选区阶段：放大镜重新出现
- 两块屏：鼠标在哪块屏，放大镜就在哪块屏，另一块屏上没有残留；一块屏有选区时，移到另一块屏上不显示放大镜
- 编辑阶段按 C 或 ⇧C：不复制色值（编辑阶段的 C 不是快捷键）
- 放大镜不挡鼠标：在放大镜下面按下拖动照样能画选区

- [ ] **Step 9：停下，不 commit**

**批次 E 检查点：** 用户确认 Task 9、10 的手动检查，再进入批次 F。

---

## 批次 F：收尾

### Task 11：收尾验证

- [ ] **Step 1：全部单元测试**

Run: `cd Core && swift test`
Expected: `Test run with 146 tests in 23 suites passed`

- [ ] **Step 2：干净编译**

Run: `cd . && rm -rf build && scripts/build.sh`
Expected: 没有错误、没有新增编译警告；最后一行输出 app 路径

- [ ] **Step 3：自查**

Run: `cd . && grep -rn "ToolRollout\|P2 restyles\|arrive in P2\|Task [0-9]" App/Sources Core/Sources`
Expected: 没有输出（中间任务留下的「Task N 再做」类注释都已在后续任务里替换掉；如有残留，按当前行为改写注释）

- [ ] **Step 4：交给用户做完整验收**

由用户按 Task 2、5、6、7、8、9、10 的手动检查清单走一遍，并补充：
- 两块不同缩放倍数的屏幕各完整走一遍（选区、工具栏位置、7 种标注、输出尺寸）
- 全屏应用上、其他桌面空间里截图，工具栏和二级栏都在覆盖层上、能点
- 日夜间各走一遍；macOS 26 液态玻璃（如有 macOS 14 / 15 机器：毛玻璃）
- 按键分层（§8）：输入文字时按 R / T、Enter、Esc、⌘Z；连点序号不会误触完成

- [ ] **Step 5：停下，不 commit**

汇报内容：改了哪些文件、测试结果（146 个）、编译结果、需要用户在真机上确认的清单、执行中发现的问题。

---

## 实施后修正（最终审查）

全部任务完成后的跨任务审查发现 8 处小问题，已修（测试 147 个，比 Step 5 多 1 个）：

1. 手柄：除选择阶段外都画（输入时手柄不响应，一点只结束输入）；`phase` 变化时重绘手柄区域，结束输入后不再缺半块。
2. 光标：输入阶段单独处理，文字框内不设光标（让 NSTextView 的 I 形光标生效），其余位置用箭头，不再和 I 形光标来回闪。
3. 按下未松或拖出选区途中按空格：`enterEditing` 清掉 `drag`，松开 / 拖动不再覆盖全屏选区（`.none` 时两者都不改选区）。
4. `close()`（如屏幕参数变化）先在每块屏上丢弃正在输入的文字框（`discardTyping`，交出键盘时输入法丢弃未完成的组字、关掉候选窗），再关窗。
5. 会话控制器抽出 `focus(_:)` 和 `selectionOwner`，替换各处重复写法；含边界的鼠标位置判断收成 Core 的 `CGRect.containsInclusive`（带测试），`present()` 和 `SelectionView.mouseLocation` 共用。
6. `AnnotationCanvasView.beginText`：去掉会把文字框放到工具栏上面的兜底 `addSubview`，缺少 `lowestChromeView` 时 `assertionFailure` 并返回 nil。
7. 注释与命名：`OverlayContentView` 的层级说明补上文字框（SelectionView 与 chrome 之间）；`selectionViewDidMouseEnter` 改名 `selectionViewMouseDidMove`，协议上写明每次移动都会调用、由接收方去重。
8. 文档：前言决定 4 改为尺寸标签圆角取 min(12, 半高)，接近胶囊，照视觉稿。
9. 真机反馈·放大镜：缩小为 13 × 13 像素 × 7 倍（面板 103 × 138，常量与 `panelSize` 收在 Core `Magnifier`，测试同步）；中心像素改为外围 1pt 强调色方框（去掉黑白双描边）；信息只留两行 `XY` 坐标 / `HEX` 色值，左标签右数值、两端对齐放大区；⇧C 仍复制 RGB。
10. 真机反馈·材质：macOS 26 只用原生 `NSGlassEffectView`（`.regular`、无 `tintColor`），不再叠淡色 / 描边 / 反光 / 投影（原投影从玻璃中部透出、显脏）；这些装饰只留给 macOS 14 / 15 毛玻璃。核对过祖先视图无遮罩、裁剪、阴影或透明度。
11. 真机反馈·选中按钮：macOS 26 去掉强调色光晕，只留强调色实底；14 / 15 保留。
12. 复审：放大镜面板位置按取整后的光标计算（触控板坐标带小数会让格子 / 方框 / 文字发虚，加测试）；坐标与色值改用 `monospacedSystemFont`（A–F 也等宽，右对齐不跳）；边缘翻转测试改用真实 `panelSize`；macOS 14 / 15 的毛玻璃和装饰收进只在回退时创建的私有 `EmulatedGlass`，macOS 26 上一个都不建；`ToolbarButton` 光晕相关的图层设置整段包在 `drawsGlow` 里。
13. 真机反馈·放大镜（纠正第 9 条）：恢复「+」十字线——竖线横线各 1pt、60% 强调色，贯穿放大区，压在中心列 / 行正中（7 = 3 + 1 + 3，整点对齐），停在中心像素的 1pt 强调色方框外，交叉处就是取色点（线段算在 Core `Magnifier.crosshairSegments`，有测试；`NSRect.fill()` 默认是复制而非叠加，半透明线要用 `fill(using: .sourceOver)`）。`XY` / `HEX` 改成「位置」/「颜色」，色值左边加 10pt 圆角色块；下面加两行提示「按 C 复制颜色值」「按 ⇧C 复制 RGB」。面板 103 × 167（新增 `hintGap` / `hintRowHeight` / `hintRowCount`、`infoRowY` / `hintRowY`，测试同步）。
14. 真机反馈·HUD（spec §3.8.1，原计划 P3 提前）：新增 `App/Sources/HUD/`（`HUDController` + `HUDView`）和 Core `HUDMessage` / `HUDLayout`（有测试）。复制 / 保存成功 / 保存失败 / 取色 / 截图失败 / 显示器变化都弹玻璃提示，出现在截图所在屏（失败时取鼠标所在屏）的下三分之一居中；覆盖层关闭后才显示，不抢焦点，2 秒后淡出，新提示替换旧的，「减弱动态效果」下不淡入淡出。保存在后台写完后回主线程再弹（`NSScreen` 不离开主线程）。取色改走新的委托 `selectionView(_:didCopyColor:)`，由会话控制器关窗后弹 HUD。原来的提示音由 HUD 取代，`NSLog` 保留。新截图开始前立即收起 HUD，免得被截进去。
15. 复审 HUD：文字按 `cell.cellSize` 计宽（`intrinsicContentSize` 不含标签两侧各 2pt 的内边距，原来文字被裁约 1.5pt、偏 2pt），标签左移 2pt；这个 2pt 收成共用的 `NSTextField.labelTextInset`，放大镜同用。HUD 最宽为屏宽减两边 24pt，超出中间省略。保存写完时若新一次截图已开始，提示记为 `pendingHUD`，在那次的 `close()` 里再显示（防止被截进去）。新截图前 HUD 在屏上时先等一个 runloop 再截。VoiceOver 播报改以 HUD 面板为来源。去掉 `HUDView` 多余的 `hitTest`（面板已 `ignoresMouseEvents`）。
16. 真机反馈·放大镜第二轮：面板太小、文字挤 → 放大区改为 17 × 17 像素 × 7 倍（119pt，7 为奇数，十字线仍在整点上），内边距 8、信息行 18（文字行内居中）、提示前空 6、提示行 14，面板 135 × 213；数值 12pt 等宽、标签 11pt、色块 12pt。去掉中心像素的强调色方框，十字线在中心连续相交；横线在交叉点断开 1pt，三段矩形互不重叠，60% 透明度不会在交叉点叠深（`Magnifier.crosshairSegments`，测试校验无重叠、总面积 = 2 × 119 − 1）。提示改成更淡的灰色常规字重（新增 `materialTertiaryText`，正文色 40%），并成一行要约 134pt 放不下，仍两行。日夜间：文字全用动态颜色，色块描边与十字线在 `viewDidChangeEffectiveAppearance` 重画；图像外的黑格表示「没有像素」，日夜间都保持黑色。

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| 输入法候选窗低于 `.screenSaver` 层级 | 中文输入时看不见候选词 | Task 8 Step 9 用脚本量出候选窗层级 L；被挡则执行 Step 10（输入期间降到 L − 1） |
| 输入法在非激活面板里根本不能组字 | 中文无法输入 | Step 10 解决不了；停下，与用户确认方案后再继续 |
| `NSTextView` 在非激活面板中拿不到键盘 | 文字工具不可用 | P1 已证明面板可成为 key；万一发生，改用 field editor，停下与用户确认 |
| `NSGlassEffectView` 在不激活的 `.screenSaver` 面板里的外观 | 玻璃可能显示为非活跃样式或采样不到冻结画面 | Task 2 手动检查确认；若效果不对，把 `MaterialView` 的 `#available(macOS 26, *)` 分支临时关掉退回毛玻璃，先保证可用，再和用户决定 |
| AppKit 工具提示窗口层级低于 `.screenSaver` | 系统提示被覆盖层挡住，悬停看不到名称和快捷键 | 不用 AppKit `toolTip`，工具提示由覆盖层自己用玻璃标签画（实施前说明第 19 条），Task 2 手动检查确认 |
| 文本框盖住工具栏 / 右键被文本框的上下文菜单吃掉 | 输入时点不到工具栏；右键不能清除 | 文本框插在 chrome 之下；关闭上下文菜单并把右键转给会话（Task 8） |
| `NSTextView` 与 CoreText 的基线位置有亚像素差 | 结束输入时文字轻微跳动 | 字体、字号、固定行高都取同一来源；提交后屏幕显示和导出走同一个 `Renderer.draw`，导出与提交后的屏幕一致 |
| 大屏首次使用马赛克要生成像素化缓存 | 第一次下笔短暂停顿 | 按块大小缓存，每次截图只生成一次；如真机上明显，可在选中马赛克工具时预生成（届时再加） |
| 每次鼠标拖动都重绘标注层 | 标注很多时卡顿 | 只重绘变化区域，并按 `bounds` 过滤不相交的标注 |
| 尺寸标签与工具栏在极窄选区时仍可能重叠 | 视觉上叠在一起 | 标签已避让上方工具栏；工具栏在选区内部时选区通常够大 |
