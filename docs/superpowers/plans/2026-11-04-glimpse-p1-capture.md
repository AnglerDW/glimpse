# Glimpse P1：截图主流程 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出一个能用的菜单栏截图工具：按 ⌘⇧A 冻结所有屏幕，悬停高亮窗口、单击选窗口、拖拽画选区、空格选整屏，选区可以移动、缩放、微调，Enter / ⌘C / 双击复制，⌘S 保存到「下载」。

**Architecture:** 纯逻辑放在 Swift Package `GlimpseCore`（坐标换算、选区模型、窗口命中、按键路由、裁剪、文件名、设置），用 `swift test` 做单元测试。界面放在 XcodeGen 生成的 macOS App 工程里（AppKit），依赖 `GlimpseCore`。截图用 ScreenCaptureKit，窗口层级用 `CGWindowListCopyWindowInfo`，全局快捷键用 Carbon。

**Tech Stack:** Swift 6.3 / Xcode 26.6、macOS 14+ 部署目标、AppKit、ScreenCaptureKit、Carbon HIToolbox、Swift Testing、XcodeGen。

**设计文档：** `docs/superpowers/specs/2026-11-04-glimpse-design.md`

**范围外（P2 / P3 再做）：** 工具栏与玻璃材质、标注、放大镜与取色、OCR、贴图、HUD、完整引导页、设置页、开机自动启动。本计划里的尺寸标签是临时的深色样式，P2 会换成玻璃材质。

**提交约定：** 用户要求不由 agent 执行 `git commit`。本计划不含提交步骤；每个任务结束时停下来，把改动交给用户检查。

---

## 文件结构

与设计文档第 7 节的差异：Package 放在 `Core/` 子目录，避免和 Xcode 工程根目录混在一起；界面代码放在 `App/Sources/` 下，由 XcodeGen 生成工程。

```
glimpse/
├─ project.yml                                # XcodeGen 工程定义
├─ scripts/
│  ├─ build.sh                                # 生成工程 → 编译 → 用 Apple Development 证书签名
│  └─ run.sh                                  # 结束旧进程 → build → 打开
├─ Core/                                      # Swift Package：GlimpseCore（纯逻辑，可单测）
│  ├─ Package.swift
│  ├─ Sources/GlimpseCore/
│  │  ├─ Geometry/CoordinateSpace.swift       # ScreenInfo；CG / AppKit / 屏幕本地 / 像素 坐标互转
│  │  ├─ Geometry/Selection.swift             # 选区模型：拖拽生成、移动、缩放、微调、手柄命中
│  │  ├─ Geometry/WindowHitTester.swift       # WindowInfo；按层级找鼠标下最上层普通窗口
│  │  ├─ Input/PointerGesture.swift           # 单击 / 拖拽 3pt 阈值
│  │  ├─ Input/EditorInput.swift              # Tool、EditorPhase、KeyInput、EditorAction、KeyRouter
│  │  ├─ Rendering/Renderer.swift             # 按像素矩形裁剪（P2 扩展为合成标注）
│  │  ├─ Output/ScreenshotFileName.swift      # 带毫秒的文件名
│  │  └─ Settings/SettingsStore.swift         # KeyCombo；截图快捷键、保存目录
│  └─ Tests/GlimpseCoreTests/
│     ├─ TestImage.swift                      # 测试用位图工具
│     ├─ CoordinateSpaceTests.swift
│     ├─ SelectionTests.swift
│     ├─ WindowHitTesterTests.swift
│     ├─ PointerGestureTests.swift
│     ├─ KeyRouterTests.swift
│     ├─ RendererTests.swift
│     ├─ ScreenshotFileNameTests.swift
│     └─ SettingsStoreTests.swift
└─ App/
   ├─ Info.plist                              # 由 XcodeGen 根据 project.yml 生成
   └─ Sources/
      ├─ main.swift                           # 入口，设置为菜单栏应用
      ├─ AppDelegate.swift                    # 组装各服务
      ├─ MenuBar/StatusItemController.swift   # 菜单栏图标和菜单
      ├─ Services/HotkeyService.swift         # Carbon 全局快捷键
      ├─ Services/ScreenRecordingPermission.swift  # 最小授权检查（P3 换成完整引导）
      ├─ Services/CaptureService.swift        # ScreenCaptureKit 冻结画面 + 窗口列表
      ├─ Services/OutputService.swift         # 剪贴板、保存 PNG
      └─ Overlay/
         ├─ CaptureSessionController.swift    # 一次截图会话：弹出 / 协调 / 关闭各屏覆盖层
         ├─ OverlayWindow.swift               # 每屏一个全屏无边框窗口
         ├─ OverlayContentView.swift          # 冻结画面 + 选区视图 两层
         ├─ SelectionView.swift               # 遮罩、高亮、选区、手柄、尺寸标签、鼠标键盘事件
         └─ KeyInput+NSEvent.swift            # NSEvent → KeyInput
```

---

> **实施后修订（2026-11-04）：** Task 1–6 已实施完毕，之后根据代码质量审查又做了修改。下面 Task 1–6 的代码块是修改前的原稿，**以 `Core/` 里的实际代码为准**。对后续任务有影响的接口变化如下：
> - `EditorPhase` 改为 `.selecting` / `.editing(tool: Tool?)` / `.typing` 三种状态
> - `KeyInput` 增加 `option`、`control` 两个参数，都有默认值；带 ⌥ 或 ⌃ 的按键（Esc 除外）一律忽略
> - `Selection.handle(at:)` 改为取离鼠标最近的手柄；`resize` 结果会限制在屏幕范围内
>
> Task 9、10 的代码已按新接口更新。
>
> **Task 7–8 同样在审查后做了修改，以 `App/`、`scripts/`、`project.yml` 的实际文件为准：**
> - `HotkeyService` 改为 `register(_:for: HotkeyAction, handler:) -> HotkeyRegistrationResult`，支持多个快捷键、按 ID 分发，注册失败时保留原有快捷键
> - `ScreenRecordingPermission` 只对外提供 `isGranted` 和 `requestOrOpenSettings()`
> - `StatusItemController` 新增 `updateCaptureShortcut(_:)`、`performAfterMenuCloses(_:)`
> - 构建脚本先编译后结束旧进程；项目的并发检查级别改为 `targeted`；新增 `README.md`
>
> **Task 9 审查后的修改：** `OverlayWindow` 改为不抢前台的 `NSPanel`，不再调用 `NSApp.activate()` / `NSApp.hide(nil)`；多屏并发截图；显示器不匹配时抛出 `CaptureError.displayMismatch`，显示器配置变化时关闭覆盖层；冻结画面改用 layer 显示，按屏幕色彩空间截取。

### Task 1：Core 包骨架 + 坐标换算

**Files:**
- Create: `Core/Package.swift`
- Create: `Core/Sources/GlimpseCore/Geometry/CoordinateSpace.swift`
- Test: `Core/Tests/GlimpseCoreTests/CoordinateSpaceTests.swift`

背景：macOS 有三套坐标系，这里统一换算。
- **CG 全局坐标**：`CGWindowListCopyWindowInfo` 用，原点在主屏左上角，y 向下。
- **AppKit 全局坐标**：`NSScreen.frame`、`NSEvent.mouseLocation` 用，原点在主屏左下角，y 向上。
- **屏幕本地坐标**：本应用自己定义，原点在某块屏幕的左上角，y 向下，单位是点。覆盖层视图（`isFlipped = true`）、选区、标注都用它。
- **像素坐标**：本地坐标 × 屏幕缩放倍数，对应冻结画面 `CGImage` 的像素（原点左上角）。

- [ ] **Step 1：创建 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlimpseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlimpseCore", targets: ["GlimpseCore"]),
    ],
    targets: [
        .target(name: "GlimpseCore"),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
    ]
)
```

- [ ] **Step 2：写失败的测试**

`Core/Tests/GlimpseCoreTests/CoordinateSpaceTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

/// Layout used by every test:
/// - primary: built-in 1728×1117 @2x at AppKit origin
/// - external: 2560×1440 @1x to the LEFT of primary, top edges aligned
///   (AppKit minY = 1117 - 1440 = -323; in CG global coords its top-left is (-2560, 0))
struct CoordinateSpaceTests {
    let primary = ScreenInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2)
    let external = ScreenInfo(displayID: 2, frame: CGRect(x: -2560, y: -323, width: 2560, height: 1440), scale: 1)
    let primaryHeight: CGFloat = 1117

    @Test func cgRectToAppKitRect() {
        let r = CoordinateSpace.appKitRect(fromCG: CGRect(x: 100, y: 50, width: 200, height: 100),
                                           primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 100, y: 967, width: 200, height: 100))
    }

    @Test func appKitPointToLocalOnExternalScreen() {
        // 60pt right of the external screen's left edge, 40pt below its top edge.
        let p = CoordinateSpace.localPoint(fromAppKit: CGPoint(x: -2500, y: 1077), in: external)
        #expect(p == CGPoint(x: 60, y: 40))
    }

    @Test func cgRectToLocalOnExternalScreen() {
        let r = CoordinateSpace.localRect(fromCG: CGRect(x: -2460, y: 30, width: 300, height: 200),
                                          in: external, primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 100, y: 30, width: 300, height: 200))
    }

    @Test func cgRectToLocalOnPrimaryIsIdentity() {
        let r = CoordinateSpace.localRect(fromCG: CGRect(x: 10, y: 20, width: 30, height: 40),
                                          in: primary, primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func localPointToCGGlobalOnExternalScreen() {
        let g = CoordinateSpace.cgGlobalPoint(fromLocal: CGPoint(x: 100, y: 30),
                                              in: external, primaryScreenHeight: primaryHeight)
        #expect(g == CGPoint(x: -2460, y: 30))
    }

    @Test func pixelRectOnRetinaSnapsOutwardToWholePixels() {
        let r = CoordinateSpace.pixelRect(fromLocal: CGRect(x: 10.25, y: 20.5, width: 100, height: 50), scale: 2)
        #expect(r == CGRect(x: 20, y: 41, width: 201, height: 100))
    }

    @Test func pixelRectOnNonRetinaIsUnchanged() {
        let r = CoordinateSpace.pixelRect(fromLocal: CGRect(x: 3, y: 4, width: 5, height: 6), scale: 1)
        #expect(r == CGRect(x: 3, y: 4, width: 5, height: 6))
    }
}
```

- [ ] **Step 3：运行测试，确认失败**

Run: `cd Core && swift test --filter CoordinateSpaceTests`
Expected: 编译失败，提示 `cannot find 'ScreenInfo' in scope` / `cannot find 'CoordinateSpace' in scope`

- [ ] **Step 4：实现**

`Core/Sources/GlimpseCore/Geometry/CoordinateSpace.swift`：

```swift
import CoreGraphics

/// One display. `frame` is in AppKit global coordinates (origin at the primary screen's
/// bottom-left, y up), in points. `scale` is the backing scale factor (2 on Retina).
public struct ScreenInfo: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
    }
}

/// Conversions between the coordinate systems Glimpse deals with.
///
/// - CG global: origin at the primary screen's top-left, y down (CGWindowList).
/// - AppKit global: origin at the primary screen's bottom-left, y up (NSScreen, NSEvent).
/// - Local: origin at one screen's top-left, y down, points (overlay views, selection).
/// - Pixel: local × scale, matching the captured CGImage (origin top-left).
public enum CoordinateSpace {
    public static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func localPoint(fromAppKit point: CGPoint, in screen: ScreenInfo) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
    }

    public static func localRect(fromAppKit rect: CGRect, in screen: ScreenInfo) -> CGRect {
        CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    public static func localRect(fromCG rect: CGRect, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGRect {
        localRect(fromAppKit: appKitRect(fromCG: rect, primaryScreenHeight: primaryScreenHeight), in: screen)
    }

    public static func cgGlobalPoint(fromLocal point: CGPoint, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: screen.frame.minX + point.x, y: primaryScreenHeight - (screen.frame.maxY - point.y))
    }

    /// Local points → pixel rect in the captured image, snapped outward to whole pixels
    /// so the crop never loses a partially covered pixel.
    public static func pixelRect(fromLocal rect: CGRect, scale: CGFloat) -> CGRect {
        let x0 = (rect.minX * scale).rounded(.down)
        let y0 = (rect.minY * scale).rounded(.down)
        let x1 = (rect.maxX * scale).rounded(.up)
        let y1 = (rect.maxY * scale).rounded(.up)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
```

- [ ] **Step 5：运行测试，确认通过**

Run: `cd Core && swift test --filter CoordinateSpaceTests`
Expected: `Test run with 7 tests in … passed`（7 个测试全部通过）

---

### Task 2：选区模型

**Files:**
- Create: `Core/Sources/GlimpseCore/Geometry/Selection.swift`
- Test: `Core/Tests/GlimpseCoreTests/SelectionTests.swift`

要点：选区始终在屏幕范围内；缩放时以**拖拽开始时的原始矩形**为基准计算，这样拖过对边时能正确翻转。

- [ ] **Step 1：写失败的测试**

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct SelectionTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func dragInAnyDirectionGivesStandardRect() {
        let s = Selection.fromDrag(start: CGPoint(x: 300, y: 200), end: CGPoint(x: 100, y: 50), bounds: bounds)
        #expect(s.rect == CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    @Test func dragIsClampedToScreen() {
        let s = Selection.fromDrag(start: CGPoint(x: 900, y: 700), end: CGPoint(x: 1200, y: 900), bounds: bounds)
        #expect(s.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func moveStopsAtScreenEdge() {
        var s = Selection(rect: CGRect(x: 10, y: 10, width: 100, height: 100), bounds: bounds)
        s.move(by: CGVector(dx: -50, dy: 20))
        #expect(s.rect == CGRect(x: 0, y: 30, width: 100, height: 100))
    }

    @Test func moveOriginKeepsSizeAndClamps() {
        var s = Selection(rect: CGRect(x: 10, y: 10, width: 100, height: 100), bounds: bounds)
        s.moveOrigin(to: CGPoint(x: 950, y: 750))
        #expect(s.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func nudgeByOneOrTenPoints() {
        var s = Selection(rect: CGRect(x: 100, y: 100, width: 50, height: 50), bounds: bounds)
        s.nudge(dx: 1, dy: 0, large: false)
        #expect(s.rect.origin == CGPoint(x: 101, y: 100))
        s.nudge(dx: 0, dy: -1, large: true)
        #expect(s.rect.origin == CGPoint(x: 101, y: 90))
    }

    @Test func resizeFromBottomRight() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.bottomRight, to: CGPoint(x: 400, y: 250), original: original)
        #expect(s.rect == CGRect(x: 100, y: 100, width: 300, height: 150))
    }

    @Test func resizePastOppositeEdgeFlips() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.left, to: CGPoint(x: 350, y: 999), original: original)
        #expect(s.rect == CGRect(x: 300, y: 100, width: 50, height: 100))
        s.resize(.left, to: CGPoint(x: 400, y: 0), original: original)
        #expect(s.rect == CGRect(x: 300, y: 100, width: 100, height: 100))
    }

    @Test func resizeIsClampedToScreen() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.topLeft, to: CGPoint(x: -50, y: -50), original: original)
        #expect(s.rect == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func handleHitTesting() {
        let s = Selection(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
        #expect(s.handle(at: CGPoint(x: 103, y: 98)) == .topLeft)
        #expect(s.handle(at: CGPoint(x: 200, y: 200)) == .bottom)
        #expect(s.handle(at: CGPoint(x: 300, y: 150)) == .right)
        #expect(s.handle(at: CGPoint(x: 200, y: 150)) == nil)
    }

    @Test func tinySelectionIsNotUsable() {
        #expect(!Selection(rect: CGRect(x: 0, y: 0, width: 50, height: 1), bounds: bounds).isUsable)
        #expect(Selection(rect: CGRect(x: 0, y: 0, width: 2, height: 2), bounds: bounds).isUsable)
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter SelectionTests`
Expected: 编译失败，`cannot find 'Selection' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Geometry/Selection.swift`：

```swift
import CoreGraphics

/// The eight resize handles around a selection.
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// A selection rectangle in screen-local points (top-left origin), always kept inside `bounds`.
public struct Selection: Equatable, Sendable {
    public private(set) var rect: CGRect
    public let bounds: CGRect

    public init(rect: CGRect, bounds: CGRect) {
        self.bounds = bounds
        self.rect = Selection.clamp(rect, to: bounds)
    }

    public static func fromDrag(start: CGPoint, end: CGPoint, bounds: CGRect) -> Selection {
        Selection(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                               width: abs(end.x - start.x), height: abs(end.y - start.y)),
                  bounds: bounds)
    }

    /// Too thin to be a real screenshot; treated as "no selection".
    public var isUsable: Bool { rect.width >= 2 && rect.height >= 2 }

    public mutating func moveOrigin(to origin: CGPoint) {
        let x = min(max(origin.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(origin.y, bounds.minY), bounds.maxY - rect.height)
        rect.origin = CGPoint(x: x, y: y)
    }

    public mutating func move(by delta: CGVector) {
        moveOrigin(to: CGPoint(x: rect.minX + delta.dx, y: rect.minY + delta.dy))
    }

    /// Arrow-key nudge: 1pt, or 10pt with Shift.
    public mutating func nudge(dx: Int, dy: Int, large: Bool) {
        let step: CGFloat = large ? 10 : 1
        move(by: CGVector(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step))
    }

    /// Moves `handle` to `point`, computed from `original` (the rect when the drag began),
    /// so dragging past the opposite edge flips the rect instead of collapsing it.
    public mutating func resize(_ handle: Handle, to point: CGPoint, original: CGRect) {
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
        var x0 = original.minX, x1 = original.maxX, y0 = original.minY, y1 = original.maxY
        switch handle {
        case .topLeft: x0 = p.x; y0 = p.y
        case .top: y0 = p.y
        case .topRight: x1 = p.x; y0 = p.y
        case .right: x1 = p.x
        case .bottomRight: x1 = p.x; y1 = p.y
        case .bottom: y1 = p.y
        case .bottomLeft: x0 = p.x; y1 = p.y
        case .left: x0 = p.x
        }
        rect = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }

    public static func handlePoint(_ handle: Handle, of r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .left: CGPoint(x: r.minX, y: r.midY)
        }
    }

    public func handle(at point: CGPoint, tolerance: CGFloat = 6) -> Handle? {
        Handle.allCases.first { h in
            let c = Selection.handlePoint(h, of: rect)
            return abs(c.x - point.x) <= tolerance && abs(c.y - point.y) <= tolerance
        }
    }

    private static func clamp(_ r: CGRect, to b: CGRect) -> CGRect {
        let i = r.standardized.intersection(b)
        return i.isNull ? CGRect(x: b.minX, y: b.minY, width: 0, height: 0) : i
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter SelectionTests`
Expected: `Test run with 10 tests in … passed`（10 个测试全部通过）

---

### Task 3：窗口命中 + 单击 / 拖拽判定

**Files:**
- Create: `Core/Sources/GlimpseCore/Geometry/WindowHitTester.swift`
- Create: `Core/Sources/GlimpseCore/Input/PointerGesture.swift`
- Test: `Core/Tests/GlimpseCoreTests/WindowHitTesterTests.swift`
- Test: `Core/Tests/GlimpseCoreTests/PointerGestureTests.swift`

- [ ] **Step 1：写失败的测试**

`WindowHitTesterTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct WindowHitTesterTests {
    // Front-to-back, as CGWindowListCopyWindowInfo returns them. Frames are CG global.
    let windows = [
        WindowInfo(windowID: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 33), layer: 25, ownerPID: 10),     // menu bar
        WindowInfo(windowID: 2, frame: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, ownerPID: 11),  // front
        WindowInfo(windowID: 3, frame: CGRect(x: 50, y: 50, width: 800, height: 600), layer: 0, ownerPID: 12),    // behind
    ]

    @Test func picksFrontmostNormalWindow() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 200, y: 200), in: windows)?.windowID == 2)
    }

    @Test func fallsThroughToWindowBehind() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 60, y: 60), in: windows)?.windowID == 3)
    }

    @Test func ignoresNonNormalLayers() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 10, y: 10), in: windows) == nil)
    }

    @Test func emptyAreaHitsNothing() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 1000, y: 1000), in: windows) == nil)
    }
}
```

`PointerGestureTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct PointerGestureTests {
    @Test func movementWithinThreePointsIsAClick() {
        #expect(!PointerGesture.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        #expect(!PointerGesture.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
    }

    @Test func movementBeyondThreePointsIsADrag() {
        #expect(PointerGesture.isDrag(from: .zero, to: CGPoint(x: 3, y: 1)))
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "WindowHitTesterTests|PointerGestureTests"`
Expected: 编译失败，`cannot find 'WindowInfo' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Geometry/WindowHitTester.swift`：

```swift
import CoreGraphics

/// An on-screen window. `frame` is in CG global coordinates (top-left origin).
public struct WindowInfo: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let layer: Int
    public let ownerPID: pid_t

    public init(windowID: CGWindowID, frame: CGRect, layer: Int, ownerPID: pid_t) {
        self.windowID = windowID
        self.frame = frame
        self.layer = layer
        self.ownerPID = ownerPID
    }
}

public enum WindowHitTester {
    /// `windows` must be ordered front-to-back (the order CGWindowListCopyWindowInfo returns).
    /// Only normal app windows (layer 0) can be picked; menu bar, Dock and desktop are skipped.
    public static func topmostWindow(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.layer == 0 && $0.frame.width > 1 && $0.frame.height > 1 && $0.frame.contains(point) }
    }
}
```

`Core/Sources/GlimpseCore/Input/PointerGesture.swift`：

```swift
import CoreGraphics

public enum PointerGesture {
    /// Moving no more than this between mouse-down and mouse-up counts as a click.
    public static let dragThreshold: CGFloat = 3

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "WindowHitTesterTests|PointerGestureTests"`
Expected: `Test run with 6 tests in … passed`（6 个测试全部通过）

---

### Task 4：按键路由（设计文档 3.2.1 的按键分层表）

**Files:**
- Create: `Core/Sources/GlimpseCore/Input/EditorInput.swift`
- Test: `Core/Tests/GlimpseCoreTests/KeyRouterTests.swift`

把设计文档 3.2.1 的表格逐条做成纯函数，界面只负责把 `NSEvent` 翻译成 `KeyInput`、执行返回的 `EditorAction`。P1 里还没有工具，但路由规则一次写全，P2 直接用。

- [ ] **Step 1：写失败的测试**

```swift
import Testing
@testable import GlimpseCore

private func key(_ k: KeyInput.Key, cmd: Bool = false, shift: Bool = false) -> KeyInput {
    KeyInput(key: k, command: cmd, shift: shift)
}

private func char(_ c: Character, cmd: Bool = false, shift: Bool = false) -> KeyInput {
    key(.character(c), cmd: cmd, shift: shift)
}

struct KeyRouterTests {
    // MARK: selecting phase
    @Test func selectingPhase() {
        let phase = EditorPhase.selecting
        #expect(KeyRouter.route(key(.escape), phase: phase) == .exit)
        #expect(KeyRouter.route(key(.space), phase: phase) == .selectFullScreen)
        #expect(KeyRouter.route(char("c"), phase: phase) == .copyColor)
        #expect(KeyRouter.route(key(.enter), phase: phase) == .ignore)
    }

    // MARK: editing, typing layer — every key belongs to the text box except Esc
    @Test func typingLayerOwnsKeys() {
        let phase = EditorPhase.editing(tool: .text, isTyping: true)
        #expect(KeyRouter.route(char("r"), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(key(.enter), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(char("z", cmd: true), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(char("c", cmd: true), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .endTyping)
    }

    // MARK: editing, tool selected
    @Test func toolLayer() {
        let phase = EditorPhase.editing(tool: .rectangle, isTyping: false)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .deselectTool)
        #expect(KeyRouter.route(char("r"), phase: phase) == .deselectTool)
        #expect(KeyRouter.route(char("a"), phase: phase) == .selectTool(.arrow))
        #expect(KeyRouter.route(key(.enter), phase: phase) == .finishCopy)
    }

    // MARK: editing, no tool
    @Test func noToolLayer() {
        let phase = EditorPhase.editing(tool: nil, isTyping: false)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .exit)
        #expect(KeyRouter.route(key(.enter), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("c", cmd: true), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("s", cmd: true), phase: phase) == .save)
        #expect(KeyRouter.route(char("z", cmd: true), phase: phase) == .undo)
        #expect(KeyRouter.route(char("Z", cmd: true, shift: true), phase: phase) == .redo)
        #expect(KeyRouter.route(char("t"), phase: phase) == .selectTool(.text))
        #expect(KeyRouter.route(char("N"), phase: phase) == .selectTool(.counter))
        #expect(KeyRouter.route(key(.arrow(dx: 1, dy: 0), shift: true), phase: phase) == .nudge(dx: 1, dy: 0, large: true))
        #expect(KeyRouter.route(key(.arrow(dx: 0, dy: -1)), phase: phase) == .nudge(dx: 0, dy: -1, large: false))
        #expect(KeyRouter.route(char("x"), phase: phase) == .ignore)
    }

    @Test func arrowsNudgeEvenWithToolSelected() {
        let phase = EditorPhase.editing(tool: .pen, isTyping: false)
        #expect(KeyRouter.route(key(.arrow(dx: -1, dy: 0)), phase: phase) == .nudge(dx: -1, dy: 0, large: false))
    }

    // MARK: mouse rules
    @Test func rightClickStepsBack() {
        #expect(KeyRouter.rightClick(phase: .selecting) == .exit)
        #expect(KeyRouter.rightClick(phase: .editing(tool: .arrow, isTyping: false)) == .reselect)
        #expect(KeyRouter.rightClick(phase: .editing(tool: nil, isTyping: false)) == .reselect)
    }

    @Test func doubleClickFinishesOnlyWithoutTool() {
        #expect(KeyRouter.doubleClickFinishes(phase: .editing(tool: nil, isTyping: false)))
        #expect(!KeyRouter.doubleClickFinishes(phase: .editing(tool: .counter, isTyping: false)))
        #expect(!KeyRouter.doubleClickFinishes(phase: .editing(tool: .text, isTyping: true)))
        #expect(!KeyRouter.doubleClickFinishes(phase: .selecting))
    }

    @Test func toolShortcuts() {
        #expect(Tool.allCases.map(\.shortcut) == ["r", "o", "a", "p", "t", "m", "n"])
        #expect(Tool(shortcut: "M") == .mosaic)
        #expect(Tool(shortcut: "q") == nil)
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter KeyRouterTests`
Expected: 编译失败，`cannot find 'KeyInput' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Input/EditorInput.swift`：

```swift
/// Annotation tools, in toolbar order.
public enum Tool: String, CaseIterable, Sendable {
    case rectangle, ellipse, arrow, pen, text, mosaic, counter

    public var shortcut: Character {
        switch self {
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .pen: "p"
        case .text: "t"
        case .mosaic: "m"
        case .counter: "n"
        }
    }

    public init?(shortcut: Character) {
        guard let lower = shortcut.lowercased().first,
              let tool = Tool.allCases.first(where: { $0.shortcut == lower }) else { return nil }
        self = tool
    }
}

public enum EditorPhase: Equatable, Sendable {
    /// No selection yet: hovering windows, dragging out a rect.
    case selecting
    /// Selection fixed. `tool == nil` means "no tool": the selection itself can be moved.
    case editing(tool: Tool?, isTyping: Bool)
}

public struct KeyInput: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case escape, enter, space
        /// Screen-local direction: dy = +1 is down.
        case arrow(dx: Int, dy: Int)
        case character(Character)
        case other
    }

    public var key: Key
    public var command: Bool
    public var shift: Bool

    public init(key: Key, command: Bool, shift: Bool) {
        self.key = key
        self.command = command
        self.shift = shift
    }
}

public enum EditorAction: Equatable, Sendable {
    case exit
    case reselect
    case selectFullScreen
    case copyColor
    case passToTextField
    case endTyping
    case selectTool(Tool)
    case deselectTool
    case finishCopy
    case save
    case undo
    case redo
    case nudge(dx: Int, dy: Int, large: Bool)
    case ignore
}

/// Implements the key layering table in the design doc (§3.2.1).
public enum KeyRouter {
    public static func route(_ input: KeyInput, phase: EditorPhase) -> EditorAction {
        switch phase {
        case .selecting:
            return routeSelecting(input)
        case .editing(let tool, let isTyping):
            if isTyping {
                return input.key == .escape && !input.command ? .endTyping : .passToTextField
            }
            if input.key == .escape {
                return tool == nil ? .exit : .deselectTool
            }
            return routeEditing(input, currentTool: tool)
        }
    }

    public static func rightClick(phase: EditorPhase) -> EditorAction {
        phase == .selecting ? .exit : .reselect
    }

    /// Double-click finishes only with no tool, so rapid clicks with the counter/pen tools never finish by accident.
    public static func doubleClickFinishes(phase: EditorPhase) -> Bool {
        phase == .editing(tool: nil, isTyping: false)
    }

    private static func routeSelecting(_ input: KeyInput) -> EditorAction {
        switch input.key {
        case .escape: return .exit
        case .space: return .selectFullScreen
        case .character(let c) where !input.command && c.lowercased() == "c": return .copyColor
        default: return .ignore
        }
    }

    private static func routeEditing(_ input: KeyInput, currentTool: Tool?) -> EditorAction {
        switch input.key {
        case .enter:
            return .finishCopy
        case .arrow(let dx, let dy):
            return .nudge(dx: dx, dy: dy, large: input.shift)
        case .character(let c):
            let lower = c.lowercased()
            if input.command {
                switch lower {
                case "c": return .finishCopy
                case "s": return .save
                case "z": return input.shift ? .redo : .undo
                default: return .ignore
                }
            }
            guard let tool = Tool(shortcut: c) else { return .ignore }
            return tool == currentTool ? .deselectTool : .selectTool(tool)
        default:
            return .ignore
        }
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter KeyRouterTests`
Expected: `Test run with 8 tests in … passed`（8 个测试全部通过）

---

### Task 5：裁剪 + 文件名

**Files:**
- Create: `Core/Sources/GlimpseCore/Rendering/Renderer.swift`
- Create: `Core/Sources/GlimpseCore/Output/ScreenshotFileName.swift`
- Create: `Core/Tests/GlimpseCoreTests/TestImage.swift`
- Test: `Core/Tests/GlimpseCoreTests/RendererTests.swift`
- Test: `Core/Tests/GlimpseCoreTests/ScreenshotFileNameTests.swift`

- [ ] **Step 1：写测试工具和失败的测试**

`TestImage.swift`：

```swift
import CoreGraphics
import Foundation

/// Bitmap helpers for pixel-exact tests. Coordinates are top-left origin, like CGImage rows.
enum TestImage {
    /// Pixel (x, y) has RGBA = (x, y, 0, 255).
    static func gradient(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(x)
                bytes[i + 1] = UInt8(y)
                bytes[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// RGBA of pixel (x, y).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 4)
        out.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            // CGContext is bottom-left origin: shift so that image row `y` (from top) lands on row 0.
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return out
    }
}
```

`RendererTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct RendererTests {
    @Test func cropsExactPixels() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 2, y: 3, width: 4, height: 2)))
        #expect(cropped.width == 4)
        #expect(cropped.height == 2)
        #expect(TestImage.pixel(cropped, x: 0, y: 0) == [2, 3, 0, 255])
        #expect(TestImage.pixel(cropped, x: 3, y: 1) == [5, 4, 0, 255])
    }

    @Test func cropIsClampedToImage() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 6, y: 6, width: 10, height: 10)))
        #expect(cropped.width == 2)
        #expect(cropped.height == 2)
    }

    @Test func emptyCropReturnsNil() {
        let image = TestImage.gradient(width: 8, height: 8)
        #expect(Renderer.crop(image, toPixelRect: CGRect(x: 20, y: 20, width: 5, height: 5)) == nil)
    }
}
```

`ScreenshotFileNameTests.swift`：

```swift
import Foundation
import Testing
@testable import GlimpseCore

struct ScreenshotFileNameTests {
    @Test func includesMilliseconds() {
        // 2026-11-04 17:30:05.500 UTC
        let date = Date(timeIntervalSince1970: 1_793_813_405.5)
        let name = ScreenshotFileName.make(for: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Glimpse 2026-11-04 17.30.05.500.png")
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "RendererTests|ScreenshotFileNameTests"`
Expected: 编译失败，`cannot find 'Renderer' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Rendering/Renderer.swift`：

```swift
import CoreGraphics

/// Turns a frozen screen image into the final screenshot.
/// P1 only crops; P2 adds compositing annotations on the full frame before cropping.
public enum Renderer {
    /// `pixelRect` is in image pixels, top-left origin. Returns nil when nothing remains after clamping.
    public static func crop(_ image: CGImage, toPixelRect pixelRect: CGRect) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = pixelRect.integral.intersection(imageBounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return image.cropping(to: r)
    }
}
```

`Core/Sources/GlimpseCore/Output/ScreenshotFileName.swift`：

```swift
import Foundation

public enum ScreenshotFileName {
    /// e.g. "Glimpse 2026-11-04 17.30.05.123.png". Milliseconds avoid clashes when saving twice in one second.
    public static func make(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return "Glimpse \(formatter.string(from: date)).png"
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test --filter "RendererTests|ScreenshotFileNameTests"`
Expected: `Test run with 4 tests in … passed`（4 个测试全部通过）

---

### Task 6：设置存储（截图快捷键、保存目录）

**Files:**
- Create: `Core/Sources/GlimpseCore/Settings/SettingsStore.swift`
- Test: `Core/Tests/GlimpseCoreTests/SettingsStoreTests.swift`

P1 只需要截图快捷键和保存目录；识别文字快捷键和开机自动启动在 P3 加。

- [ ] **Step 1：写失败的测试**

```swift
import Foundation
import Testing
@testable import GlimpseCore

struct SettingsStoreTests {
    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "glimpse-tests-\(UUID().uuidString)")!)
    }

    @Test func defaultHotkeyIsCommandShiftA() {
        // kVK_ANSI_A = 0; Carbon cmdKey = 0x100, shiftKey = 0x200
        #expect(KeyCombo.defaultScreenshot == KeyCombo(keyCode: 0, modifiers: 0x0300))
    }

    @Test func defaults() {
        let store = makeStore()
        #expect(store.screenshotHotkey == .defaultScreenshot)
        #expect(store.saveDirectory.lastPathComponent == "Downloads")
    }

    @Test func hotkeyCanBeChangedAndCleared() {
        let store = makeStore()
        let combo = KeyCombo(keyCode: 18, modifiers: 0x0100)
        store.screenshotHotkey = combo
        #expect(store.screenshotHotkey == combo)
        store.screenshotHotkey = nil
        #expect(store.screenshotHotkey == nil)
    }

    @Test func saveDirectoryPersists() {
        let store = makeStore()
        store.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        #expect(store.saveDirectory.path == "/tmp/shots")
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter SettingsStoreTests`
Expected: 编译失败，`cannot find 'SettingsStore' in scope`

- [ ] **Step 3：实现**

`Core/Sources/GlimpseCore/Settings/SettingsStore.swift`：

```swift
import Foundation

/// A global shortcut in Carbon terms: virtual key code + Carbon modifier flags
/// (cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000).
public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧A
    public static let defaultScreenshot = KeyCombo(keyCode: 0, modifiers: 0x0100 | 0x0200)
}

public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let screenshotHotkey = "screenshotHotkey"
        static let saveDirectory = "saveDirectory"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` means the user cleared the shortcut.
    public var screenshotHotkey: KeyCombo? {
        get {
            guard let data = defaults.data(forKey: Key.screenshotHotkey) else { return .defaultScreenshot }
            do {
                return try JSONDecoder().decode(KeyCombo?.self, from: data)
            } catch {
                return .defaultScreenshot
            }
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.screenshotHotkey)
        }
    }

    public var saveDirectory: URL {
        get { defaults.url(forKey: Key.saveDirectory) ?? SettingsStore.defaultSaveDirectory }
        set { defaults.set(newValue, forKey: Key.saveDirectory) }
    }

    public static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
```

- [ ] **Step 4：运行全部 Core 测试**

Run: `cd Core && swift test`
Expected: 全部通过（7 + 10 + 6 + 8 + 4 + 4 = 39 个测试）

---

### Task 7：App 工程骨架 + 菜单栏图标

**Files:**
- Create: `project.yml`
- Create: `scripts/build.sh`、`scripts/run.sh`
- Create: `App/Sources/main.swift`
- Create: `App/Sources/AppDelegate.swift`
- Create: `App/Sources/MenuBar/StatusItemController.swift`
- Create: `.gitignore`

本任务及之后的界面任务没有自动化测试（设计文档第 8 节约定），验证方式是编译 + 按步骤手动检查。

- [ ] **Step 1：创建 project.yml**

```yaml
name: Glimpse
options:
  bundleIdPrefix: com.anglerdw
  deploymentTarget:
    macOS: "14.0"
packages:
  GlimpseCore:
    path: Core
targets:
  Glimpse:
    type: application
    platform: macOS
    sources:
      - App/Sources
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: Glimpse
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.anglerdw.glimpse
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.0"
        SWIFT_STRICT_CONCURRENCY: minimal
        ENABLE_HARDENED_RUNTIME: NO
    dependencies:
      - package: GlimpseCore
    scheme: {}
```

`LSUIElement: true` 让应用不出现在 Dock，只在菜单栏。App 层用 Swift 5 语言模式，避免 AppKit / Carbon 回调在 Swift 6 严格并发检查下产生大量噪音；Core 包仍是 Swift 6 模式。

- [ ] **Step 2：创建构建脚本**

`scripts/build.sh`：

```bash
#!/bin/bash
# Generate the Xcode project, build Debug, then sign with the Apple Development certificate.
# A stable signature keeps the Screen Recording permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet build

APP="build/Build/Products/Debug/Glimpse.app"
codesign --force --deep --sign "Apple Development" "$APP"
echo "$APP"
```

`scripts/run.sh`：

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Glimpse || true
APP="$(scripts/build.sh | tail -1)"
open "$APP"
```

`.gitignore`：

```
build/
Glimpse.xcodeproj/
App/Info.plist
Core/.build/
.superpowers/
.DS_Store
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 3：创建入口和菜单栏**

`App/Sources/main.swift`：

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`App/Sources/AppDelegate.swift`：

```swift
import AppKit
import GlimpseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(onCapture: {
            NSLog("Glimpse: capture requested")
        })
    }
}
```

`App/Sources/MenuBar/StatusItemController.swift`：

```swift
import AppKit

final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: () -> Void

    init(onCapture: @escaping () -> Void) {
        self.onCapture = onCapture
        super.init()
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glimpse")

        let menu = NSMenu()
        let capture = NSMenuItem(title: "截图", action: #selector(captureClicked), keyEquivalent: "a")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Glimpse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func captureClicked() {
        // Let the menu finish fading out so it doesn't end up in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [onCapture] in onCapture() }
    }
}
```

- [ ] **Step 4：编译运行**

Run: `cd . && scripts/run.sh`
Expected: 输出 `build/Build/Products/Debug/Glimpse.app`，没有编译错误。

- [ ] **Step 5：手动检查**

- 菜单栏出现取景框图标，Dock 里没有 Glimpse
- 点图标，菜单显示「截图 ⇧⌘A」「退出 Glimpse」
- 点「截图」，`log stream --predicate 'process == "Glimpse"' --level default` 里能看到 `Glimpse: capture requested`
- 点「退出 Glimpse」，图标消失

---

### Task 8：全局快捷键 + 最小授权检查

**Files:**
- Create: `App/Sources/Services/HotkeyService.swift`
- Create: `App/Sources/Services/ScreenRecordingPermission.swift`
- Modify: `App/Sources/AppDelegate.swift`

- [ ] **Step 1：HotkeyService**

```swift
import Carbon.HIToolbox
import GlimpseCore

/// Registers one global shortcut through Carbon. Carbon only reports a conflict when another
/// program registered the same combo globally; app menu shortcuts cannot be detected (design doc §3.1).
final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Returns false when the combo could not be registered.
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.action?() }
            return noErr
        }, 1, &spec, userData, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x474C_4D50), id: 1) // 'GLMP'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }
}
```

- [ ] **Step 2：最小授权检查**（P3 换成完整引导页）

`App/Sources/Services/ScreenRecordingPermission.swift`：

```swift
import AppKit

enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Calling this once makes Glimpse appear in System Settings › Screen Recording.
    static func request() { _ = CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3：在 AppDelegate 里接上快捷键**

把 `App/Sources/AppDelegate.swift` 整体替换为：

```swift
import AppKit
import GlimpseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let hotkeys = HotkeyService()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(onCapture: { [weak self] in self?.startCapture() })
        if let combo = settings.screenshotHotkey,
           !hotkeys.register(combo, action: { [weak self] in self?.startCapture() }) {
            NSLog("Glimpse: failed to register screenshot hotkey")
        }
    }

    private func startCapture() {
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.request()
            ScreenRecordingPermission.openSystemSettings()
            return
        }
        NSLog("Glimpse: capture requested (permission granted)")
    }
}
```

- [ ] **Step 4：编译运行 + 手动检查**

Run: `cd . && scripts/run.sh`

- 第一次按 ⌘⇧A：弹出系统授权提示，或系统设置自动打开到「屏幕录制」页，列表里有 Glimpse
- 打开 Glimpse 的开关。如果系统提示「退出并重新打开」，照做；或执行 `scripts/run.sh` 重启
- 再按 ⌘⇧A：日志出现 `capture requested (permission granted)`
- 在 Finder 里按 ⌘⇧A，触发的是 Glimpse，不是「前往应用程序」（预期行为，设计文档 3.1 已说明）
- 再执行一次 `scripts/run.sh` 重新编译，按 ⌘⇧A **不会**再次要求授权（证明签名稳定）

---

### Task 9：冻结画面 + 覆盖层

**Files:**
- Create: `App/Sources/Services/CaptureService.swift`
- Create: `App/Sources/Overlay/OverlayWindow.swift`
- Create: `App/Sources/Overlay/OverlayContentView.swift`
- Create: `App/Sources/Overlay/SelectionView.swift`（本任务先放最小版本）
- Create: `App/Sources/Overlay/CaptureSessionController.swift`
- Modify: `App/Sources/AppDelegate.swift`

- [ ] **Step 1：CaptureService**

```swift
import AppKit
import GlimpseCore
import ScreenCaptureKit

struct CapturedScreen {
    let info: ScreenInfo
    let image: CGImage
    let nsScreen: NSScreen
}

struct CaptureResult {
    let screens: [CapturedScreen]
    /// Front-to-back, CG global frames, excluding Glimpse's own windows.
    let windows: [WindowInfo]
    let primaryScreenHeight: CGFloat
}

enum CaptureError: Error {
    case noDisplays
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
final class CaptureService {
    /// Capture first, show overlays afterwards, so the overlay never appears in the image (design doc §3.2).
    func captureAll() async throws -> CaptureResult {
        let windows = Self.onScreenWindows()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        var captured: [CapturedScreen] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            captured.append(CapturedScreen(
                info: ScreenInfo(displayID: id, frame: screen.frame, scale: screen.backingScaleFactor),
                image: image,
                nsScreen: screen))
        }

        guard !captured.isEmpty, let primary = NSScreen.screens.first else { throw CaptureError.noDisplays }
        return CaptureResult(screens: captured, windows: windows, primaryScreenHeight: primary.frame.height)
    }

    /// ScreenCaptureKit's window list has no z-order; CGWindowList returns windows front-to-back.
    static func onScreenWindows() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            // Some apps keep fully transparent layer-0 windows on screen; they must not be snapped to.
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            return WindowInfo(windowID: number, frame: bounds, layer: layer, ownerPID: pid)
        }
    }
}
```

说明：原稿按屏幕依次截取。代码审查后已改成 `withThrowingTaskGroup` 并发截取（符合设计文档），以实际文件为准。

- [ ] **Step 2：OverlayWindow 和 OverlayContentView**

`App/Sources/Overlay/OverlayWindow.swift`：

```swift
import AppKit
import GlimpseCore

/// One borderless full-screen window per display. Must be able to become key,
/// otherwise Esc / Enter / letter keys go to the previously active app (design doc §5.1).
final class OverlayWindow: NSWindow {
    let selectionView: SelectionView

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        let content = OverlayContentView(captured: captured, windows: windows, primaryScreenHeight: primaryScreenHeight)
        selectionView = content.selectionView
        super.init(contentRect: captured.nsScreen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        contentView = content
        setFrame(captured.nsScreen.frame, display: false)
        initialFirstResponder = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

`App/Sources/Overlay/OverlayContentView.swift`：

```swift
import AppKit
import GlimpseCore

/// Bottom: the frozen screen image (layer-backed, cheap to keep on screen).
/// Top: SelectionView, which draws the dim / selection and handles all input.
final class OverlayContentView: NSView {
    let selectionView: SelectionView

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        let frame = CGRect(origin: .zero, size: captured.info.frame.size)
        selectionView = SelectionView(frame: frame, captured: captured, windows: windows,
                                      primaryScreenHeight: primaryScreenHeight)
        super.init(frame: frame)

        let imageView = NSImageView(frame: frame)
        imageView.image = NSImage(cgImage: captured.image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        selectionView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        addSubview(selectionView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
```

- [ ] **Step 3：SelectionView 最小版本（只有遮罩和 Esc 退出）**

`App/Sources/Overlay/SelectionView.swift`：

```swift
import AppKit
import GlimpseCore

enum OverlayFinishAction {
    case copy
    case save
}

@MainActor
protocol SelectionViewDelegate: AnyObject {
    func selectionViewDidBeginSelection(_ view: SelectionView)
    func selectionViewDidCancel(_ view: SelectionView)
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction)
    func selectionViewMouseEntered(_ view: SelectionView)
}

final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?

    private let captured: CapturedScreen
    private let windows: [WindowInfo]
    private let primaryScreenHeight: CGFloat

    private(set) var phase: EditorPhase = .selecting
    private var selection: Selection?

    var hasSelection: Bool { selection != nil }

    init(frame: CGRect, captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        self.captured = captured
        self.windows = windows
        self.primaryScreenHeight = primaryScreenHeight
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func resetSelection() {
        selection = nil
        phase = .selecting
        needsDisplay = true
    }

    func refreshHoverAtMouse() {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { delegate?.selectionViewDidCancel(self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()
    }
}
```

- [ ] **Step 4：CaptureSessionController**

`App/Sources/Overlay/CaptureSessionController.swift`：

```swift
import AppKit
import GlimpseCore

/// One screenshot session: capture → one overlay per screen → finish or cancel → tear down.
@MainActor
final class CaptureSessionController {
    private let settings: SettingsStore
    private let capture = CaptureService()
    private var overlays: [OverlayWindow] = []
    private var isRunning = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard !isRunning else { return } // hotkey pressed again while overlay is up: ignore
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.requestOrOpenSettings()
            return
        }
        isRunning = true
        Task { @MainActor in
            do {
                present(try await capture.captureAll())
            } catch {
                NSLog("Glimpse: capture failed: \(error)") // P3 replaces this with a HUD
                NSSound.beep()
                isRunning = false
            }
        }
    }

    private func present(_ result: CaptureResult) {
        overlays = result.screens.map { screen in
            let window = OverlayWindow(captured: screen, windows: result.windows,
                                       primaryScreenHeight: result.primaryScreenHeight)
            window.selectionView.delegate = self
            return window
        }
        NSApp.activate()
        overlays.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let target = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        target?.makeKey()
        target?.makeFirstResponder(target?.selectionView)
        overlays.forEach { $0.selectionView.refreshHoverAtMouse() }
    }

    private func close() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        isRunning = false
        NSApp.hide(nil) // hand focus back to the previously active app
    }
}

extension CaptureSessionController: SelectionViewDelegate {
    func selectionViewDidBeginSelection(_ view: SelectionView) {
        // Selection is limited to one screen: starting one clears the others.
        for window in overlays where window.selectionView !== view {
            window.selectionView.resetSelection()
        }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    func selectionViewDidCancel(_ view: SelectionView) {
        close()
    }

    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction) {
        close()
        // Task 11 fills this in.
    }

    func selectionViewMouseEntered(_ view: SelectionView) {
        // Keyboard follows the mouse between screens until a selection exists.
        guard !overlays.contains(where: { $0.selectionView.hasSelection }) else { return }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }
}
```

- [ ] **Step 5：AppDelegate 接入会话**

在现有的 `App/Sources/AppDelegate.swift`（批次 B 审查修复后的版本）上做三处修改，**不要整体替换**，否则会丢掉快捷键注册结果的处理和菜单联动：

1. 加一个属性（放在 `statusItem` 下面）：

```swift
    // Created in applicationDidFinishLaunching (main thread). A `lazy var` initializer would run in a
    // nonisolated context and fail to compile, because CaptureSessionController is @MainActor.
    private var session: CaptureSessionController?
```

2. `applicationDidFinishLaunching` 的第一行加上：

```swift
        session = CaptureSessionController(settings: settings)
```

3. 把 `startCapture()` 的整个方法体换成转发给会话（授权检查已经挪进 `CaptureSessionController.start()`）：

```swift
    private func startCapture() {
        session?.start()
    }
```

- [ ] **Step 6：编译运行 + 手动检查**

Run: `cd . && scripts/run.sh`

- 按 ⌘⇧A：两块屏幕都变暗，画面「冻住」（播放中的视频停在当前帧），菜单栏和 Dock 也被盖住
- 冻结的画面清晰，Retina 屏上文字不发虚，没有鼠标指针
- 按 Esc：两块屏幕都恢复，焦点回到原来的应用
- 覆盖层显示时再按 ⌘⇧A：没有任何反应
- 在全屏应用里（比如把 Safari 切成全屏）按 ⌘⇧A：照样能盖住

> 代码审查后，覆盖层窗口改成了不抢前台的浮动面板（`NSPanel` + `.nonactivatingPanel`），不再调用 `NSApp.activate()`，关闭时也不再隐藏应用；显示器配置变化时会自动关闭覆盖层。以 `App/Sources/Overlay/` 的实际文件为准。验收时重点看：按 Esc 能退出；连按两次 ⌘⇧A（关掉后再截一次）覆盖层都能出现；在全屏应用里也能用。

---

### Task 10：选区交互

**Files:**
- Create: `App/Sources/Overlay/KeyInput+NSEvent.swift`
- Modify: `App/Sources/Overlay/SelectionView.swift`（整体替换为完整版本）

- [ ] **Step 1：NSEvent → KeyInput**

`App/Sources/Overlay/KeyInput+NSEvent.swift`：

```swift
import AppKit
import GlimpseCore

extension KeyInput {
    init(event: NSEvent) {
        let key: KeyInput.Key
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .enter          // Return, keypad Enter
        case 49: key = .space
        case 123: key = .arrow(dx: -1, dy: 0)
        case 124: key = .arrow(dx: 1, dy: 0)
        case 125: key = .arrow(dx: 0, dy: 1)  // down (screen-local y grows downward)
        case 126: key = .arrow(dx: 0, dy: -1)
        default: key = event.charactersIgnoringModifiers?.first.map { .character($0) } ?? .other
        }
        let flags = event.modifierFlags
        self.init(key: key,
                  command: flags.contains(.command),
                  shift: flags.contains(.shift),
                  option: flags.contains(.option),   // ⌥R / ⌃R must not switch tools (KeyRouter ignores them)
                  control: flags.contains(.control))
    }
}
```

- [ ] **Step 2：SelectionView 完整版本**

把 `App/Sources/Overlay/SelectionView.swift` 整体替换为：

```swift
import AppKit
import GlimpseCore

enum OverlayFinishAction {
    case copy
    case save
}

@MainActor
protocol SelectionViewDelegate: AnyObject {
    func selectionViewDidBeginSelection(_ view: SelectionView)
    func selectionViewDidCancel(_ view: SelectionView)
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction)
    func selectionViewMouseEntered(_ view: SelectionView)
}

/// Draws the dim, window highlight, selection, handles and size label for one screen,
/// and turns mouse/keyboard input into selection changes. All geometry is screen-local
/// (top-left origin, points) — this view is flipped.
final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?

    private let captured: CapturedScreen
    private let windows: [WindowInfo]
    private let primaryScreenHeight: CGFloat

    private(set) var phase: EditorPhase = .selecting
    private var selection: Selection?
    private var hoveredRect: CGRect?

    private enum Drag {
        case none
        case pending(start: CGPoint)                 // mouse down, not yet past the drag threshold
        case creating(start: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, original: CGRect)
    }
    private var drag: Drag = .none

    var hasSelection: Bool { selection != nil }
    private var screenBounds: CGRect { CGRect(origin: .zero, size: bounds.size) }

    init(frame: CGRect, captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat) {
        self.captured = captured
        self.windows = windows
        self.primaryScreenHeight = primaryScreenHeight
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - State changes

    func resetSelection() {
        selection = nil
        phase = .selecting
        drag = .none
        needsDisplay = true
    }

    private func enterEditing(with newSelection: Selection) {
        selection = newSelection
        hoveredRect = nil
        phase = .editing(tool: nil)
        needsDisplay = true
    }

    private func finish(_ action: OverlayFinishAction) {
        guard let selection else { return }
        let pixels = CoordinateSpace.pixelRect(fromLocal: selection.rect, scale: captured.info.scale)
        guard let image = Renderer.crop(captured.image, toPixelRect: pixels) else {
            NSSound.beep()
            return
        }
        delegate?.selectionView(self, didFinishWith: image, scale: captured.info.scale, action: action)
    }

    // MARK: - Hover

    func refreshHoverAtMouse() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if bounds.contains(point) { updateHover(at: point) }
    }

    private func updateHover(at point: CGPoint) {
        guard phase == .selecting else { return }
        let global = CoordinateSpace.cgGlobalPoint(fromLocal: point, in: captured.info,
                                                   primaryScreenHeight: primaryScreenHeight)
        let rect = WindowHitTester.topmostWindow(at: global, in: windows).map {
            CoordinateSpace.localRect(fromCG: $0.frame, in: captured.info,
                                      primaryScreenHeight: primaryScreenHeight).intersection(screenBounds)
        }
        if rect != hoveredRect {
            hoveredRect = rect
            needsDisplay = true
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.selectionViewMouseEntered(self)
    }

    override func mouseExited(with event: NSEvent) {
        guard phase == .selecting, hoveredRect != nil else { return }
        hoveredRect = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        switch phase {
        case .selecting:
            drag = .pending(start: point)
        case .typing:
            return // text annotations arrive in P2
        case .editing(let tool):
            guard let selection else { return }
            if event.clickCount == 2, KeyRouter.doubleClickFinishes(phase: phase), selection.rect.contains(point) {
                finish(.copy)
                return
            }
            if let handle = selection.handle(at: point) {
                drag = .resizing(handle, original: selection.rect)
            } else if tool == nil, selection.rect.contains(point) {
                drag = .moving(start: point, original: selection.rect)
                NSCursor.closedHand.set()
            } else {
                drag = .none
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none:
            return
        case .pending(let start):
            guard PointerGesture.isDrag(from: start, to: point) else { return }
            drag = .creating(start: start)
            hoveredRect = nil
            delegate?.selectionViewDidBeginSelection(self)
            selection = .fromDrag(start: start, end: point, bounds: screenBounds)
        case .creating(let start):
            selection = .fromDrag(start: start, end: point, bounds: screenBounds)
        case .moving(let start, let original):
            selection?.moveOrigin(to: CGPoint(x: original.minX + point.x - start.x,
                                              y: original.minY + point.y - start.y))
        case .resizing(let handle, let original):
            selection?.resize(handle, to: point, original: original)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none }
        switch drag {
        case .pending:
            // A click (no drag): take the highlighted window, if any.
            guard let rect = hoveredRect else { return }
            delegate?.selectionViewDidBeginSelection(self)
            enterEditing(with: Selection(rect: rect, bounds: screenBounds))
        case .creating, .resizing:
            if let selection, selection.isUsable {
                if phase == .selecting { enterEditing(with: selection) }
            } else {
                resetSelection()
            }
        case .moving, .none:
            break
        }
        updateCursor(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        switch KeyRouter.rightClick(phase: phase) {
        case .exit:
            delegate?.selectionViewDidCancel(self)
        case .reselect:
            resetSelection()
            updateHover(at: convert(event.locationInWindow, from: nil))
        default:
            break
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        perform(KeyRouter.route(KeyInput(event: event), phase: phase))
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .exit:
            delegate?.selectionViewDidCancel(self)
        case .selectFullScreen:
            delegate?.selectionViewDidBeginSelection(self)
            enterEditing(with: Selection(rect: screenBounds, bounds: screenBounds))
        case .finishCopy:
            finish(.copy)
        case .save:
            finish(.save)
        case .nudge(let dx, let dy, let large):
            selection?.nudge(dx: dx, dy: dy, large: large)
            needsDisplay = true
        case .reselect, .copyColor, .passToTextField, .endTyping, .selectTool, .deselectTool, .undo, .redo, .ignore:
            break // tools, colour picking and undo arrive in P2
        }
    }

    // MARK: - Cursor

    private func updateCursor(at point: CGPoint) {
        guard case .editing(let tool) = phase, let selection else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = selection.handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        } else if tool == nil, selection.rect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let clearRect = selection?.rect ?? hoveredRect

        let dim = NSBezierPath(rect: bounds)
        if let clearRect {
            dim.append(NSBezierPath(rect: clearRect))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dim.fill()

        guard let clearRect else { return }
        let accent = NSColor.controlAccentColor
        let border = NSBezierPath(rect: clearRect.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        accent.setStroke()
        border.stroke()

        guard let selection else { return }
        drawSizeLabel(for: selection.rect)
        if case .editing = phase {
            drawHandles(for: selection.rect, accent: accent)
        }
    }

    private func drawHandles(for rect: CGRect, accent: NSColor) {
        for handle in Handle.allCases {
            let c = Selection.handlePoint(handle, of: rect)
            let dot = NSBezierPath(ovalIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
            NSColor.white.setFill()
            dot.fill()
            dot.lineWidth = 1.5
            accent.setStroke()
            dot.stroke()
        }
    }

    /// Temporary dark label; P2 restyles it with the glass material.
    private func drawSizeLabel(for rect: CGRect) {
        let pixels = CoordinateSpace.pixelRect(fromLocal: rect, scale: captured.info.scale)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 12)
        if origin.y < 4 { origin = CGPoint(x: rect.minX + 6, y: rect.minY + 6) } // no room above: go inside
        let background = CGRect(x: origin.x, y: origin.y, width: size.width + 14, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: background.minX + 7, y: background.minY + 3), withAttributes: attributes)
    }
}
```

- [ ] **Step 3：编译运行 + 手动检查**

Run: `cd . && scripts/run.sh`

按 ⌘⇧A 后逐项检查：
- 鼠标在窗口上移动：最上层的窗口不变暗、有一圈强调色描边；窗口重叠时高亮的是前面那个
- 鼠标移到菜单栏或 Dock 上：不吸附后面的窗口，高亮整块屏幕
- 鼠标在两块屏幕之间移动：两边都能高亮，坐标对得上（外接屏上的窗口描边贴合窗口边缘）
- 单击高亮的窗口：变成选区，出现 8 个手柄和尺寸标签；尺寸是像素（Retina 屏上是窗口点数的 2 倍）
- 拖拽：轻微抖动（3pt 以内）不会画出选区；拖动画出选区，往任意方向拖都正确
- 在一块屏上有选区时，到另一块屏上拖拽：原来的选区消失，新选区出现
- 拖手柄：调整大小；拖过对边会翻转；不会超出屏幕
- 拖选区内部：整体移动，到屏幕边缘停住；光标是手形
- 方向键：每次移动 1pt；按住 ⇧ 每次 10pt
- 空格（还没选区时）：选中整块屏幕
- 有选区时右键：选区消失，回到悬停高亮状态；没有选区时右键：退出
- Esc：任何时候都直接退出（P1 还没有工具，所以 Esc 都是退出）

---

### Task 11：复制 / 保存

**Files:**
- Create: `App/Sources/Services/OutputService.swift`
- Modify: `App/Sources/Overlay/CaptureSessionController.swift`（`didFinishWith` 方法）

- [ ] **Step 1：OutputService**

```swift
import AppKit
import GlimpseCore

enum OutputService {
    /// Writes PNG + TIFF. The rep's size is set in points so a Retina capture pastes at the right size.
    static func copy(_ image: CGImage, scale: CGFloat) {
        let rep = bitmap(image, scale: scale)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// Saves to `directory` with a millisecond-precise name; throws if the directory is missing or not writable.
    @discardableResult
    static func savePNG(_ image: CGImage, scale: CGFloat, to directory: URL, date: Date = Date()) throws -> URL {
        guard let png = bitmap(image, scale: scale).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(ScreenshotFileName.make(for: date))
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }

    private static func bitmap(_ image: CGImage, scale: CGFloat) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep
    }
}
```

- [ ] **Step 2：在会话里接上输出**

把 `CaptureSessionController.swift` 里的 `selectionView(_:didFinishWith:scale:action:)` 替换为：

```swift
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction) {
        close()
        // Saving also copies (design doc §3.2), so a failed save still leaves the image on the clipboard.
        OutputService.copy(image, scale: scale)
        guard action == .save else { return }
        do {
            try OutputService.savePNG(image, scale: scale, to: settings.saveDirectory)
        } catch {
            NSLog("Glimpse: save failed, image is on the clipboard: \(error)") // P3: HUD
            NSSound.beep()
        }
    }
```

- [ ] **Step 3：编译运行 + 手动检查**

Run: `cd . && scripts/run.sh`

- 选一个窗口按 Enter：覆盖层关闭；在「预览」里 ⌘N（从剪贴板新建），图片内容就是那个窗口，Retina 屏上分辨率是 2 倍
- 同样操作，分别用 ⌘C、双击选区内部完成：结果一样
- 第一次按 ⌘S 时，系统可能弹出「Glimpse 想访问下载文件夹」，点允许。这是系统对「下载」文件夹的保护，不是程序卡住
- 按 ⌘S：`~/Downloads` 里出现 `Glimpse 2026-11-04 …​.png`，剪贴板里也有同一张图
- 一秒内连续截图保存两次：生成两个不同的文件（毫秒不同）
- 在外接 1 倍屏上截图：图片尺寸等于选区点数
- 把保存目录改成不存在的路径，再按 ⌘S：听到提示音，剪贴板里仍有图片
  - 改法：`defaults write com.anglerdw.glimpse saveDirectory -string "/no/such/dir"`，然后 `scripts/run.sh`
  - 测完恢复：`defaults delete com.anglerdw.glimpse saveDirectory`
- 在浏览器里粘贴到可粘贴图片的输入框（比如飞书、微信）：显示尺寸正常，没有被放大 2 倍

---

### Task 12：收尾验证

- [ ] **Step 1：全部单元测试**

Run: `cd Core && swift test`
Expected: 58 个测试全部通过

- [ ] **Step 2：干净编译**

Run: `cd . && rm -rf build && scripts/build.sh`
Expected: 没有错误；输出 app 路径

- [ ] **Step 3：完整走一遍 P1 验收**

按 Task 9、10、11 的手动检查清单在两块屏幕上各走一遍，把结果（通过 / 不通过和现象）记录下来，交给用户。

- [ ] **Step 4：停下来交给用户检查**

不执行 `git commit`。汇报内容包括：改了哪些文件、测试结果、手动验收结果、发现的问题。

---

## 后续计划（P1 完成后再写）

- **P2：材质、工具栏与标注**
  - `Material` 封装：macOS 26 用 `NSGlassEffectView`，macOS 14/15 用 `NSVisualEffectView`
  - 工具栏和颜色 / 粗细栏，自动避让屏幕边缘
  - 标注模型：坐标以冻结画面像素存储，锚定在画面上
  - Renderer：在整屏上合成标注，再按选区裁剪
  - 7 种工具；文字输入层（`passToTextField` / `endTyping`）；撤销重做
  - 放大镜和取色；尺寸标签改用玻璃材质
- **P3：其余功能**
  - OCR 和结果面板；贴图浮窗；HUD 提示
  - 完整的引导页和授权流程：轮询授权、重启应用、授权被撤销后的处理
  - 设置页：4 项，包含快捷键录制
  - 开机自动启动（`SMAppService`）；识别文字快捷键
