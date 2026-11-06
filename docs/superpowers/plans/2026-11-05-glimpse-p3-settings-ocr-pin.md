# Glimpse P3：设置页、引导与权限、识别文字、贴图 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 P2 的截图编辑流程上补齐第 1 期剩下的功能：自己的设置窗口（快捷键录制、界面强调色、保存目录、开机自动启动、关于）、首次启动引导与屏幕录制权限流程（含「重新启动 Glimpse」）、识别文字（Vision，工具栏按钮 + 菜单 + 可选快捷键 + 结果面板）、贴图浮窗（工具栏按钮），菜单栏菜单补全为「截图、识别文字、设置…、退出」。

**Architecture:** 纯逻辑继续放 `GlimpseCore`（Swift 6、Swift Testing，先写失败测试）：设置项读写（扩展现有 `SettingsStore`，不另起 store）、强调色预设、快捷键录制规则与显示、引导窗口的状态机、OCR 阅读顺序、贴图缩放几何、局部坐标 → AppKit 全局坐标。App 层是 AppKit 胶水：设置窗口用 SwiftUI 的分组表单（`Form` + `.formStyle(.grouped)`）放进 `NSHostingController`，快捷键录制按钮是 AppKit 的 `NSButton` 子类经 `NSViewRepresentable` 嵌进表单；引导窗口、识别结果面板用现有 `MaterialView`（玻璃材质）；全局快捷键由新的 `HotkeyController` 统一注册 / 挂起 / 改键；开机自动启动走 `SMAppService.mainApp`；HUD 复用已落地的 `HUDController`。

**Tech Stack:** Swift 6.3 / Xcode 26.6（macOS 26.5 SDK）、macOS 14+ 部署目标、AppKit、SwiftUI（`Form`、`@Observable`，均 macOS 14 可用）、Vision（`VNRecognizeTextRequest`）、ServiceManagement（`SMAppService`）、Carbon（`RegisterEventHotKey`）、Swift Testing、XcodeGen。

**设计文档：** `docs/superpowers/specs/2026-11-04-glimpse-design.md`（P3 = §3.1、§3.5、§3.6、§3.7、§3.8、§3.9、§4、§5、§6）
**上一期计划：** `docs/superpowers/plans/2026-11-05-glimpse-p2-editing.md`（已验收）

**提交约定：** 用户要求不由 agent 执行 `git commit`。本计划不含提交步骤；每个任务结束时「停下，不 commit」，把改动交给用户检查。

**执行约束：** 执行本计划的 agent **不得**启动应用、不得运行 `scripts/run.sh`、不得做任何会触发系统权限弹窗或登录项注册的操作。agent 只跑 `swift test` 和 `scripts/build.sh`；每个批次末尾的「手动检查」由用户在真机上做。

---

## 实施前说明（2026-11-05）

本计划以 P2 验收后、HUD 任务落地后的**实际代码**为准。写计划时把全部改动在仓库副本上按顺序重放过一遍：每一处「把…替换为…」的原文都在当时的文件里**恰好出现一次**，每个任务末尾都能编译（无新增警告），Core 测试全部通过。核对过的现状：

- **设置**：`Core/Sources/GlimpseCore/Settings/SettingsStore.swift` 里只有 `screenshotHotkey`（JSON 编码的 `KeyCombo?`，默认 ⌘⇧A，存 `nil` 表示用户清空）和 `saveDirectory`（默认 `~/Downloads`，带校验）。本计划在它上面加识别文字快捷键、强调色、「开机自动启动默认值已应用」三项，不另起 store（`AnnotationStyleStore` 维持原样）。
- **快捷键**：`HotkeyService`（Carbon）已支持「新组合注册成功才换掉旧的」「同组合重复注册直接换 handler」，`unregister` 尚未被调用；`HotkeyAction` 只有 `.screenshot`。`AppDelegate.applicationDidFinishLaunching` 里直接注册截图快捷键并把结果写到菜单。
- **菜单栏**：`StatusItemController` 只有「截图」「退出 Glimpse」，`updateCaptureShortcut(_:)` 显示快捷键；`KeyCombo+Menu.swift` 已有 Carbon → 菜单键的换算。
- **权限**：`ScreenRecordingPermission.requestOrOpenSettings()`：第一次只调 `CGRequestScreenCaptureAccess()`（系统自己弹询问框），之后每次都调它并打开系统设置的屏幕录制页；没有引导窗口，未授权时只打日志。
- **强调色**：用到 `NSColor.controlAccentColor` 的地方共 6 处：`SelectionView.draw`（选区边框、手柄）、`ToolbarButton.refreshColors`（选中底色、14/15 的光晕、✓ 图标）、`PaletteButton.draw`（选中色块的外圈）、`ZoomedPixelsView.draw`（放大镜的「+」十字线；放大镜已改为 17 × 17 像素、135 × 213 的面板，不再画中心方框，提示文字用新的 `NSColor.materialTertiaryText`）。标注颜色走 `PaletteColor`，不受影响。
- **HUD**：`App/Sources/HUD/HUDController.swift`（`show(_ message: HUDMessage, on screen: NSScreen?)`、`dismiss()`）和 Core 的 `HUDMessage`（`.copied`、`.saved(folder:)`、`.saveFailed` 等）已由另一个任务实现，由 `CaptureSessionController` 自己 `private let hud = HUDController()` 持有；会话运行中完成的保存提示放进 `pendingHUD`，等覆盖层关闭再显示。本计划**不再实现 HUD，也不改它的归属**：批次 D 给会话加一个 `showHUD(_:on:)`（运行中就走 `pendingHUD`），贴图的复制 / 保存提示都经它显示，不会被截进画面或被覆盖层盖住。
- **工具栏**：`ToolbarItem.groups` 第三组现在是 `[.save]`；注释写明 P3 按 §3.3 在「保存」前插入「识别文字」「贴图」。`OverlayFinishAction` 只有 `.copy` / `.save`；`SelectionView.finish(_:)` 是 `private`，合成用 `Renderer.composite`。
- **截图服务**：`CaptureService` 的 `SCContentFilter` 不排除任何窗口（注释里写着「Pin windows (P3) will need explicit exclusion then」），窗口列表已经剔除 Glimpse 自己的窗口（批次 D 改为保留它层级高于 0 的窗口作遮挡，见第 20 条）。
- **签名**：开发证书被吊销，`scripts/build.sh` 退回 ad-hoc 签名，**每次重新编译后都要重新授予屏幕录制权限**。所以每个批次只在最后编译给用户一次；批次内的中间任务只由 agent 编译检查。用户在批次内要重启应用时，用 `pkill -f Glimpse.app/; open build/Build/Products/Debug/Glimpse.app`（不重新编译，权限保留），不要用 `scripts/run.sh`。ad-hoc 重签名后系统可能把 Glimpse 当成新应用、再次弹出屏幕录制询问框，而 `UserDefaults` 里「申请过」的标记（`didRequestScreenRecording`）还在，于是点「去授权」时系统询问框和系统设置可能叠在一起出现（第 10 条想避免的情况）。只有开发版会这样（正式签名不变），不处理；想从头测时按 Task 6 手动检查里的 `tccutil reset` + `defaults delete` 清掉。
- 写计划时 `swift test` 是 **154 tests in 24 suites**（HUD 任务完成后）；各任务的预期总数见对应步骤，全部完成后是 **197 tests in 29 suites**。

**设计文档没说死、本计划自己定下的地方**（取 macOS 原生和主流截图工具的做法，尽量少做）：

1. **设置窗口用 SwiftUI 分组表单，装在 AppKit 窗口里**：应用仍是 `main.swift` + `NSApplication` 的 AppKit 生命周期，不改成 SwiftUI `App`（`Settings` 场景要求 SwiftUI 生命周期，而且会改动菜单栏应用的启动方式）。`Form` + `.formStyle(.grouped)` 一行代码就是「系统设置」的原生外观，日夜间、字体、间距、辅助功能都由系统负责；纯 AppKit 要手搭 `NSGridView` 和分组背景才能接近。设置窗口不用玻璃材质（§4.1 的材质清单里没有设置页），是标准标题栏窗口「Glimpse 设置」，宽 480、高 600，不可缩放；内容超出时表单自己滚动。
2. **菜单**：「截图 ⇧⌘A / 识别文字（有快捷键才显示）/ ─ / 设置… ⌘, / ─ / 退出 Glimpse ⌘Q」。⌘, 和 ⌘Q 一样只在菜单打开时生效（菜单栏应用没有主菜单）。**不加主菜单**：主菜单的按键会在覆盖层、文字框之前截走 ⌘C / ⌘Q 等组合键，打乱 P2 的按键分层。设置窗口自己处理 ⌘W（关闭）和 ⌘Q（退出），先让窗口里的视图处理（录制快捷键时这两个组合也能被录下）。`KeyCombo+Menu` 的键表补全到录制按钮能录的所有键（F1–F20、空格、标点、方向键、Return / Tab / Delete 等），菜单里总能显示正在生效的快捷键。
3. **快捷键的写法**按 macOS 习惯排成 ⌃⌥⇧⌘ + 键，所以默认值显示为「⇧⌘A」（设计文档写的 ⌘⇧A 是同一个组合）。
4. **快捷键录制规则**：点按钮开始录制（按钮显示「请按快捷键…」，按住修饰键时实时显示，如「⌃⌥」）；单按 Esc 取消、单按 Delete 清空；其余按键必须带 ⌘、⌃ 或 ⌥（F1–F20 可以不带），否则红字「快捷键需要包含 ⌘、⌃ 或 ⌥」；**系统常用组合拒收**：只带 ⌘ 的 Q / W / C / V / X / Z / A / S / H / M / Tab / 空格 / 逗号，以及 ⇧⌘Z，还有切换输入法的 ⌃空格、⌃⌥空格，红字「这是系统常用的快捷键（如拷贝、粘贴、退出），请换一个」（与另一个快捷键重复时也先报这一条）；**只带 ⌥（或 ⌥⇧）时只接受 F 键和空格**，加字母、数字、符号会挡住特殊字符输入（⌥E → ´），红字「只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃」；带修饰键的 Esc / Delete（如 ⌘⌫）照常录下；与另一个全局快捷键相同则红字「已用作另一个快捷键，请换一个」；小键盘等认不出名字的键拒收。按钮右边的 ⓧ 也能清空。**录制期间暂停全部全局快捷键**（否则按 ⇧⌘A 会被 Carbon 先拿走、直接开始截图）。结束录制的方式：再点按钮、按键、点窗口里任何别处（录制时装一个本地鼠标事件监视器：表单空白处、ⓧ 这类不会成为第一响应者的地方也算）、窗口不再是 key、关闭窗口；结束时恢复全部快捷键，仍注册不上的快捷键重新标红。录完松手前按键的自动重复由设置窗口吞掉（不响提示音，被拒的 ⌘W 按住不放也不会关窗口）。
5. **注册失败**：新组合注册失败时**不保存**，原来的快捷键继续有效，录制按钮仍显示原组合，下面红字「「⌃⌥X」已被其他程序占用，请换一个」。已保存的快捷键在启动时注册失败（别的程序先占了）：仍保留在设置里（下次启动再试），设置页红字「没有注册成功，现在不可用」，菜单里不显示这个快捷键。常驻提示句（微信 / QQ）放在「快捷键」分组的脚注里，两个快捷键共用一句。
6. **界面强调色**：跟随系统 + 7 个预设：蓝、紫、粉、红、橙、绿、石墨，取 Apple 系统色，夜间用系统色的深色值（调亮一档，§4.2）。**不放黄色**：选中按钮是强调色实底 + 白色图标，黄底白字看不清。设置页以一排色点显示（同「系统设置 → 外观」的强调色行），第一个是彩虹色点代表「跟随系统」，悬停显示名称。作用范围是上面列出的 6 处，另加引导窗口的图标和「去授权」按钮；**不影响标注颜色**。改动立即生效：覆盖层每次截图新建，所以下一次截图就是新颜色；另外，把强调色缓存成 `CGColor` 或画进内容的视图（工具栏按钮、选区、二级栏选中色块、放大镜十字线）都持有一个 `AccentObservation`，在 Glimpse 的选择变化（`InterfaceAccent.didChangeNotification`）或系统强调色变化（`NSColor.systemColorsDidChangeNotification`）时立即刷新，截图途中在系统设置里换强调色也能跟上。实现上是一个动态 `NSColor.glimpseAccent`，每次绘制时读当前选择（加锁，因为 AppKit 可能在后台线程解析颜色）。
7. **保存目录**：显示访达里的名称和图标（「下载」），悬停显示完整路径；「更改…」在设置窗口上以表单（sheet）弹 `NSOpenPanel`（只选文件夹、可新建文件夹）。`project.yml` 补上「桌面」「文稿」的访问说明（同已有的「下载」），选这两个目录后第一次保存时系统询问框里是中文说明。不做「恢复默认」按钮。应用没有沙盒，直接存路径（沿用 `SettingsStore.saveDirectory` 的校验）。
8. **开机自动启动**：状态以系统为准（`SMAppService.mainApp.status == .enabled`），Glimpse 自己只记「默认值已应用过」一个标记：第一次启动时注册一次（失败只记日志），之后只由用户改。**Debug 编译跳过这次默认注册**（`#if DEBUG`）：`build/` 里的开发版永远不会自己登记成登录项，设置里的开关照样能手动用；Release 版第一次运行时才应用默认值。开关失败时恢复原状并在下方红字显示原因（§6）；系统返回「需要批准」（用户在「系统设置 → 通用 → 登录项」里关掉过 Glimpse）也算失败，红字「需要在「系统设置 → 通用 → 登录项」里允许 Glimpse」并给「打开登录项设置」按钮。`register()` 抛错时以系统状态为准：已经是「已开启」算成功，「需要批准」报上面那句，其他才报「开启失败：…」。设置窗口每次打开、Glimpse 每次重新变成活跃应用时重读状态（用户可能在系统设置里改过）；重读时系统处于「需要批准」（用户在登录项里关掉了 Glimpse）就直接显示那句红字和「打开登录项设置」按钮，不必等开关失败；不再需要批准时清掉；其他失败的红字一直保留到系统状态与出错时不同；Glimpse 变成活跃应用时只重读登录项，不清快捷键的红字。
9. **识别文字快捷键在批次 A 只能录、不能用**：设置页一次做全（§3.9 的项都在），但识别文字流程到批次 C 才有；批次 A 里按这个快捷键只响一声提示音，Task 9 换成真正的识别。
10. **「去授权」第一次点**：只调用 `CGRequestScreenCaptureAccess()`，由系统弹自己的询问框（框上有「打开系统设置」按钮），不同时打开系统设置，免得两个窗口叠在一起；之后每次点都先调用它再打开系统设置的屏幕录制页。这是 P1 真机上定下的做法，保留；§3.8 的写法在 Task 12 同步。
11. **引导窗口**：无边框的玻璃窗口（`MaterialView`，圆角 12，§4.3 的面板圆角），可拖动背景移动；右上角 ✕ 和 Esc 关闭（关闭后按截图快捷键会再打开它）；普通窗口层级，不压住系统设置。只在第一次创建时居中，用户拖开后再次打开留在原处。内容：图标、标题「允许 Glimpse 录制屏幕」、说明、「去授权」、需要时出现的「已经打开了开关？需要重新启动 Glimpse 才能生效。 [重新启动 Glimpse]」、快捷键提示（§3.1 要求首次引导里也提微信 / QQ）、「开机自动启动」勾选框（显示系统里的真实状态，默认已在第 8 条里打开；红字和「打开登录项设置」按钮与设置页同一套逻辑，`LoginItemService.Display` 共用，Glimpse 重新变成活跃应用时重读）。需要重新启动时，回车键对应「重新启动 Glimpse」，否则对应「去授权」。**每次启动时没有权限都显示**（不只是第一次），授权后自动关闭。**截图被拒的情况**（第 14 条）：预检说有权限、ScreenCaptureKit 却拒绝截图时，引导窗口以「截图被拒」模式打开：直接显示「系统设置里已允许，但截图仍被拒绝。请重新启动 Glimpse；若仍不行，在系统设置里关掉再打开 Glimpse 的开关。」和「重新启动 Glimpse」；这时预检一直说有权限，所以轮询不会自动关窗，只能用 ✕、Esc 或重新启动关闭；窗口开着时用户再截图（截图入口仍只看预检），窗口先隐藏再截图；截图成功时菜单栏标记立即清掉，窗口等覆盖层关掉后才正式关闭（关闭会把键盘交还之前的应用，不能抢在覆盖层还在时）；再次被拒就重新显示。
12. **显示「重新启动」的时机**用 Core 的 `PermissionFlow`，分两档：第一次点「去授权」只弹系统询问框（用户可能在框里点了「打开系统设置」，我们不知道），之后就常驻一行**弱提示**「打开开关后若没有生效，请重新启动 Glimpse」（小字、次要色，带一个小号「重新启动 Glimpse」按钮）；**真的打开过系统设置**（第二次及以后点「去授权」）之后，Glimpse 再次变成活跃应用时仍未授权，换成**明显的提示**「已经打开了开关？需要重新启动 Glimpse 才能生效。」和常规大小的按钮。每秒轮询发现已授权 → 关窗。状态在应用运行期间保留（关掉引导窗口再打开不会忘），确认授权后清零。
13. **重新启动的做法**：起一个 `/bin/sh` 子进程，等当前进程退出、再等 0.3 秒（让系统收掉状态栏图标和全局快捷键）后 `open` 应用，然后当前进程退出。最多等 10 秒：当前进程到时还没退出（退出被取消），子进程放弃、不 `open`，免得出现第二个实例。子进程起不来时不退出，重启那一行换成红字「无法自动重启，请手动退出后重新打开」并响一声提示音。不用 `createsNewApplicationInstance` 先开新实例：新实例注册 ⇧⌘A 时旧实例还占着，会被 Carbon 判成冲突。
14. **菜单栏图标的提示标记**（§6）：没有权限时换成 `viewfinder.trianglebadge.exclamationmark`（老系统没有这个符号时退回 `exclamationmark.triangle`）。在启动、每次 Glimpse 变成活跃应用、引导窗口确认授权、截图发现没权限时刷新（状态没变时不换图）。ScreenCaptureKit 报 `userDeclined`（预检说有权限但实际被拒，如 macOS 15 定期确认时用户点了拒绝）也当作没权限：记下 `PermissionService.captureRefused`，以「截图被拒」模式打开引导窗口（第 11 条），不弹「截图失败」；菜单栏标记 = 没有权限 **或** 截图被拒，下一次截图成功时立即清掉（引导窗口则等覆盖层关掉后才关，见第 11 条）。截图入口仍只看预检，所以被拒后用户还能再试。
15. **识别文字的输入**：工具栏按钮识别当前选区；菜单 / 快捷键进入的截图会话里，选区一确定（拖完松手、单击窗口或整屏、空格、Enter / ⌘S 取当前高亮）立即识别，不出工具栏，也不另加「识别模式」提示。识别用选区的**原始冻结像素**（不含标注，§3.2），剪贴板里只放文字（不放图片）。
16. **阅读顺序**（§3.5）：按行从上到下，行内从左到右。一段文字归入某一行的条件：高度相近时，它的竖直中心落在该行**第一段**的上下范围内，且第一段的中心也落在它的范围内；一段比另一段高出一倍以上时，只要求矮的那段的中心落在高的那段**中间一半**的范围内（行内的小角标归入这一行，而大标题旁贴着它上沿、下沿的小字不会被吞进去）。行的范围不随加入的文字扩大，所以一串逐渐错开的文字不会连成一行。先试最近的一行；只有最近的行是由很小的一段（不到这段文字一半高，如角标、徽标）开头时才越过它往前找，所以夹在同一行两段之间的小角标不会把这一行拆开，而中间隔着一行正常文字时不会越过。同行之间用一个空格连接，行之间换行；空白行丢掉。左右两栏的版面按行交错读出（不做分栏检测，同大多数截图工具）。
17. **识别结果面板**：识别开始就出现，第一次在选区所在屏幕的正中，之后留在用户拖到的位置（那个位置已不在任何屏幕上时才重新居中）；标题旁显示「正在识别…」，结果出来换成文字和「已复制」；没有文字显示「未识别到文字」（剪贴板不动）；出错显示「识别失败」。只有识别出的文字可编辑（正在识别 / 未识别到 / 失败时不可编辑），一改动「已复制」就消失（剪贴板里还是旧文字），「复制」按钮随文字是否为空启用 / 停用，点「复制」复制当前文字并重新显示「已复制」；每次换内容都清空撤销记录。Esc、⌘W（面板自己处理，Caps Lock 开着也行；俄文等非拉丁键盘按键位认 W）、✕ 关闭，关闭时取消进行中的识别。和覆盖层一样是「不激活应用、但能拿键盘」的浮动面板，关掉后键盘自然回到原来的应用。只有一个面板，新的识别替换旧内容并**真正取消**旧的 Vision 请求（`request.cancel()`）；识别结束时先确认它没有被取消、面板也还开着，才写剪贴板（关掉面板后才出来的结果不会覆盖剪贴板）。**新的截图 / 识别开始时**，面板和 HUD、引导窗口一样先收起（进行中的识别一并取消），等一轮主队列再截图，不会出现在冻结画面里。面板一直是浮动层级（`.floating`），切到别的应用时也在上面，是否合适由用户真机判断。面板宽 440、高 300。
18. **贴图**：从工具栏「贴图」合成（含标注）后，浮窗**原位**出现在选区的位置、原始大小（同 Snipaste），剪贴板不动。滚轮缩放以鼠标为中心，范围 10%–500%，短边不小于 24pt（本来就更小的图不缩小），长边不超过 10000pt（大截图放到 500% 会是比任何屏幕都大的窗口）；缩放经过 100%、或朝 100% 缩到相差 3% 以内时停在正好 100%（离开 100% 不受影响），100% 时窗口就是图片原尺寸，其他倍数的窗口大小和位置取到屏幕像素（1 / backingScaleFactor）上；触控板甩动后的惯性滚动（momentum）不缩放；触控板捏合（`magnify(with:)`）同样以鼠标为中心缩放；滚轮向前推（远离自己）放大，跟「自然滚动」设置无关；触控板双指滚动同样缩放。拖动用系统的 `performDrag`，双击关闭。浮窗在所有桌面空间和全屏应用上都显示，不抢键盘（点它不会让当前应用失去焦点）。浮窗用 `.floating` 层级：低于覆盖层，也低于 Dock 和菜单栏（拖到那里会被盖住，接受）。窗口大小和位置取自实际裁出的像素（选区向外取整后的像素矩形），贴图正好盖在原来的像素上。拔掉显示器或调整排列后，不在任何屏幕上的贴图移回主屏可见区域的中间。
19. **贴图右键菜单用系统 `NSMenu`**，不自绘玻璃菜单。§4.1 把「贴图右键菜单」列进统一材质，但 macOS 26 的系统菜单本身就是液态玻璃（和 `MaterialView` 在 26 上用的是同一种系统玻璃），自绘还要重做键盘导航、子菜单和 VoiceOver。macOS 14 / 15 上系统菜单是系统自己的菜单材质，与我们模拟的毛玻璃略有差别，接受。菜单：复制、保存、透明度（100% / 75% / 50%，当前项打勾）、─、关闭。「复制」后 HUD「已复制到剪贴板」；「保存」同时复制（同 ⌘S），HUD「已保存到「下载」」或「保存失败，图片已复制到剪贴板」。这些提示经会话的 `showHUD(_:on:)`：保存在新截图进行中才完成时，提示等覆盖层关掉再出现。设计文档在 Task 12 同步。**如果用户评审时坚持自绘，这一条单独开任务，不影响其他任务。**
20. **贴图与之后的截图**：贴图是屏幕上的普通内容，会出现在之后截图的冻结画面里（所见即所得，同 Snipaste）；窗口列表剔除 Glimpse 自己的普通窗口（层级 0，如设置窗口），但保留层级高于 0 的（贴图、识别结果面板）作为遮挡：悬停时不会吸附贴图，也不会吸附贴图后面的窗口（鼠标在贴图上时高亮整屏），与冻结画面里看到的一致。HUD 在截图前收起的做法不变。
21. **工具栏**：第三组变成「识别文字 贴图 保存」（图标 `text.viewfinder`、`pin`）。这两个按钮在覆盖层里没有单键，工具提示只显示名称「识别文字」「贴图」。
22. **14 / 15 的毛玻璃**：覆盖层里的玻璃模糊的是同一窗口里的冻结画面（`.withinWindow`）；引导窗口和识别结果面板是独立窗口，要模糊窗口后面的桌面，所以 `MaterialView` 加一个 `blendsBehindWindow` 参数（默认 false，现有调用不变）。macOS 26 的系统玻璃不受影响。
23. **有窗口时显示 Dock 图标**：设置窗口或引导窗口打开时，应用切到 `.regular`（Dock 图标和 ⌘Tab 里能找到它，窗口被别的应用挡住时能切回来），两个都关闭后回到 `.accessory`（`DockPresence` 计数）。打开时先 `orderFrontRegardless` + `makeKey`，再 `NSApp.activate()`：从菜单和启动时激活会被允许；从全局快捷键打开时 macOS 14+ 的协作式激活可能拒绝，但窗口已经在最前面、可以直接点。打开窗口时若 Glimpse 不是活跃应用，记下当时在前面的应用；之后一直监听 `NSWorkspace.didActivateApplicationNotification`，记住最近一个变成活跃的其他应用（从 Dock / ⌘Tab 切回 Glimpse 时，交还给刚离开的那个应用）。窗口全部关掉时若 Glimpse 仍是活跃应用，先 `NSApp.yieldActivation(to:)` 再激活那个应用，键盘回到它（不用 `NSApp.hide`，那会把贴图也藏起来）。**识别结果面板不显示 Dock 图标**：它是不激活应用的浮动面板，⌘Tab 切到 Glimpse 会打破「关掉后键盘回到原来的应用」。应用没有图标资源，Dock 里是通用图标；`.regular` 时菜单栏左侧只有应用名（没有主菜单，见第 2 条）。
24. **菜单 / 快捷键识别文字时，覆盖层不加「识别模式」提示**：外观与普通截图相同，选区一定立即识别（第 15 条）。
25. **批次 C 不单独上真机**：识别文字和贴图都在批次 D 结束时一起检查，少编译一次、少授权一次。

---

## 文件结构

新增（+）、修改（~）、删除（−）：

```
glimpse/
├─ Core/Sources/GlimpseCore/
│  ├─ Settings/SettingsStore.swift            ~ 识别文字快捷键、强调色、开机启动默认值标记（Task 1）
│  ├─ Settings/AccentColor.swift              + 强调色预设（Task 1）
│  ├─ Settings/HotkeyRecording.swift          + 快捷键显示（⇧⌘A）与录制规则（Task 1）
│  ├─ Permission/PermissionFlow.swift         + 引导窗口状态：去授权 / 需要重启 / 截图被拒 / 已授权（Task 5）
│  ├─ OCR/ReadingOrder.swift                  + RecognizedLine、阅读顺序（Task 7）
│  ├─ Pin/PinZoom.swift                       + 贴图缩放倍数与以鼠标为中心的窗口位置（Task 10）
│  ├─ Geometry/CoordinateSpace.swift          ~ appKitRect(fromLocal:in:)（Task 10）
│  └─ Geometry/WindowHitTester.swift          ~ removingOwnWindows：自己的贴图留作遮挡（Task 10）
├─ Core/Tests/GlimpseCoreTests/
│  ├─ SettingsStoreTests.swift                ~ Task 1
│  ├─ HotkeyRecordingTests.swift              + Task 1（含 AccentColorTests）
│  ├─ PermissionFlowTests.swift               + Task 5
│  ├─ ReadingOrderTests.swift                 + Task 7
│  ├─ PinZoomTests.swift                      + Task 10
│  ├─ CoordinateSpaceTests.swift              ~ Task 10
│  └─ WindowHitTesterTests.swift              ~ Task 10
└─ App/Sources/
   ├─ AppDelegate.swift                       ~ Task 4 整体替换；6、9、11 局部修改
   ├─ Material/InterfaceAccent.swift          + NSColor.glimpseAccent、AccentObservation（Task 2）
   ├─ Material/MaterialView.swift             ~ blendsBehindWindow（Task 6）
   ├─ Overlay/SelectionView.swift             ~ 强调色（Task 2）；识别文字（Task 9）；贴图位置（Task 11）
   ├─ Overlay/MagnifierView.swift             ~ 强调色（Task 2）
   ├─ Overlay/OverlayContentView.swift        ~ 工具栏新按钮（Task 9、11）
   ├─ Overlay/CaptureSessionController.swift  ~ 权限（Task 6）；识别文字（Task 9）；贴图、HUD 注入（Task 11）
   ├─ Toolbar/ToolbarButton.swift             ~ 强调色（Task 2）
   ├─ Toolbar/StylePaletteView.swift          ~ 强调色（Task 2）
   ├─ Toolbar/ToolbarItem.swift               ~ Task 9 整体替换；Task 11 局部修改
   ├─ MenuBar/StatusItemController.swift      ~ Task 4 整体替换；6、9 局部修改
   ├─ MenuBar/KeyCombo+Menu.swift             ~ Task 4 整体替换：键表补全
   ├─ Services/HotkeyService.swift            ~ HotkeyAction.ocr（Task 3）
   ├─ Services/HotkeyController.swift         + 全局快捷键的注册、挂起、改键（Task 3）
   ├─ Services/LoginItemService.swift         + SMAppService.mainApp（Task 3）；显示逻辑 Display（Task 6）
   ├─ Services/DockPresence.swift             + 有窗口时显示 Dock 图标（Task 4）
   ├─ Services/ScreenRecordingPermission.swift − 由 PermissionService 取代（Task 6）
   ├─ Services/PermissionService.swift        + 检查 / 申请权限、截图被拒标记、重新启动（Task 6）
   ├─ Services/CaptureService.swift           ~ 窗口列表保留自己的贴图作遮挡、注释（Task 11）
   ├─ Settings/HotkeyRecorderButton.swift     + 快捷键录制按钮（Task 4）
   ├─ Settings/SettingsModel.swift            + 设置页的数据和动作（Task 4）；登录项改用 Display（Task 6）
   ├─ Settings/SettingsView.swift             + 设置页（SwiftUI 分组表单）（Task 4）
   ├─ Settings/SettingsWindowController.swift + 设置窗口（Task 4）
   ├─ Onboarding/OnboardingWindowController.swift + 引导窗口（Task 6）
   ├─ OCR/OCRService.swift                    + Vision 识别（Task 8）
   ├─ OCR/OCRResultPanel.swift                + 识别结果面板（Task 8）
   ├─ OCR/OCRController.swift                 + 识别 → 剪贴板 → 面板（Task 8）
   ├─ Pin/PinWindow.swift                     + 贴图浮窗（Task 11）
   └─ Pin/PinWindowController.swift           + 所有贴图、复制 / 保存（Task 11）
```

`project.yml` 只在 Task 4 加两条文件夹访问说明（实施前说明第 7 条）；`App/Sources` 下新建的子目录会被 XcodeGen 自动收进工程；SwiftUI、Vision、ServiceManagement、ScreenCaptureKit 都是系统框架，`import` 即自动链接。`scripts/build.sh` 每次都会重新生成工程。

## 批次与真机检查点

| 批次 | 任务 | 结束后用户在真机上能验证的 |
|---|---|---|
| A 设置页 | Task 1–4 | 菜单「设置…」打开设置窗口；录制 / 清空截图和识别文字快捷键、冲突标红、常驻提示；强调色作用于覆盖层；保存目录；开机自动启动开关；关于 |
| B 引导与权限 | Task 5–6 | 引导窗口、去授权、需要时「重新启动 Glimpse」、勾选框；没权限时按快捷键打开引导、菜单栏图标标记 |
| C 识别文字 | Task 7–9 | 不单独上真机（实施前说明第 25 条），和批次 D 一起检查 |
| D 贴图 | Task 10–11 | 识别文字：工具栏「识别文字」、菜单「识别文字」和自设快捷键、结果面板（编辑、复制、已复制、未识别到文字、Esc）；贴图：工具栏「贴图」、原位浮窗、拖动、滚轮 / 捏合缩放、双击关闭、右键菜单、多个同时存在 |
| E 收尾 | Task 12 | 全部测试、干净编译、残留检查、设计文档同步、登录项实测、完整验收 |

每个真机检查点（A、B、C+D、E）只在最后让用户编译运行一次（`scripts/run.sh`），因为 ad-hoc 签名每次重新编译都要重新授予屏幕录制权限；批次内的任务由 agent 用 `scripts/build.sh` 检查能编译即可。批次 B 正好利用这一点：编译后权限失效，引导流程自然会出现。

---

## 批次 A：设置页

### Task 1：设置项、强调色预设、快捷键录制规则（Core）

**Files:**
- Modify: `Core/Sources/GlimpseCore/Settings/SettingsStore.swift`
- Create: `Core/Sources/GlimpseCore/Settings/AccentColor.swift`
- Create: `Core/Sources/GlimpseCore/Settings/HotkeyRecording.swift`
- Test: `Core/Tests/GlimpseCoreTests/SettingsStoreTests.swift`、`Core/Tests/GlimpseCoreTests/HotkeyRecordingTests.swift`

`SettingsStore` 加三项：`ocrHotkey`（默认 nil，与截图快捷键共用同一套 JSON 读写，抽成两个私有方法）、`accentColor`（按名字存，认不出的名字回到「跟随系统」）、`loginItemDefaultApplied`（实施前说明第 8 条）。`AccentColor` 是强调色预设（第 6 条）。`HotkeyRecording` 是录制按钮的规则（第 4 条：需要修饰键、系统常用组合和只带 ⌥ 的字符键拒收、不能与另一个重复）和 ⌃⌥⇧⌘ 顺序的显示（第 3 条）；`KeyCombo` 改为 `Hashable`（拒收表是一个 `Set`），默认截图快捷键改用具名的修饰键常量；修饰键用 Carbon 的位（与 `KeyCombo.modifiers` 一致），键名按 Carbon 虚拟键码查 ANSI 键盘上的标签。

- [ ] **Step 1：写失败的测试**

（1）`Core/Tests/GlimpseCoreTests/SettingsStoreTests.swift`：把

```swift
    @Test func saveDirectoryPersists() {
```

替换为

```swift
    @Test func ocrHotkeyIsUnsetUntilChosen() {
        withStore { store, _ in
            #expect(store.ocrHotkey == nil)
            let combo = KeyCombo(keyCode: 17, modifiers: KeyCombo.command | KeyCombo.option)
            store.ocrHotkey = combo
            #expect(store.ocrHotkey == combo)
            #expect(store.screenshotHotkey == .defaultScreenshot) // a separate key
            store.ocrHotkey = nil
            #expect(store.ocrHotkey == nil)
        }
    }

    @Test func accentFollowsTheSystemUntilPicked() {
        withStore { store, defaults in
            #expect(store.accentColor == .system)
            store.accentColor = .purple
            #expect(SettingsStore(defaults: defaults).accentColor == .purple)
            defaults.set("teal", forKey: "accentColor") // a name this version does not know
            #expect(store.accentColor == .system)
        }
    }

    @Test func loginItemDefaultIsAppliedOnce() {
        withStore { store, defaults in
            #expect(!store.loginItemDefaultApplied)
            store.loginItemDefaultApplied = true
            #expect(SettingsStore(defaults: defaults).loginItemDefaultApplied)
        }
    }

    @Test func saveDirectoryPersists() {
```

新建 `Core/Tests/GlimpseCoreTests/HotkeyRecordingTests.swift`：

```swift
import Testing
@testable import GlimpseCore

struct HotkeyRecordingTests {
    private let cmdShift = KeyCombo.command | KeyCombo.shift

    @Test func displaysModifiersInMacOrder() {
        #expect(KeyCombo.defaultScreenshot.displayString == "⇧⌘A")
        let all = KeyCombo(keyCode: 18, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.shift | KeyCombo.command)
        #expect(all.displayString == "⌃⌥⇧⌘1")
        #expect(KeyCombo(keyCode: 122, modifiers: 0).displayString == "F1")
        #expect(KeyCombo(keyCode: 49, modifiers: KeyCombo.option).displayString == "⌥Space")
        #expect(KeyCombo.symbols(forModifiers: KeyCombo.command | KeyCombo.control) == "⌃⌘")
    }

    @Test func recordsACommandCombo() {
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: cmdShift, other: nil)
                == .record(.defaultScreenshot))
    }

    @Test func dropsModifierBitsCarbonDoesNotUse() {
        // Caps Lock (alphaLock 0x400) must not end up in the stored combo.
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: cmdShift | 0x0400, other: nil)
                == .record(.defaultScreenshot))
    }

    @Test func plainEscapeCancelsAndPlainDeleteClears() {
        #expect(HotkeyRecording.interpret(keyCode: 53, modifiers: 0, other: nil) == .cancel)
        #expect(HotkeyRecording.interpret(keyCode: 51, modifiers: 0, other: nil) == .clear)
        #expect(HotkeyRecording.interpret(keyCode: 117, modifiers: 0, other: nil) == .clear)
    }

    @Test func needsCommandControlOrOption() {
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: 0, other: nil) == .reject(.needsModifier))
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: KeyCombo.shift, other: nil) == .reject(.needsModifier))
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: KeyCombo.control, other: nil)
                == .record(KeyCombo(keyCode: 0, modifiers: KeyCombo.control)))
    }

    @Test func rejectsShortcutsEveryAppUses() {
        for key: UInt32 in [12, 13, 8, 9, 7, 6, 0, 1, 4, 46, 48, 49, 43] { // Q W C V X Z A S H M Tab Space ,
            #expect(HotkeyRecording.interpret(keyCode: key, modifiers: KeyCombo.command, other: nil) == .reject(.reserved))
        }
        #expect(HotkeyRecording.interpret(keyCode: 6, modifiers: cmdShift, other: nil) == .reject(.reserved)) // ⇧⌘Z
        // ⌃Space and ⌃⌥Space switch input sources.
        #expect(HotkeyRecording.interpret(keyCode: 49, modifiers: KeyCombo.control, other: nil) == .reject(.reserved))
        #expect(HotkeyRecording.interpret(keyCode: 49, modifiers: KeyCombo.control | KeyCombo.option, other: nil)
                == .reject(.reserved))
        // With another modifier they are fair game: ⇧⌘A is the default, ⌃⌘Q is not taken here.
        #expect(HotkeyRecording.interpret(keyCode: 12, modifiers: KeyCombo.command | KeyCombo.control, other: nil)
                == .record(KeyCombo(keyCode: 12, modifiers: KeyCombo.command | KeyCombo.control)))
        #expect(HotkeyRecording.Rejection.reserved.message.contains("系统常用"))
    }

    @Test func reservedWinsOverTheOtherShortcut() {
        let commandQ = KeyCombo(keyCode: 12, modifiers: KeyCombo.command)
        #expect(HotkeyRecording.interpret(keyCode: 12, modifiers: KeyCombo.command, other: commandQ) == .reject(.reserved))
    }

    @Test func escapeAndDeleteWithModifiersAreRecorded() {
        #expect(HotkeyRecording.interpret(keyCode: 51, modifiers: KeyCombo.command, other: nil)
                == .record(KeyCombo(keyCode: 51, modifiers: KeyCombo.command))) // ⌘⌫
        #expect(HotkeyRecording.interpret(keyCode: 53, modifiers: KeyCombo.control | KeyCombo.option, other: nil)
                == .record(KeyCombo(keyCode: 53, modifiers: KeyCombo.control | KeyCombo.option))) // ⌃⌥⎋
    }

    @Test func optionAloneOnlyWithFunctionKeysOrSpace() {
        #expect(HotkeyRecording.interpret(keyCode: 14, modifiers: KeyCombo.option, other: nil) == .reject(.typesCharacter))
        #expect(HotkeyRecording.interpret(keyCode: 19, modifiers: KeyCombo.option | KeyCombo.shift, other: nil)
                == .reject(.typesCharacter))
        #expect(HotkeyRecording.interpret(keyCode: 49, modifiers: KeyCombo.option, other: nil)
                == .record(KeyCombo(keyCode: 49, modifiers: KeyCombo.option)))
        #expect(HotkeyRecording.interpret(keyCode: 96, modifiers: KeyCombo.option, other: nil)
                == .record(KeyCombo(keyCode: 96, modifiers: KeyCombo.option)))
        #expect(HotkeyRecording.interpret(keyCode: 49, modifiers: KeyCombo.option | KeyCombo.shift, other: nil)
                == .record(KeyCombo(keyCode: 49, modifiers: KeyCombo.option | KeyCombo.shift))) // ⌥⇧Space
        #expect(HotkeyRecording.interpret(keyCode: 14, modifiers: KeyCombo.option | KeyCombo.control, other: nil)
                == .record(KeyCombo(keyCode: 14, modifiers: KeyCombo.option | KeyCombo.control)))
        #expect(HotkeyRecording.Rejection.typesCharacter.message == "只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃")
    }

    @Test func functionKeysWorkAlone() {
        #expect(HotkeyRecording.interpret(keyCode: 96, modifiers: 0, other: nil) == .record(KeyCombo(keyCode: 96, modifiers: 0)))
        #expect(HotkeyRecording.interpret(keyCode: 96, modifiers: KeyCombo.shift, other: nil)
                == .record(KeyCombo(keyCode: 96, modifiers: KeyCombo.shift))) // ⇧F5
    }

    @Test func rejectsUnnamedKeysAndTheOtherShortcut() {
        // 82 is keypad 0.
        #expect(HotkeyRecording.interpret(keyCode: 82, modifiers: KeyCombo.command, other: nil) == .reject(.unsupportedKey))
        #expect(HotkeyRecording.interpret(keyCode: 0, modifiers: cmdShift, other: .defaultScreenshot)
                == .reject(.sameAsOther))
    }
}

struct AccentColorTests {
    @Test func systemHasNoFixedColour() {
        #expect(AccentColor.system.rgba(darkAppearance: false) == nil)
        #expect(AccentColor.allCases.first == .system)
    }

    @Test func presetsBrightenInDarkAppearance() {
        #expect(AccentColor.blue.rgba(darkAppearance: false) == RGBA(hex: 0x007AFF))
        #expect(AccentColor.blue.rgba(darkAppearance: true) == RGBA(hex: 0x0A84FF))
        for accent in AccentColor.allCases where accent != .system {
            let light = accent.rgba(darkAppearance: false)!, dark = accent.rgba(darkAppearance: true)!
            #expect(light != dark, "\(accent)")
        }
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "SettingsStoreTests|HotkeyRecordingTests|AccentColorTests"`
Expected: 编译失败，`value of type 'SettingsStore' has no member 'ocrHotkey'`、`cannot find 'HotkeyRecording' in scope` 等

- [ ] **Step 3：实现**

（1）`Core/Sources/GlimpseCore/Settings/SettingsStore.swift`：把

```swift
public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧A
    public static let defaultScreenshot = KeyCombo(keyCode: 0, modifiers: 0x0100 | 0x0200)
```

替换为

```swift
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘A
    public static let defaultScreenshot = KeyCombo(keyCode: 0, modifiers: KeyCombo.command | KeyCombo.shift)
```

（2）`Core/Sources/GlimpseCore/Settings/SettingsStore.swift`：把

```swift
    private enum Key {
        static let screenshotHotkey = "screenshotHotkey"
        static let saveDirectory = "saveDirectory"
    }
```

替换为

```swift
    private enum Key {
        static let screenshotHotkey = "screenshotHotkey"
        static let ocrHotkey = "ocrHotkey"
        static let saveDirectory = "saveDirectory"
        static let accentColor = "accentColor"
        static let loginItemDefaultApplied = "loginItemDefaultApplied"
    }
```

（3）`Core/Sources/GlimpseCore/Settings/SettingsStore.swift`：把

```swift
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
            guard let data = try? JSONEncoder().encode(newValue) else {
                assertionFailure("Failed to encode screenshotHotkey")
                return
            }
            defaults.set(data, forKey: Key.screenshotHotkey)
        }
    }
```

替换为

```swift
    /// `nil` means the user cleared the shortcut.
    public var screenshotHotkey: KeyCombo? {
        get { hotkey(forKey: Key.screenshotHotkey, default: .defaultScreenshot) }
        set { setHotkey(newValue, forKey: Key.screenshotHotkey) }
    }

    /// Not set by default (design doc §3.1): text recognition goes through the toolbar or the menu.
    public var ocrHotkey: KeyCombo? {
        get { hotkey(forKey: Key.ocrHotkey, default: nil) }
        set { setHotkey(newValue, forKey: Key.ocrHotkey) }
    }

    /// Unset or unreadable → `defaultValue`; a stored `nil` stays `nil` (the user cleared it).
    private func hotkey(forKey key: String, default defaultValue: KeyCombo?) -> KeyCombo? {
        guard let data = defaults.data(forKey: key) else { return defaultValue }
        do {
            return try JSONDecoder().decode(KeyCombo?.self, from: data)
        } catch {
            return defaultValue
        }
    }

    private func setHotkey(_ combo: KeyCombo?, forKey key: String) {
        guard let data = try? JSONEncoder().encode(combo) else {
            assertionFailure("Failed to encode \(key)")
            return
        }
        defaults.set(data, forKey: key)
    }

    /// The interface accent (design doc §3.9). An unknown stored name (say, from a later version) follows the system.
    public var accentColor: AccentColor {
        get { defaults.string(forKey: Key.accentColor).flatMap(AccentColor.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.accentColor) }
    }

    /// Launch at login defaults to on (design doc §3.9). The system keeps the real state; this only records
    /// that the default was applied once, so turning it off later sticks.
    public var loginItemDefaultApplied: Bool {
        get { defaults.bool(forKey: Key.loginItemDefaultApplied) }
        set { defaults.set(newValue, forKey: Key.loginItemDefaultApplied) }
    }
```

新建 `Core/Sources/GlimpseCore/Settings/AccentColor.swift`：

```swift
/// The interface accent picked in Settings (design doc §3.9, §4.2): the selection border and handles, the
/// selected toolbar button, ✓, the magnifier's crosshair. Never the annotation colours.
/// Persisted by name, so reordering cases cannot change a stored choice.
public enum AccentColor: String, CaseIterable, Codable, Sendable {
    /// The accent chosen in System Settings → Appearance.
    case system
    case blue, purple, pink, red, orange, green, graphite

    /// Name in the settings page.
    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .pink: "粉色"
        case .red: "红色"
        case .orange: "橙色"
        case .green: "绿色"
        case .graphite: "石墨色"
        }
    }

    /// The preset in light or dark appearance; nil for `.system`. Apple's system colours: the dark value is
    /// a step brighter so it keeps its contrast on dark glass (design doc §4.2).
    public func rgba(darkAppearance: Bool) -> RGBA? {
        switch self {
        case .system: nil
        case .blue: RGBA(hex: darkAppearance ? 0x0A84FF : 0x007AFF)
        case .purple: RGBA(hex: darkAppearance ? 0xBF5AF2 : 0xAF52DE)
        case .pink: RGBA(hex: darkAppearance ? 0xFF375F : 0xFF2D55)
        case .red: RGBA(hex: darkAppearance ? 0xFF453A : 0xFF3B30)
        case .orange: RGBA(hex: darkAppearance ? 0xFF9F0A : 0xFF9500)
        case .green: RGBA(hex: darkAppearance ? 0x30D158 : 0x34C759)
        case .graphite: RGBA(hex: darkAppearance ? 0x98989D : 0x8E8E93)
        }
    }
}
```

新建 `Core/Sources/GlimpseCore/Settings/HotkeyRecording.swift`：

```swift
extension KeyCombo {
    /// Carbon modifier flags (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    /// How macOS writes a shortcut: ⌃⌥⇧⌘ in that order, then the key, e.g. `⇧⌘A`. Keys without a name
    /// show their code, which the recorder never lets through (see `HotkeyRecording`).
    public var displayString: String {
        Self.symbols(forModifiers: modifiers) + (HotkeyRecording.keyName(keyCode) ?? "#\(keyCode)")
    }

    /// `⌃⌥⇧⌘` for the flags in `modifiers`, in macOS order; the recorder shows them while they are held.
    public static func symbols(forModifiers modifiers: UInt32) -> String {
        var text = ""
        if modifiers & control != 0 { text += "⌃" }
        if modifiers & option != 0 { text += "⌥" }
        if modifiers & shift != 0 { text += "⇧" }
        if modifiers & command != 0 { text += "⌘" }
        return text
    }
}

/// What the shortcut recorder in Settings does with a key press (design doc §3.1, §3.9).
public enum HotkeyRecording {
    public enum Outcome: Equatable, Sendable {
        /// Esc on its own: stop recording, keep the current shortcut.
        case cancel
        /// Delete on its own: clear the shortcut.
        case clear
        case record(KeyCombo)
        case reject(Rejection)
    }

    public enum Rejection: Equatable, Sendable {
        /// A plain key (or with ⇧ only) would fire while typing anywhere.
        case needsModifier
        /// A key the recorder cannot name (keypad, media keys, …).
        case unsupportedKey
        /// Already the other global shortcut.
        case sameAsOther
        /// A shortcut every app relies on (⌘Q, ⌘W, ⌘C, ⌘V, …) or the input-source switch (⌃Space):
        /// taking it globally would break it everywhere.
        case reserved
        /// ⌥ (or ⌥⇧) with a letter, digit or symbol types a character (⌥E → ´, ⌥2 → ™); taking it globally
        /// would stop those characters from being typed. With ⌥ alone only F-keys and Space are allowed.
        case typesCharacter

        public var message: String {
            switch self {
            case .needsModifier: "快捷键需要包含 ⌘、⌃ 或 ⌥"
            case .unsupportedKey: "不支持这个键，请换一个"
            case .sameAsOther: "已用作另一个快捷键，请换一个"
            case .reserved: "这是系统常用的快捷键（如拷贝、粘贴、退出），请换一个"
            case .typesCharacter: "只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃"
            }
        }
    }

    private static let space: UInt32 = 49
    private static let escape: UInt32 = 53
    private static let delete: UInt32 = 51
    private static let forwardDelete: UInt32 = 117

    /// `modifiers` are Carbon flags. `other` is the other action's shortcut, which this one may not repeat.
    public static func interpret(keyCode: UInt32, modifiers: UInt32, other: KeyCombo?) -> Outcome {
        let relevant = modifiers & (KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        if relevant == 0, keyCode == escape { return .cancel }
        if relevant == 0, keyCode == delete || keyCode == forwardDelete { return .clear }
        guard keyName(keyCode) != nil else { return .reject(.unsupportedKey) }
        let isFunctionKey = functionKeys.keys.contains(keyCode)
        let hasModifier = relevant & (KeyCombo.command | KeyCombo.option | KeyCombo.control) != 0
        guard hasModifier || isFunctionKey else { return .reject(.needsModifier) }
        let combo = KeyCombo(keyCode: keyCode, modifiers: relevant)
        if reservedCombos.contains(combo) { return .reject(.reserved) }
        // ⌥ without ⌘ or ⌃ only with F-keys and Space: anything else is a character on the keyboard.
        if relevant & (KeyCombo.command | KeyCombo.control) == 0, relevant & KeyCombo.option != 0,
           !isFunctionKey, keyCode != space {
            return .reject(.typesCharacter)
        }
        if combo == other { return .reject(.sameAsOther) }
        return .record(combo)
    }

    /// ⌘Q W C V X Z A S H M Tab Space , and ⇧⌘Z: quit, close, copy, paste, cut, undo, select all, save, hide,
    /// minimise, app switcher, Spotlight, settings, redo. ⌃Space and ⌃⌥Space: previous / next input source.
    private static let reservedCombos: Set<KeyCombo> = {
        let commandKeys: [UInt32] = [12, 13, 8, 9, 7, 6, 0, 1, 4, 46, 48, 49, 43]
        return Set(commandKeys.map { KeyCombo(keyCode: $0, modifiers: KeyCombo.command) }
                   + [KeyCombo(keyCode: 6, modifiers: KeyCombo.command | KeyCombo.shift),
                      KeyCombo(keyCode: space, modifiers: KeyCombo.control),
                      KeyCombo(keyCode: space, modifiers: KeyCombo.control | KeyCombo.option)])
    }()

    /// The key's label on an ANSI keyboard, by Carbon virtual key code; nil for keys the recorder skips.
    public static func keyName(_ keyCode: UInt32) -> String? {
        characterKeys[keyCode] ?? functionKeys[keyCode] ?? namedKeys[keyCode]
    }

    private static let characterKeys: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test`
Expected: `Test run with 170 tests in 26 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 2：界面强调色接到覆盖层

**Files:**
- Create: `App/Sources/Material/InterfaceAccent.swift`
- Modify: `App/Sources/Overlay/SelectionView.swift`、`App/Sources/Toolbar/ToolbarButton.swift`、`App/Sources/Toolbar/StylePaletteView.swift`、`App/Sources/Overlay/MagnifierView.swift`

`NSColor.glimpseAccent` 是动态颜色：选了预设就用预设在当前外观下的值，否则解析系统强调色。`InterfaceAccent.current` 由 `AppDelegate` 在启动时、设置页在每次改动时写入（Task 4）；本任务结束时它还一直是「跟随系统」，外观与现在完全一样。覆盖层每次截图新建，所以下一次截图就会用上新颜色；把颜色缓存成 `CGColor`（`ToolbarButton` 的图层）或画进内容（`SelectionView` 的边框和手柄、二级栏选中色块的外圈、放大镜的十字线）的视图各持有一个 `AccentObservation`，Glimpse 的选择或系统强调色一变就立即刷新（实施前说明第 6 条）。

- [ ] **Step 1：新增 InterfaceAccent，替换 6 处 controlAccentColor，接上即时刷新**

新建 `App/Sources/Material/InterfaceAccent.swift`：

```swift
import AppKit
import GlimpseCore
import os

/// The accent picked in Settings (design doc §3.9). Set at launch and on every change; read whenever
/// `NSColor.glimpseAccent` resolves, which AppKit may do off the main thread, hence the lock.
enum InterfaceAccent {
    private static let choice = OSAllocatedUnfairLock(initialState: AccentColor.system)

    /// Posted on the main thread when the choice changes.
    static let didChangeNotification = Notification.Name("GlimpseInterfaceAccentDidChange")

    static var current: AccentColor {
        get { choice.withLock { $0 } }
        set {
            let previous = choice.withLock { stored in
                let previous = stored
                stored = newValue
                return previous
            }
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
}

extension NSColor {
    /// Glimpse's interface accent: the selection border and handles, the selected toolbar button, ✓, the
    /// chosen colour swatch's ring, the magnifier's crosshair (design doc §3.9, §4.3). The system accent,
    /// or the preset picked in Settings, a step brighter in dark appearance. Annotation colours never use it.
    /// Resolved each time it is drawn; views that keep it as a CGColor refresh through `AccentObservation`.
    static let glimpseAccent = NSColor(name: "glimpseAccent") { appearance in
        if let preset = InterfaceAccent.current.rgba(darkAppearance: appearance.isDark) {
            return preset.nsColor
        }
        var system = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            system = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        }
        return system
    }
}

/// Calls `handler` on the main thread whenever the accent may look different: the Settings choice changed,
/// or the system accent changed (System Settings → Appearance), which matters while following the system.
/// Views that cache the accent as a CGColor or in drawn content keep one of these for as long as they live.
final class AccentObservation {
    private var tokens: [NSObjectProtocol] = []

    init(_ handler: @escaping @MainActor () -> Void) {
        for name in [InterfaceAccent.didChangeNotification, NSColor.systemColorsDidChangeNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}
```

（1）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        let accent = NSColor.controlAccentColor
```

替换为

```swift
        let accent = NSColor.glimpseAccent
```

（2）`App/Sources/Toolbar/ToolbarButton.swift`：把

```swift
                fill = .controlAccentColor
```

替换为

```swift
                fill = .glimpseAccent
```

（3）`App/Sources/Toolbar/ToolbarButton.swift`：把

```swift
                layer?.shadowColor = NSColor.controlAccentColor.cgColor
```

替换为

```swift
                layer?.shadowColor = NSColor.glimpseAccent.cgColor
```

（4）`App/Sources/Toolbar/ToolbarButton.swift`：把

```swift
                contentTintColor = item == .confirm ? .controlAccentColor : .materialText
```

替换为

```swift
                contentTintColor = item == .confirm ? .glimpseAccent : .materialText
```

（5）`App/Sources/Toolbar/StylePaletteView.swift`：把

```swift
                NSColor.controlAccentColor.setFill()
```

替换为

```swift
                NSColor.glimpseAccent.setFill()
```

（6）`App/Sources/Toolbar/StylePaletteView.swift`：把

```swift
    var isChosen = false {
        didSet { if isChosen != oldValue { needsDisplay = true } }
    }
```

替换为

```swift
    var isChosen = false {
        didSet { if isChosen != oldValue { needsDisplay = true } }
    }
    /// Redraws the chosen swatch's accent ring when the accent changes.
    private var accentObservation: AccentObservation?
```

（7）`App/Sources/Toolbar/StylePaletteView.swift`：把

```swift
        self.target = target
        self.action = action
        // VoiceOver names only
```

替换为

```swift
        self.target = target
        self.action = action
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
        // VoiceOver names only
```

（8）`App/Sources/Overlay/MagnifierView.swift`：把

```swift
        NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
```

替换为

```swift
        NSColor.glimpseAccent.withAlphaComponent(0.6).setFill()
```

（9）`App/Sources/Overlay/MagnifierView.swift`：把

```swift
    var center: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
```

替换为

```swift
    var center: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    /// Redraws the crosshair when the accent changes.
    private var accentObservation: AccentObservation?
```

（10）`App/Sources/Overlay/MagnifierView.swift`：把

```swift
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
```

替换为

```swift
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
    }
```

（11）`App/Sources/Toolbar/ToolbarButton.swift`：把

```swift
    private var hoverArea: NSTrackingArea?
```

替换为

```swift
    private var hoverArea: NSTrackingArea?
    /// Layer colours are CGColors: resolve them again when the accent changes.
    private var accentObservation: AccentObservation?
```

（12）`App/Sources/Toolbar/ToolbarButton.swift`：把

```swift
        self.action = action
        refreshColors()
    }
```

替换为

```swift
        self.action = action
        refreshColors()
        accentObservation = AccentObservation { [weak self] in self?.refreshColors() }
    }
```

（13）`App/Sources/Overlay/SelectionView.swift`：把

```swift
    private var displayedExtent: CGRect = .null
```

替换为

```swift
    private var displayedExtent: CGRect = .null
    /// Redraws the border and handles when the accent changes.
    private var accentObservation: AccentObservation?
```

（14）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        self.canvas = canvas
        super.init(frame: frame)
    }
```

替换为

```swift
        self.canvas = canvas
        super.init(frame: frame)
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
    }
```

- [ ] **Step 2：确认没有遗漏**

Run: `cd . && grep -rn "controlAccentColor" App/Sources`
Expected: 只剩 `App/Sources/Material/InterfaceAccent.swift` 里的两行（「跟随系统」时解析系统强调色）

- [ ] **Step 3：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行输出 `build/Build/Products/Debug/Glimpse.app`（证书被吊销期间 stderr 会有 `warning: … signing ad-hoc …`，属于正常）

- [ ] **Step 4：停下，不 commit**

---

### Task 3：全局快捷键控制器、开机自动启动服务

**Files:**
- Modify: `App/Sources/Services/HotkeyService.swift`
- Create: `App/Sources/Services/HotkeyController.swift`
- Create: `App/Sources/Services/LoginItemService.swift`

`HotkeyController` 把「设置里存了什么」「Carbon 里注册了什么」「哪个注册失败」放在一起（实施前说明第 4、5 条）：`registerAll()` 在启动和录制结束时调用；`suspend()` 在录制开始时取消全部注册；`set(_:for:)` 应用设置页的新组合，注册成功才保存；`failures` 给设置页标红；`onChange` 让菜单显示正在生效的快捷键。`LoginItemService` 包一层 `SMAppService.mainApp`（第 8 条）。本任务只新增类型，下一个任务接上。

- [ ] **Step 1：HotkeyAction 加识别文字，新增两个服务**

（1）`App/Sources/Services/HotkeyService.swift`：把

```swift
/// Global shortcuts Glimpse registers. P3 adds `case ocr = 2`.
enum HotkeyAction: UInt32 {
    case screenshot = 1
}
```

替换为

```swift
/// Global shortcuts Glimpse registers (design doc §3.1).
enum HotkeyAction: UInt32, CaseIterable {
    case screenshot = 1
    /// 识别文字; not set by default.
    case ocr = 2
}
```

（2）`App/Sources/Services/HotkeyService.swift`：把

```swift
    // Not called yet: the settings page (P3) uses it when the user clears a shortcut.
    func unregister(
```

替换为

```swift
    func unregister(
```

新建 `App/Sources/Services/HotkeyController.swift`：

```swift
import AppKit
import GlimpseCore

/// The global shortcuts (design doc §3.1): registers what `SettingsStore` holds, applies changes from
/// the settings page, and remembers which stored shortcut failed to register so the page can show it red.
/// A shortcut that fails to register stays stored, so it is tried again on the next launch.
@MainActor
final class HotkeyController {
    private let settings: SettingsStore
    private let service = HotkeyService()
    private let handlers: [HotkeyAction: () -> Void]
    /// Stored shortcuts that are not registered right now (taken by another program).
    private(set) var failures: Set<HotkeyAction> = []
    /// What is registered changed: the status menu shows the working shortcuts.
    var onChange: (() -> Void)?

    init(settings: SettingsStore, handlers: [HotkeyAction: () -> Void]) {
        self.settings = settings
        self.handlers = handlers
    }

    /// The stored shortcut, working or not; nil when cleared (or never set).
    func combo(for action: HotkeyAction) -> KeyCombo? {
        switch action {
        case .screenshot: settings.screenshotHotkey
        case .ocr: settings.ocrHotkey
        }
    }

    /// The stored shortcut if it is registered; what the menu shows.
    func activeCombo(for action: HotkeyAction) -> KeyCombo? {
        failures.contains(action) ? nil : combo(for: action)
    }

    /// Registers every stored shortcut (launch, and after recording).
    func registerAll() {
        for action in HotkeyAction.allCases {
            if let combo = combo(for: action) {
                let result = register(combo, for: action)
                if result == .registered {
                    failures.remove(action)
                } else {
                    failures.insert(action)
                    NSLog("Glimpse: failed to register %@ hotkey: %@", String(describing: action), String(describing: result))
                }
            } else {
                service.unregister(action)
                failures.remove(action)
            }
        }
        onChange?()
    }

    /// Takes every shortcut off while the settings page records one: Carbon would otherwise grab the
    /// current shortcut before the recorder sees it. `registerAll()` puts them back.
    func suspend() {
        HotkeyAction.allCases.forEach(service.unregister)
    }

    /// Applies a shortcut from the settings page. A new combo is stored only once it registers; on failure
    /// the previous one stays in place and the result says why. Clearing always succeeds.
    @discardableResult
    func set(_ combo: KeyCombo?, for action: HotkeyAction) -> HotkeyRegistrationResult {
        guard let combo else {
            service.unregister(action)
            store(nil, for: action)
            failures.remove(action)
            onChange?()
            return .registered
        }
        let result = register(combo, for: action)
        if result == .registered {
            store(combo, for: action)
            failures.remove(action)
            onChange?()
        }
        return result
    }

    private func register(_ combo: KeyCombo, for action: HotkeyAction) -> HotkeyRegistrationResult {
        service.register(combo, for: action, handler: handlers[action] ?? {})
    }

    private func store(_ combo: KeyCombo?, for action: HotkeyAction) {
        switch action {
        case .screenshot: settings.screenshotHotkey = combo
        case .ocr: settings.ocrHotkey = combo
        }
    }
}
```

新建 `App/Sources/Services/LoginItemService.swift`：

```swift
import Foundation
import GlimpseCore
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (design doc §3.9, §5.1). The system holds the state;
/// nothing is mirrored in Glimpse's settings except that the default was applied once.
@MainActor
enum LoginItemService {
    enum Failure: LocalizedError {
        /// Registered, but switched off in System Settings → General → Login Items.
        case requiresApproval
        case system(String)

        var errorDescription: String? {
            switch self {
            case .requiresApproval: "需要在「系统设置 → 通用 → 登录项」里允许 Glimpse"
            case .system(let reason): "开启失败：\(reason)"
            }
        }
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Throws `Failure` with a reason for the user; the switch then goes back (design doc §6).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            // register() also throws when the item is already there; the status says what actually holds.
            switch service.status {
            case .enabled where enabled, .notRegistered where !enabled: return
            case .requiresApproval where enabled: throw Failure.requiresApproval
            default: throw Failure.system(error.localizedDescription)
            }
        }
        if enabled, service.status == .requiresApproval { throw Failure.requiresApproval }
    }

    /// On by default (design doc §3.9): turned on once, on the first launch; after that only the user changes it.
    /// Not in Debug builds: the development build in build/ must never register itself as a login item
    /// (the switch in Settings still works by hand). A Release build then applies the default on its first run.
    static func applyDefault(settings: SettingsStore) {
        #if DEBUG
        return
        #else
        guard !settings.loginItemDefaultApplied else { return }
        settings.loginItemDefaultApplied = true
        do {
            try setEnabled(true)
        } catch {
            NSLog("Glimpse: could not turn on launch at login: \(error.localizedDescription)")
        }
        #endif
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 2：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行输出 app 路径

- [ ] **Step 3：停下，不 commit**

---

### Task 4：设置窗口

**Files:**
- Create: `App/Sources/Settings/HotkeyRecorderButton.swift`、`SettingsModel.swift`、`SettingsView.swift`、`SettingsWindowController.swift`
- Create: `App/Sources/Services/DockPresence.swift`
- Modify（整体替换）: `App/Sources/MenuBar/StatusItemController.swift`、`App/Sources/MenuBar/KeyCombo+Menu.swift`、`App/Sources/AppDelegate.swift`
- Modify: `project.yml`（「桌面」「文稿」的访问说明）

- `HotkeyRecorderButton`：`NSButton`（push 样式）。录制时把自己设成第一响应者：带 ⌘ 的组合先到 `performKeyEquivalent`，其余到 `keyDown`，修饰键变化到 `flagsChanged`（实时显示）。结束录制时先通知外面恢复快捷键，再交出结果。失去第一响应者（点别处）、离开窗口都结束录制。
- `SettingsModel`（`@Observable`）：页面显示的值和所有动作；每次改动立即写入 `SettingsStore` / 系统。快捷键和登录项分开重读（`reloadLoginItem()` 只在 Glimpse 重新变成活跃应用时调用，不清快捷键的红字）；选保存目录的面板以 sheet 挂在设置窗口上。
- `SettingsView`：分组表单，五组：快捷键（脚注是常驻提示）、外观、保存、通用、关于（第 1 条）。
- `SettingsWindowController`：只建一个窗口，第一次打开时创建；打开时激活 Glimpse（菜单栏应用从自己的菜单激活是允许的）；窗口关闭或不再是 key 时结束录制，免得快捷键一直处于暂停状态；`⌘W` / `⌘Q`（第 2 条，只看 ⌘⇧⌥⌃ 四个修饰键，开着大写锁定也能用）；吞掉录制后仍按住的键的自动重复。
- `DockPresence`：设置窗口、引导窗口打开时显示 Dock 图标，都关掉时回到菜单栏应用并把键盘还给最近一个在前面的其他应用（实施前说明第 23 条）；设置窗口在 `willClose` 时移除。录制按钮在录制期间装本地鼠标事件监视器，点按钮以外的任何地方都结束录制（第 4 条）。
- `KeyCombo+Menu` 整体替换：键表补全到录制按钮能录的所有键（第 2 条）。
- `StatusItemController` 整体替换：加「设置…」；`updateCaptureShortcut(_:)` 换成按动作更新的 `updateShortcut(_:for:)`（批次 C 加「识别文字」项时不用再改这个方法）。
- `AppDelegate` 整体替换：启动时设置强调色、应用开机启动默认值（Debug 编译跳过，第 8 条）、建 `HotkeyController`（识别文字的 handler 暂时只响一声，第 9 条）、建设置窗口。

- [ ] **Step 1：录制按钮、设置页、设置窗口**

新建 `App/Sources/Services/DockPresence.swift`：

```swift
import AppKit

/// Glimpse is a menu-bar app with no Dock icon. While the settings or onboarding window is open it shows in
/// the Dock and in ⌘Tab, so the window can be found again behind other apps; once both are closed it goes back
/// to the menu bar only and hands the keyboard back to the app that was in front before.
@MainActor
enum DockPresence {
    private static var windows: Set<ObjectIdentifier> = []
    /// The last app other than Glimpse to become active; it gets the keyboard back. Kept current while
    /// one of our windows is open, so returning to Glimpse through the Dock or ⌘Tab hands back to the app
    /// the user just left, not the one in front when the window first opened.
    private static var previousApp: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    static func add(_ window: NSWindow) {
        watchActivations()
        guard windows.insert(ObjectIdentifier(window)).inserted, windows.count == 1 else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func remove(_ window: NSWindow) {
        guard windows.remove(ObjectIdentifier(window)) != nil, windows.isEmpty else { return }
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(.accessory)
        // Not NSApp.hide: it would hide the pinned screenshots too. Under cooperative activation (macOS 14+)
        // Glimpse yields first, so the other app's activate() is honoured.
        if wasActive, let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }

    /// Shows `window` in front with the keyboard and activates Glimpse. From the menu bar menu or at launch
    /// macOS grants the activation; from a global shortcut it may refuse it (cooperative activation on
    /// macOS 14+), so the window is ordered front and made key first, and is visible and usable either way.
    static func bringToFront(_ window: NSWindow) {
        if !NSApp.isActive, let app = NSWorkspace.shared.frontmostApplication, !isGlimpse(app) {
            previousApp = app
        }
        add(window)
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    /// Remembers every other app that becomes active, from the first time one of our windows opens.
    private static func watchActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, !isGlimpse(app) { previousApp = app }
            }
        }
    }

    private static func isGlimpse(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
```

新建 `App/Sources/Settings/HotkeyRecorderButton.swift`：

```swift
import AppKit
import GlimpseCore

/// A push button that records a global shortcut (design doc §3.9). Click it, then press the shortcut:
/// Esc cancels, Delete clears, anything else goes through `HotkeyRecording`. While recording it holds the
/// keyboard and shows the modifiers being held; clicking anywhere else (even on something that never takes
/// the keyboard, like the form's background or the clear button), leaving the window or closing it cancels.
final class HotkeyRecorderButton: NSButton {
    var combo: KeyCombo? {
        didSet { if combo != oldValue { refreshTitle() } }
    }
    /// The other action's shortcut, which this one may not repeat.
    var otherCombo: KeyCombo?
    /// Recording started (true) or ended (false). The owner suspends the global shortcuts meanwhile.
    var onRecordingChange: ((Bool) -> Void)?
    var onOutcome: ((HotkeyRecording.Outcome) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            isRecording ? watchClicks() : stopWatchingClicks()
            refreshTitle()
            onRecordingChange?(isRecording)
        }
    }
    private var heldModifiers: UInt32 = 0
    /// While recording: clicks anywhere in Glimpse, so one outside the button ends the recording. A click on
    /// a view that never becomes first responder would not take the keyboard away, so resigning alone
    /// does not cover it.
    private var clickMonitor: Any?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 140, height: 24))
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isRecording }

    @objc private func clicked() {
        if isRecording {
            stopRecording()
        } else {
            heldModifiers = 0
            isRecording = true
            window?.makeFirstResponder(self)
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    private func watchClicks() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let inside = event.window === self.window
                    && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                if !inside { self.stopRecording() } // a click on the button itself toggles it in clicked()
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false // clicking elsewhere cancels
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { isRecording = false }
        super.viewWillMove(toWindow: newWindow)
    }

    /// ⌘ combos arrive here, before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        heldModifiers = Self.carbonModifiers(event.modifierFlags)
        refreshTitle()
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return } // a key held since before recording began
        let outcome = HotkeyRecording.interpret(keyCode: UInt32(event.keyCode),
                                                modifiers: Self.carbonModifiers(event.modifierFlags),
                                                other: otherCombo)
        stopRecording() // first, so the shortcuts are back before the new one is applied
        onOutcome?(outcome)
    }

    private func refreshTitle() {
        if isRecording {
            let held = KeyCombo.symbols(forModifiers: heldModifiers)
            title = held.isEmpty ? "请按快捷键…" : held
        } else {
            title = combo?.displayString ?? "点击录制"
        }
        setAccessibilityLabel(isRecording ? "正在录制快捷键" : (combo.map { "快捷键 \($0.displayString)" } ?? "未设置快捷键"))
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        return modifiers
    }
}
```

新建 `App/Sources/Settings/SettingsModel.swift`：

```swift
import AppKit
import GlimpseCore
import Observation
import ServiceManagement

/// What the settings page shows and changes (design doc §3.9). Every change applies at once and is
/// stored in `SettingsStore`; launch at login lives in the system (`LoginItemService`).
@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let hotkeys: HotkeyController
    /// The settings window: the folder picker opens as a sheet on it.
    @ObservationIgnored weak var sheetParent: NSWindow?

    private(set) var screenshotHotkey: KeyCombo?
    private(set) var ocrHotkey: KeyCombo?
    /// The red line under a shortcut: a failed registration or a rejected key. Nil when it works.
    private(set) var hotkeyErrors: [HotkeyAction: String] = [:]
    private(set) var accent: AccentColor
    private(set) var saveDirectory: URL
    private(set) var launchAtLogin = false
    private(set) var loginItemError: String?
    /// The error is fixed in System Settings → Login Items; the page offers a button for it.
    private(set) var loginItemNeedsApproval = false
    /// The system's state when `loginItemError` was set: the error stays until that state changes.
    @ObservationIgnored private var statusAtLoginItemError: SMAppService.Status?

    init(settings: SettingsStore, hotkeys: HotkeyController) {
        self.settings = settings
        self.hotkeys = hotkeys
        accent = settings.accentColor
        saveDirectory = settings.saveDirectory
        reload()
    }

    /// Reads everything again when the window opens.
    func reload() {
        reloadHotkeys()
        saveDirectory = settings.saveDirectory
        reloadLoginItem()
    }

    /// The stored shortcuts, and a red line for each one that is not registered.
    private func reloadHotkeys() {
        screenshotHotkey = hotkeys.combo(for: .screenshot)
        ocrHotkey = hotkeys.combo(for: .ocr)
        hotkeyErrors = [:]
        for action in hotkeys.failures {
            if let combo = hotkeys.combo(for: action) { hotkeyErrors[action] = Self.unavailableMessage(combo) }
        }
    }

    /// The system's login item state, also when Glimpse comes back from System Settings. Switched off in
    /// System Settings → Login Items shows the hint and its button right away; any other error stays until
    /// the system's state changes.
    func reloadLoginItem() {
        let status = LoginItemService.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemError = LoginItemService.Failure.requiresApproval.errorDescription
            loginItemNeedsApproval = true
            statusAtLoginItemError = status
        } else if loginItemError != nil, loginItemNeedsApproval || status != statusAtLoginItemError {
            loginItemError = nil
            loginItemNeedsApproval = false
            statusAtLoginItemError = nil
        }
    }

    // MARK: - Shortcuts

    func combo(for action: HotkeyAction) -> KeyCombo? {
        action == .screenshot ? screenshotHotkey : ocrHotkey
    }

    func recordingChanged(_ recording: Bool, for action: HotkeyAction) {
        if recording {
            hotkeyErrors[action] = nil
            hotkeys.suspend()
        } else {
            // Ended without a key too (a click elsewhere): a shortcut that still fails gets its red line back.
            hotkeys.registerAll()
            reloadHotkeys()
        }
    }

    func apply(_ outcome: HotkeyRecording.Outcome, for action: HotkeyAction) {
        switch outcome {
        case .cancel:
            reloadHotkeys()
        case .clear:
            hotkeys.set(nil, for: action)
            reloadHotkeys()
        case .record(let combo):
            let result = hotkeys.set(combo, for: action)
            reloadHotkeys()
            if result != .registered { hotkeyErrors[action] = Self.failureMessage(combo, result) }
        case .reject(let rejection):
            reloadHotkeys()
            hotkeyErrors[action] = rejection.message
        }
    }

    private static func unavailableMessage(_ combo: KeyCombo) -> String {
        "「\(combo.displayString)」没有注册成功，现在不可用，请换一个"
    }

    private static func failureMessage(_ combo: KeyCombo, _ result: HotkeyRegistrationResult) -> String {
        switch result {
        case .conflict: "「\(combo.displayString)」已被其他程序占用，请换一个"
        case .failed(let status): "「\(combo.displayString)」注册失败（\(status)），请换一个"
        case .registered: ""
        }
    }

    // MARK: - Accent

    func setAccent(_ accent: AccentColor) {
        self.accent = accent
        settings.accentColor = accent
        InterfaceAccent.current = accent
    }

    // MARK: - Save folder

    /// The folder's name as Finder shows it (「下载」).
    var saveDirectoryName: String { FileManager.default.displayName(atPath: saveDirectory.path) }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        panel.prompt = "选择"
        panel.message = "选择截图的保存位置"
        guard let window = sheetParent else {
            if panel.runModal() == .OK, let url = panel.url { useSaveDirectory(url) }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useSaveDirectory(url) }
        }
    }

    private func useSaveDirectory(_ url: URL) {
        settings.saveDirectory = url
        saveDirectory = settings.saveDirectory
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        // Follow the switch first and clear the old error, so putting it back below is always a change the
        // page sees, even when the same failure happens twice in a row.
        launchAtLogin = enabled
        loginItemError = nil
        loginItemNeedsApproval = false
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            loginItemError = error.localizedDescription
            loginItemNeedsApproval = (error as? LoginItemService.Failure).map {
                if case .requiresApproval = $0 { true } else { false }
            } ?? false
            statusAtLoginItemError = LoginItemService.status
        }
        launchAtLogin = LoginItemService.isEnabled // a failure puts the switch back (design doc §6)
    }

    // MARK: - About

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short)（\(build)）"
    }
}
```

新建 `App/Sources/Settings/SettingsView.swift`：

```swift
import AppKit
import GlimpseCore
import SwiftUI

/// The settings page (design doc §3.9): a grouped form, like System Settings.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                shortcutRow("截图", action: .screenshot)
                shortcutRow("识别文字", action: .ocr)
            } header: {
                Text("快捷键")
            } footer: {
                Text("按快捷键没反应时，可能被微信、QQ 等应用的截图快捷键占用，请在那边改掉，或在这里换一个")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("界面强调色") {
                    AccentSwatches(selection: model.accent) { model.setAccent($0) }
                }
            } header: {
                Text("外观")
            } footer: {
                Text("用于选区边框、手柄、选中的按钮和 ✓，不影响标注颜色")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("保存") {
                LabeledContent("保存目录") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.saveDirectory.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(model.saveDirectoryName)
                            .help(model.saveDirectory.path)
                        Button("更改…") { model.chooseSaveDirectory() }
                    }
                }
            }

            Section("通用") {
                Toggle("开机自动启动", isOn: Binding(get: { model.launchAtLogin },
                                                  set: { model.setLaunchAtLogin($0) }))
                if let error = model.loginItemError {
                    HStack {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                        if model.loginItemNeedsApproval {
                            Spacer()
                            Button("打开登录项设置") { LoginItemService.openSystemSettings() }
                        }
                    }
                }
            }

            Section("关于") {
                LabeledContent("Glimpse · 瞥", value: "版本 \(model.version)")
                Text("截图、标注、识别文字都在本机完成，不联网，也不保存截图历史。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
    }

    private func shortcutRow(_ title: String, action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    HotkeyRecorder(combo: model.combo(for: action),
                                   otherCombo: model.combo(for: action == .screenshot ? .ocr : .screenshot),
                                   onRecordingChange: { model.recordingChanged($0, for: action) },
                                   onOutcome: { model.apply($0, for: action) })
                        .frame(width: 140)
                    Button {
                        model.apply(.clear, for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("清除")
                    .opacity(model.combo(for: action) == nil ? 0 : 1)
                    .disabled(model.combo(for: action) == nil)
                }
            }
            if let error = model.hotkeyErrors[action] {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// The recorder button inside the form.
private struct HotkeyRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let otherCombo: KeyCombo?
    let onRecordingChange: (Bool) -> Void
    let onOutcome: (HotkeyRecording.Outcome) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        HotkeyRecorderButton()
    }

    func updateNSView(_ button: HotkeyRecorderButton, context: Context) {
        button.combo = combo
        button.otherCombo = otherCombo
        button.onRecordingChange = onRecordingChange
        button.onOutcome = onOutcome
    }
}

/// 跟随系统 and the presets as colour dots, like the accent row in System Settings. The chosen dot has a
/// white centre; the name shows on hover.
private struct AccentSwatches: View {
    let selection: AccentColor
    let onPick: (AccentColor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentColor.allCases, id: \.self) { accent in
                Button {
                    onPick(accent)
                } label: {
                    swatch(accent)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if accent == selection {
                                Circle().fill(.white).frame(width: 6, height: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(accent.title)
                .accessibilityLabel(accent.title)
                .accessibilityAddTraits(accent == selection ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func swatch(_ accent: AccentColor) -> some View {
        if accent == .system {
            Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                          center: .center))
        } else {
            Circle().fill(Color(nsColor: NSColor(name: nil) { appearance in
                accent.rgba(darkAppearance: appearance.isDark)?.nsColor ?? .controlAccentColor
            }))
        }
    }
}
```

新建 `App/Sources/Settings/SettingsWindowController.swift`：

```swift
import AppKit
import SwiftUI

/// The settings window, opened from the menu bar's 「设置…」 (design doc §3.7, §3.9). One window, created
/// on first use and kept; Glimpse is activated so the window comes to the front, and has a Dock icon
/// while it is open (DockPresence).
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        model.reload()
        let window = self.window ?? makeWindow()
        self.window = window
        model.sheetParent = window
        DockPresence.bringToFront(window)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Glimpse 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let window { DockPresence.remove(window) }
            }
        }
        // Back from System Settings (login items): show what changed there. Only the login item: a
        // shortcut's red line must survive switching apps.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isVisible == true else { return }
                self.model.reloadLoginItem()
            }
        }
        return window
    }
}

/// A menu-bar app has no main menu, so ⌘W and ⌘Q are handled here. Offered to the views first, so the
/// shortcut recorder can take them while it records.
private final class SettingsWindow: NSWindow {
    /// The recorder keeps the global shortcuts off while it records: closing the window or leaving it
    /// for another one ends the recording, which puts them back.
    override func close() {
        endRecording()
        super.close()
    }

    override func resignKey() {
        super.resignKey()
        endRecording()
    }

    private func endRecording() {
        if firstResponder is HotkeyRecorderButton { makeFirstResponder(nil) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        // Only these four count: Caps Lock or fn must not stop ⌘W.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command else { return false }
        var key = event.charactersIgnoringModifiers?.lowercased()
        if let typed = key, !typed.unicodeScalars.allSatisfy(\.isASCII) {
            key = [13: "w", 12: "q"][event.keyCode] // a layout without Latin letters (Russian, Greek…): by key code
        }
        switch key {
        case "w":
            // A ⌘W still held after the recorder rejected it repeats here: it must not close the window.
            if !event.isARepeat { performClose(nil) }
            return true
        case "q":
            if !event.isARepeat { NSApp.terminate(nil) }
            return true
        default:
            return false
        }
    }

    /// A key still held after the recorder took it repeats with nobody to take it: swallow the repeats
    /// instead of beeping at each one.
    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        super.keyDown(with: event)
    }
}
```

`App/Sources/MenuBar/StatusItemController.swift` 整体替换为：

```swift
import AppKit
import GlimpseCore

/// The menu bar icon and its menu (design doc §3.7): 截图, 设置…, 退出.
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Time for the menu to finish fading out so it doesn't end up in the screenshot.
    private static let menuFadeDelay: TimeInterval = 0.25

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    /// The items that start a global-shortcut action; they show the shortcut while it works.
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private var isMenuOpen = false

    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glimpse")

        let captureItem = NSMenuItem(title: "截图", action: #selector(captureClicked), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        actionItems[.screenshot] = captureItem
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Glimpse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    /// Shows `combo` next to the item for `action`; clears it when nil or not representable in a menu.
    func updateShortcut(_ combo: KeyCombo?, for action: HotkeyAction) {
        guard let menuItem = actionItems[action] else { return }
        if let combo, let key = combo.menuKeyEquivalent {
            menuItem.keyEquivalent = key
            menuItem.keyEquivalentModifierMask = combo.menuModifierMask
        } else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }

    /// Closes the status menu first if it is open, then runs `action` once it has faded out.
    func performAfterMenuCloses(_ action: @escaping () -> Void) {
        guard isMenuOpen else {
            action()
            return
        }
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { action() }
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    @objc private func captureClicked() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { [onCapture] in onCapture() }
    }

    @objc private func settingsClicked() {
        onSettings()
    }
}
```

`App/Sources/MenuBar/KeyCombo+Menu.swift` 整体替换为：

```swift
import AppKit
import Carbon.HIToolbox
import GlimpseCore

extension KeyCombo {
    /// Every key the shortcut recorder accepts (HotkeyRecording), as the menu key equivalent AppKit draws.
    private static let menuCharacters: [UInt32: String] = {
        func function(_ key: Int) -> String { String(Character(UnicodeScalar(UInt32(key))!)) }
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "a"), (kVK_ANSI_B, "b"), (kVK_ANSI_C, "c"), (kVK_ANSI_D, "d"),
            (kVK_ANSI_E, "e"), (kVK_ANSI_F, "f"), (kVK_ANSI_G, "g"), (kVK_ANSI_H, "h"),
            (kVK_ANSI_I, "i"), (kVK_ANSI_J, "j"), (kVK_ANSI_K, "k"), (kVK_ANSI_L, "l"),
            (kVK_ANSI_M, "m"), (kVK_ANSI_N, "n"), (kVK_ANSI_O, "o"), (kVK_ANSI_P, "p"),
            (kVK_ANSI_Q, "q"), (kVK_ANSI_R, "r"), (kVK_ANSI_S, "s"), (kVK_ANSI_T, "t"),
            (kVK_ANSI_U, "u"), (kVK_ANSI_V, "v"), (kVK_ANSI_W, "w"), (kVK_ANSI_X, "x"),
            (kVK_ANSI_Y, "y"), (kVK_ANSI_Z, "z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
            (kVK_Space, " "), (kVK_Return, "\r"), (kVK_Tab, "\t"), (kVK_Delete, "\u{8}"), (kVK_Escape, "\u{1b}"),
            (kVK_ForwardDelete, function(NSDeleteFunctionKey)),
            (kVK_LeftArrow, function(NSLeftArrowFunctionKey)), (kVK_RightArrow, function(NSRightArrowFunctionKey)),
            (kVK_DownArrow, function(NSDownArrowFunctionKey)), (kVK_UpArrow, function(NSUpArrowFunctionKey)),
            (kVK_Home, function(NSHomeFunctionKey)), (kVK_End, function(NSEndFunctionKey)),
            (kVK_PageUp, function(NSPageUpFunctionKey)), (kVK_PageDown, function(NSPageDownFunctionKey)),
            (kVK_F1, function(NSF1FunctionKey)), (kVK_F2, function(NSF2FunctionKey)),
            (kVK_F3, function(NSF3FunctionKey)), (kVK_F4, function(NSF4FunctionKey)),
            (kVK_F5, function(NSF5FunctionKey)), (kVK_F6, function(NSF6FunctionKey)),
            (kVK_F7, function(NSF7FunctionKey)), (kVK_F8, function(NSF8FunctionKey)),
            (kVK_F9, function(NSF9FunctionKey)), (kVK_F10, function(NSF10FunctionKey)),
            (kVK_F11, function(NSF11FunctionKey)), (kVK_F12, function(NSF12FunctionKey)),
            (kVK_F13, function(NSF13FunctionKey)), (kVK_F14, function(NSF14FunctionKey)),
            (kVK_F15, function(NSF15FunctionKey)), (kVK_F16, function(NSF16FunctionKey)),
            (kVK_F17, function(NSF17FunctionKey)), (kVK_F18, function(NSF18FunctionKey)),
            (kVK_F19, function(NSF19FunctionKey)), (kVK_F20, function(NSF20FunctionKey)),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()

    /// Menu key equivalent for every key the recorder accepts; nil for anything else.
    var menuKeyEquivalent: String? { Self.menuCharacters[keyCode] }

    /// Carbon modifier flags mapped to AppKit.
    var menuModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        return mask
    }
}
```

`App/Sources/AppDelegate.swift` 整体替换为：

```swift
import AppKit
import GlimpseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var hotkeys: HotkeyController?
    private var statusItem: StatusItemController?
    // Created in applicationDidFinishLaunching (main thread). A `lazy var` initializer would run in a
    // nonisolated context and fail to compile, because CaptureSessionController is @MainActor.
    private var session: CaptureSessionController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        InterfaceAccent.current = settings.accentColor
        LoginItemService.applyDefault(settings: settings)
        session = CaptureSessionController(settings: settings)
        let statusItem = StatusItemController(onCapture: { [weak self] in self?.startCapture() },
                                              onSettings: { [weak self] in self?.showSettings() })
        self.statusItem = statusItem

        let hotkeys = HotkeyController(settings: settings, handlers: [
            .screenshot: { [weak self] in
                self?.statusItem?.performAfterMenuCloses { [weak self] in self?.startCapture() }
            },
            .ocr: { NSSound.beep() }, // text recognition arrives in Task 9
        ])
        hotkeys.onChange = { [weak self, weak hotkeys] in
            guard let hotkeys else { return }
            for action in HotkeyAction.allCases {
                self?.statusItem?.updateShortcut(hotkeys.activeCombo(for: action), for: action)
            }
        }
        self.hotkeys = hotkeys
        hotkeys.registerAll()
        settingsWindow = SettingsWindowController(model: SettingsModel(settings: settings, hotkeys: hotkeys))
    }

    // CaptureSessionController is @MainActor. applicationDidFinishLaunching gets main-actor isolation from
    // the NSApplicationDelegate requirement; these private helpers do not, so they are annotated here.
    // Class-level @MainActor would break the nonisolated top-level code in main.swift.
    @MainActor
    private func startCapture() {
        session?.start()
    }

    @MainActor
    private func showSettings() {
        settingsWindow?.show()
    }
}
```

（1）`project.yml`：把

```
        NSDownloadsFolderUsageDescription: Glimpse 需要把截图保存到「下载」文件夹。
```

替换为

```
        NSDownloadsFolderUsageDescription: Glimpse 需要把截图保存到「下载」文件夹。
        NSDesktopFolderUsageDescription: Glimpse 需要把截图保存到「桌面」文件夹。
        NSDocumentsFolderUsageDescription: Glimpse 需要把截图保存到「文稿」文件夹。
```

- [ ] **Step 2：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误、没有新增警告，最后一行输出 app 路径

Run: `cd Core && swift test`
Expected: `Test run with 170 tests in 26 suites passed`（本任务没有改 Core）

- [ ] **Step 3：手动检查（用户在真机上做）**

Run: `cd . && scripts/run.sh`（重新授予屏幕录制权限的方式同 P2：按快捷键 → 系统设置里打开 → 重启应用）。之后需要重启应用时用 `pkill -f Glimpse.app/; open build/Build/Products/Debug/Glimpse.app`，不重新编译，权限保留。

- 菜单栏菜单：「截图 ⇧⌘A」「设置… ⌘,」「退出 Glimpse ⌘Q」，分隔线位置对
- 点「设置…」：标题为「Glimpse 设置」的窗口出现在最前面并拿到键盘，同时 Dock 里出现 Glimpse 图标（通用图标）、⌘Tab 里也有它；关掉设置窗口后 Dock 图标消失；在 TextEdit 里打字时从菜单打开设置，再按 ⌘W 关掉：直接接着打字能进 TextEdit（键盘回到之前的应用）；切到别的应用把设置窗口挡住，用 ⌘Tab 或点 Dock 图标能切回来；外观同「系统设置」的分组表单；五组：快捷键、外观、保存、通用、关于；切换日夜间跟着变
- 菜单打开时按 ⌘, 也能打开；窗口里 ⌘W 关闭，再打开还是同一个窗口；窗口里 ⌘Q 退出；打开大写锁定后 ⌘W、⌘Q 照样有效
- 从 TextEdit 打开设置后切到 Safari，再用 ⌘Tab 切回设置窗口，⌘W 关掉：键盘回到 Safari（最近离开的应用）
- 「快捷键」组脚注是那句常驻提示：「按快捷键没反应时，可能被微信、QQ 等应用的截图快捷键占用，请在那边改掉，或在这里换一个」
- 截图快捷键显示「⇧⌘A」；点它变成「请按快捷键…」，按住 ⌃⌥ 时显示「⌃⌥」；按 ⌃⌥S：按钮显示「⌃⌥S」，菜单里「截图」旁也变成 ⌃⌥S；⌃⌥S 能开始截图，⇧⌘A 不再触发
- 录制时按 ⇧⌘A：被录下来（不会开始截图）
- 录制时按 A（不带修饰键）：红字「快捷键需要包含 ⌘、⌃ 或 ⌥」，原快捷键不变；按 F5：录成「F5」
- 录制时按 ⌘Q、⌘W、⌘C、⌘Space、⇧⌘Z、⌃Space、⌃⌥Space：红字「这是系统常用的快捷键（如拷贝、粘贴、退出），请换一个」，应用没有退出、窗口没有关；按住 ⌘W 不放：窗口不关、不连续响提示音；按 ⌥E：红字「只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃」；按 ⌘⌫：录成「⌘⌫」；按 ⌥F5：录成「⌥F5」；按 ⌃⌥F1：录成「⌃⌥F1」，菜单里「截图」旁显示 ⌃⌥F1（F 键也能显示）；最后改回 ⇧⌘A
- 录制时按 Esc：取消，原快捷键不变；按 Delete：清空，按钮显示「点击录制」，菜单里「截图」旁不再显示快捷键，按原快捷键无反应；点 ⓧ 同样清空；最后改回 ⇧⌘A
- 录制中点表单空白处、点另一行的文字、点 ⓧ、切到别的应用、关掉窗口：都结束录制（按钮回到原组合），⇧⌘A 照常截图；某个快捷键有「没有注册成功」红字时，点它再点别处取消，红字重新出现；切到别的应用再回来，红字还在
- 识别文字快捷键默认显示「点击录制」；录 ⇧⌘A：红字「已用作另一个快捷键，请换一个」；录 ⌃⌥O：成功；按 ⌃⌥O 只响一声（批次 C 接入）
- 如果装了 Alfred / Raycast 这类注册全局快捷键的应用：录它的快捷键（如 ⌥Space），红字「「⌥Space」已被其他程序占用，请换一个」，原快捷键继续有效。没有这类应用可跳过（微信的 ⇧⌘A 这种情况 Carbon 发现不了，所以才有常驻提示）
- 退出再打开应用：两个快捷键都还在
- 界面强调色：一排色点，第一个彩虹色点（跟随系统）中间有白点；悬停显示名称；点「紫色」后截图：选区边框、手柄、选中的工具按钮底色、✓ 图标、二级栏选中色块的外圈、放大镜的「+」十字线都是紫色；标注颜色（红橙黄绿蓝黑）不变；夜间外观下紫色更亮一些。点回「跟随系统」，再到「系统设置 → 外观」换强调色，下次截图跟着变
- 保存目录：显示「下载」和文件夹图标，悬停显示完整路径；「更改…」的选择面板从设置窗口标题栏下滑出（sheet），不是单独的窗口；选「桌面」：显示「桌面」；截图按 ⌘S：第一次保存到桌面时系统可能询问是否允许访问「桌面」文件夹，说明文字是「Glimpse 需要把截图保存到「桌面」文件夹。」，点允许后文件出现在桌面，HUD「已保存到「桌面」」；最后改回「下载」
- 开机自动启动：开发版（Debug）不会自己打开它，开关默认是关的，「系统设置 → 通用 → 登录项」里没有 Glimpse；手动打开 → 列表里出现；再关掉 → 消失。**测完务必关掉**，免得 `build/` 下的开发版留在登录项里。若开关失败：开关回到原状、下面红字说明原因（「需要批准」时还有「打开登录项设置」按钮）；连续失败两次开关也都会弹回关闭。默认开启和重启电脑的验证在 Task 12 用 /Applications 里的 Release 版做
- 关于：「Glimpse · 瞥」「版本 0.1.0（1）」和一行说明
- VoiceOver（可选）：录制按钮读「快捷键 ⇧⌘A」，色点读颜色名

- [ ] **Step 4：停下，不 commit**

**批次 A 检查点：** 用户按 Task 4 的手动检查确认设置页可用，再进入批次 B。

---

## 批次 B：引导窗口与权限流程

### Task 5：引导窗口的状态（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/Permission/PermissionFlow.swift`
- Test: `Core/Tests/GlimpseCoreTests/PermissionFlowTests.swift`

§3.8 的第 1–3 步写成一个小状态机（实施前说明第 12 条）：每秒轮询 `poll(granted:)`；Glimpse 重新变成活跃应用时 `appDidBecomeActive(granted:)`；「去授权」打开过系统设置（`didRequest(openedSystemSettings: true)`）且回来仍未授权 → `.needsRestart`（明显的重启提示）；第一次点只弹系统询问框（传 false）→ `.restartHint`（常驻弱提示，实施前说明第 12 条）；截图被 ScreenCaptureKit 拒绝而预检说有权限（`captureWasRefused()`）→ `.needsRestart`，且之后轮询和回到活跃都不再转成 `.granted`（预检说有权限不代表能截图，实施前说明第 11、14 条）。

- [ ] **Step 1：写失败的测试**

新建 `Core/Tests/GlimpseCoreTests/PermissionFlowTests.swift`：

```swift
import Testing
@testable import GlimpseCore

struct PermissionFlowTests {
    @Test func startsAskingForTheGrant() {
        #expect(PermissionFlow().step == .needsGrant)
    }

    @Test func aGrantSeenByThePollClosesTheWindow() {
        var flow = PermissionFlow()
        flow.poll(granted: false)
        #expect(flow.step == .needsGrant)
        flow.poll(granted: true)
        #expect(flow.step == .granted)
    }

    @Test func backFromSystemSettingsWithoutTheGrantOffersARestart() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: true)
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsRestart)
        flow.poll(granted: false) // the poll keeps the restart button
        #expect(flow.step == .needsRestart)
    }

    @Test func theFirstSystemPromptOnlyGetsTheQuietHint() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: false) // only the system's prompt appeared
        #expect(flow.step == .restartHint)
        flow.appDidBecomeActive(granted: false) // declined, or opened System Settings from the prompt
        #expect(flow.step == .restartHint)
        flow.didRequest(openedSystemSettings: true) // the second click opens System Settings
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsRestart)
    }

    @Test func becomingActiveBeforeAskingChangesNothing() {
        var flow = PermissionFlow()
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsGrant)
    }

    @Test func backFromSystemSettingsWithTheGrantCloses() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: true)
        flow.appDidBecomeActive(granted: true)
        #expect(flow.step == .granted)
    }

    @Test func aRefusedCaptureOffersARestartThatTheGrantDoesNotClose() {
        var flow = PermissionFlow()
        flow.captureWasRefused() // the preflight says granted, ScreenCaptureKit still says no
        #expect(flow.step == .needsRestart)
        #expect(flow.isCaptureRefused)
        flow.poll(granted: true)
        #expect(flow.step == .needsRestart)
        flow.appDidBecomeActive(granted: true)
        #expect(flow.step == .needsRestart)
    }

    @Test func aRefusedCaptureReplacesTheQuietHint() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: false)
        flow.captureWasRefused()
        #expect(flow.step == .needsRestart)
        flow.didRequest(openedSystemSettings: false) // 「去授权」 again does not bring the quiet hint back
        #expect(flow.step == .needsRestart)
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter PermissionFlowTests`
Expected: 编译失败，`cannot find 'PermissionFlow' in scope`

- [ ] **Step 3：实现**

新建 `Core/Sources/GlimpseCore/Permission/PermissionFlow.swift`：

```swift
/// The onboarding window's state (design doc §3.8). Screen Recording often only takes effect after a
/// restart, so after the user went to System Settings and came back without it, the window offers one.
public struct PermissionFlow: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Show 「去授权」.
        case needsGrant
        /// 「去授权」 only brought up the system's own prompt (its 「打开系统设置」 button may have opened System
        /// Settings without us knowing): show 「去授权」 plus a quiet hint with a secondary restart button.
        case restartHint
        /// Show 「去授权」 and 「重新启动 Glimpse」.
        case needsRestart
        /// Close the window; capturing works.
        case granted
    }

    public private(set) var step: Step = .needsGrant
    /// ScreenCaptureKit refused a capture although the preflight says granted (design doc §6). The preflight
    /// cannot tell when this is over, so the window stays (offering the restart) until the user closes it.
    public private(set) var isCaptureRefused = false
    /// System Settings was opened from this window. Only then can "back without the grant" mean the grant
    /// needs a restart: declining the system's first prompt is not a visit to System Settings.
    private var openedSystemSettings = false

    public init() {}

    /// 「去授权」 clicked. `openedSystemSettings` is false the very first time, when only the system's own
    /// prompt appears (see PermissionService.request).
    public mutating func didRequest(openedSystemSettings opened: Bool) {
        if opened {
            openedSystemSettings = true
        } else if step == .needsGrant {
            step = .restartHint
        }
    }

    /// A capture was refused while the preflight says granted: offer the restart at once.
    public mutating func captureWasRefused() {
        isCaptureRefused = true
        step = .needsRestart
    }

    /// The once-a-second check while the window is open.
    public mutating func poll(granted: Bool) {
        if granted, !isCaptureRefused { step = .granted }
    }

    /// Glimpse became the active app again, i.e. the user is back from System Settings (§3.8 step 3).
    public mutating func appDidBecomeActive(granted: Bool) {
        if granted {
            if !isCaptureRefused { step = .granted }
        } else if openedSystemSettings {
            step = .needsRestart
        }
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test`
Expected: `Test run with 178 tests in 27 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 6：引导窗口、权限检查、菜单栏标记

**Files:**
- Modify: `App/Sources/Material/MaterialView.swift`
- Delete: `App/Sources/Services/ScreenRecordingPermission.swift`
- Create: `App/Sources/Services/PermissionService.swift`、`App/Sources/Onboarding/OnboardingWindowController.swift`
- Modify: `App/Sources/Overlay/CaptureSessionController.swift`、`App/Sources/MenuBar/StatusItemController.swift`、`App/Sources/AppDelegate.swift`
- Modify: `App/Sources/Services/LoginItemService.swift`、`App/Sources/Settings/SettingsModel.swift`

- `MaterialView` 加 `blendsBehindWindow`（实施前说明第 22 条），只影响 macOS 14 / 15 的毛玻璃。
- `PermissionService` 取代 `ScreenRecordingPermission`：`request()` 保留 P1 的「第一次只让系统询问」（第 10 条）并返回这次是否打开了系统设置（交给 `PermissionFlow`），新增 `isPermissionDenial(_:)`（ScreenCaptureKit 的 `userDeclined`）、`captureRefused`（被拒后到下一次截图成功之间为真，第 14 条）、`Problem`（引导窗口为什么打开：`.missing` / `.captureRefused`）和 `relaunch()`（最多等 10 秒，起不来返回 false，第 13 条）。
- `OnboardingWindowController`：引导窗口（第 11 条），`show(reason:)`。内容用 `NSStackView` 自动布局，窗口按内容大小调整（「重新启动」那一行出现时向下长，顶边不动）；只在创建时居中；`render()` 只在要显示的内容变了时才改界面（轮询每秒一次）。
- `CaptureSessionController`：没权限时调用 `onPermissionMissing(.missing)`，被 ScreenCaptureKit 拒绝时记下 `captureRefused` 并调用 `onPermissionMissing(.captureRefused)`，不再自己去申请；截图前经 `onCaptureWillStart` 让引导窗口先隐藏（和 HUD 一样等一轮主队列，免得被截进冻结画面），截图成功时立即清掉被拒标记并通知 `onCaptureSucceeded`（刷新菜单栏标记），等覆盖层关掉、会话 `close()` 时才通知 `onCaptureFinished(true)`（引导窗口就此关闭、键盘交还之前的应用；覆盖层还在时交还会让不激活的覆盖层失去键盘。屏幕布局变化而丢弃结果的分支同样在 `close()` 之后）；其他原因失败时 `onCaptureFinished(false)`（引导窗口回来）；再次被拒则照常以截图被拒模式打开。
- `StatusItemController`：标成 `@MainActor`；`setNeedsPermission(_:)`，两种图标只建一次，状态没变时不换图。
- `AppDelegate`：启动时没权限就打开引导窗口；刷新菜单栏标记（第 14 条）。
- `LoginItemService.Display`：「开机自动启动」显示什么（开关、红字、「打开登录项设置」），设置页和引导窗口共用（第 11 条）。

- [ ] **Step 1：MaterialView 支持独立窗口的毛玻璃**

在 `App/Sources/Material/MaterialView.swift` 里按顺序做下面 3 处替换（每段原文在文件里只出现一次）：

（1）`App/Sources/Material/MaterialView.swift`：把

```swift
    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
```

替换为

```swift
    /// `blendsBehindWindow`: for a window of its own (onboarding, OCR result), whose glass shows what is
    /// behind the window. The overlay's chrome blurs the frozen screen inside its window instead.
    init(cornerRadius: CGFloat, blendsBehindWindow: Bool = false) {
        self.cornerRadius = cornerRadius
```

（2）`App/Sources/Material/MaterialView.swift`：把

```swift
            emulated = EmulatedGlass(contentView: contentView)
```

替换为

```swift
            emulated = EmulatedGlass(contentView: contentView, blendsBehindWindow: blendsBehindWindow)
```

（3）`App/Sources/Material/MaterialView.swift`：把

```swift
    init(contentView: NSView) {
        effect.material = .popover          // adapts to light / dark; .hudWindow is always dark
        effect.blendingMode = .withinWindow // blur the frozen screen in this window, not what is behind it
```

替换为

```swift
    init(contentView: NSView, blendsBehindWindow: Bool) {
        effect.material = .popover          // adapts to light / dark; .hudWindow is always dark
        // Overlay chrome blurs the frozen screen in its own window; a window of its own blurs what is behind it.
        effect.blendingMode = blendsBehindWindow ? .behindWindow : .withinWindow
```

- [ ] **Step 2：PermissionService 与引导窗口**

删除 `App/Sources/Services/ScreenRecordingPermission.swift`（Run: `rm App/Sources/Services/ScreenRecordingPermission.swift`）。

新建 `App/Sources/Services/PermissionService.swift`：

```swift
import AppKit
import ScreenCaptureKit

/// Screen Recording permission (design doc §3.8, §5.1): check it, ask for it, and restart Glimpse,
/// which macOS often needs before a fresh grant takes effect.
enum PermissionService {
    private static let didRequestKey = "didRequestScreenRecording"

    /// Why the onboarding window opens.
    enum Problem {
        /// The preflight says the permission is missing (never granted, or revoked).
        case missing
        /// The preflight says granted, but ScreenCaptureKit refused the capture (design doc §6).
        case captureRefused
    }

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// ScreenCaptureKit refused the last capture although `isGranted` said yes (design doc §6). Set when it
    /// refuses, cleared by the next capture that works; the menu bar icon keeps its mark meanwhile.
    @MainActor static var captureRefused = false

    /// 「去授权」: asks the system first, which puts Glimpse in the Screen Recording list (an app that never
    /// asked is missing there, and the user would have to add it with 「+」). The very first time the system
    /// shows its own prompt, which has its own 「打开系统设置」 button, so System Settings is opened only from the
    /// second time on: the prompt and the Settings window never stack. Returns whether System Settings was opened.
    @discardableResult
    static func request() -> Bool {
        let defaults = UserDefaults.standard
        let requestedBefore = defaults.bool(forKey: didRequestKey)
        defaults.set(true, forKey: didRequestKey)
        _ = CGRequestScreenCaptureAccess()
        if requestedBefore { openSystemSettings() }
        return requestedBefore
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// ScreenCaptureKit refused because the permission is missing (revoked, or denied when macOS 15+
    /// asked again), even though the preflight said yes.
    static func isPermissionDenial(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    /// Starts a new instance once this one has exited, then quits (design doc §3.8 step 3). A shell waits
    /// for this process to exit, so the new instance can register the same global shortcut (held until then),
    /// plus a moment for the system to finish tearing it down (status item, hotkey). If this process is still
    /// there after 10 seconds (the quit was cancelled), the shell gives up instead of opening a second instance.
    /// Returns false when the shell could not be started; Glimpse then keeps running.
    @MainActor
    static func relaunch() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // $0 is the app, $1 this process: wait up to 10 s (100 × 0.1 s) for it to exit, then open the app again.
        let script = "i=0; while /bin/kill -0 \"$1\" 2>/dev/null; do i=$((i + 1)); "
            + "[ \"$i\" -gt 100 ] && exit 1; /bin/sleep 0.1; done; /bin/sleep 0.3; /usr/bin/open \"$0\""
        process.arguments = ["-c", script, Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try process.run()
        } catch {
            NSLog("Glimpse: could not restart: \(error)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
```

新建 `App/Sources/Onboarding/OnboardingWindowController.swift`：

```swift
import AppKit
import GlimpseCore

/// The first-launch window (design doc §3.8): asks for Screen Recording, offers a restart when the grant
/// has not taken effect, and holds the 「开机自动启动」 checkbox. Shown at launch and whenever a capture
/// finds the permission missing; closes itself once the permission is there. When ScreenCaptureKit refused
/// a capture although the permission looks granted, it offers the restart and stays until the user closes it.
@MainActor
final class OnboardingWindowController {
    /// The permission arrived: the status item drops its warning mark.
    var onGranted: (() -> Void)?

    private let settings: SettingsStore
    private var window: OnboardingWindow?
    private var content: OnboardingView?
    private var flow = PermissionFlow()
    /// What the restart row shows now; render() only touches the view when this changes.
    private var renderedOffer: OnboardingView.RestartOffer?
    private var loginItem = LoginItemService.Display()
    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// Ordered out so a capture does not freeze it into the screenshot; see `captureFinished(succeeded:)`.
    private var isHiddenForCapture = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(reason: PermissionService.Problem) {
        switch reason {
        case .missing:
            // Kept while Glimpse runs, so closing the window does not forget that 「去授权」 was clicked;
            // started over once a grant was seen (it may have been revoked since), and when the preflight now
            // plainly says missing after a refused capture.
            if flow.step == .granted || flow.isCaptureRefused { flow = PermissionFlow() }
        case .captureRefused:
            flow.captureWasRefused()
        }
        isHiddenForCapture = false
        let isNew = window == nil
        if isNew {
            let view = OnboardingView(shortcut: settings.screenshotHotkey)
            view.onRequest = { [weak self] in self?.request() }
            view.onRestart = { [weak self] in self?.restart() }
            view.onClose = { [weak self] in self?.close() }
            view.onLaunchAtLoginChange = { [weak self] enabled in
                guard let self else { return }
                self.loginItem.set(enabled)
                self.showLoginItem()
            }
            view.onOpenLoginItems = { LoginItemService.openSystemSettings() }
            content = view
            window = OnboardingWindow(content: view)
            startWatching()
        }
        loginItem.reload()
        showLoginItem()
        render(force: true)
        guard let window else { return }
        if isNew { window.center() } // a window the user moved stays where it is
        DockPresence.bringToFront(window)
    }

    /// A capture is about to start (e.g. a retry after a refused capture): the window steps aside.
    /// Returns whether it was on screen.
    func hideForCapture() -> Bool {
        guard let window, window.isVisible else { return false }
        window.orderOut(nil)
        isHiddenForCapture = true
        return true
    }

    /// The capture the window stepped aside for is over. It worked (called once its overlay is gone, so
    /// handing the keyboard back cannot take it from the overlay): the permission is there, so the window
    /// closes for good. It failed for another reason: the window comes back. (Refused again: the
    /// session calls `show(reason: .captureRefused)` instead.)
    func captureFinished(succeeded: Bool) {
        guard isHiddenForCapture, let window else { return }
        isHiddenForCapture = false
        if succeeded {
            flow = PermissionFlow()
            close()
            onGranted?()
        } else {
            DockPresence.bringToFront(window)
        }
    }

    private func request() {
        flow.didRequest(openedSystemSettings: PermissionService.request())
        render()
    }

    private func restart() {
        guard !PermissionService.relaunch() else { return }
        NSSound.beep()
        content?.showRestartFailed()
        window?.fitContent()
    }

    private func showLoginItem() {
        content?.showLoginItem(loginItem)
        window?.fitContent()
    }

    /// Polls once a second while open, and checks again whenever Glimpse becomes active (back from System
    /// Settings, where the login item may have changed too).
    private func startWatching() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.flow.poll(granted: PermissionService.isGranted)
                self.render()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loginItem.reload()
                self.showLoginItem()
                self.flow.appDidBecomeActive(granted: PermissionService.isGranted)
                self.render()
            }
        }
    }

    /// Shows the flow's step. Only when it changed (the poll runs every second), or when `force`d.
    private func render(force: Bool = false) {
        let offer: OnboardingView.RestartOffer?
        switch flow.step {
        case .needsGrant: offer = nil
        case .restartHint: offer = .quiet
        case .needsRestart: offer = flow.isCaptureRefused ? .captureRefused : .prominent
        case .granted:
            close()
            onGranted?()
            return
        }
        guard force || offer != renderedOffer else { return }
        renderedOffer = offer
        content?.showRestart(offer)
        window?.fitContent()
    }

    private func close() {
        isHiddenForCapture = false
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let window {
            window.orderOut(nil)
            DockPresence.remove(window)
        }
        window = nil
        content = nil
    }
}

/// Borderless and transparent, so the glass is the window; dragged by its background.
private final class OnboardingWindow: NSWindow {
    private let material = MaterialView(cornerRadius: 12, blendsBehindWindow: true)
    private let content: OnboardingView

    init(content: OnboardingView) {
        self.content = content
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        material.contentView.addSubview(content)
        contentView = material
        fitContent()
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes, like the ✕.
    override func cancelOperation(_ sender: Any?) {
        content.onClose?()
    }

    /// Sizes the window to the content (the restart row comes and goes), keeping the top edge in place.
    func fitContent() {
        let size = content.fittingSize
        let top = frame.maxY
        content.frame = CGRect(origin: .zero, size: size)
        material.frame = CGRect(origin: .zero, size: size)
        let origin = frame.isEmpty ? frame.origin : CGPoint(x: frame.minX, y: top - size.height)
        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

/// The window's content, top to bottom: ✕, icon, title, explanation, 「去授权」, the restart row (when
/// needed), the shortcut hint, 「开机自动启动」 and its error row.
private final class OnboardingView: NSView {
    var onRequest: (() -> Void)?
    var onRestart: (() -> Void)?
    var onClose: (() -> Void)?
    var onLaunchAtLoginChange: ((Bool) -> Void)?
    var onOpenLoginItems: (() -> Void)?

    private static let width: CGFloat = 400
    private static let inset: CGFloat = 24
    private static let textWidth = width - inset * 2

    private let stack = NSStackView()
    private let request = NSButton(title: "去授权", target: nil, action: nil)
    private let restartRow = NSStackView()
    private let restartHint = NSTextField(wrappingLabelWithString: "")
    private let restart = NSButton(title: "重新启动 Glimpse", target: nil, action: nil)

    /// How the window offers a restart (PermissionFlow): a quiet hint after the system's prompt, a clear one
    /// after the user came back from System Settings without the grant taking effect, and its own sentence
    /// when ScreenCaptureKit refused a capture although the permission looks granted.
    enum RestartOffer {
        case quiet, prominent, captureRefused
    }
    private let launchAtLogin = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let loginItemRow = NSStackView()
    private let loginItemError = NSTextField(wrappingLabelWithString: "")
    private let openLoginItems = NSButton(title: "打开登录项设置", target: nil, action: nil)

    init(shortcut: KeyCombo?) {
        super.init(frame: .zero)
        let textWidth = Self.textWidth

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .regular))
        icon.contentTintColor = .glimpseAccent

        let title = Self.label("允许 Glimpse 录制屏幕", font: .systemFont(ofSize: 17, weight: .semibold), width: textWidth)
        let body = Self.label("截图需要「屏幕录制」权限。点「去授权」，在系统设置里打开 Glimpse 的开关。"
                              + "画面只在本机处理，不会上传。", font: .systemFont(ofSize: 13), width: textWidth)
        body.textColor = .materialSecondaryText

        request.target = self
        request.action = #selector(requestClicked)
        request.bezelStyle = .push
        request.keyEquivalent = "\r"
        request.bezelColor = .glimpseAccent

        restartHint.preferredMaxLayoutWidth = textWidth - 150
        restart.target = self
        restart.action = #selector(restartClicked)
        restart.bezelStyle = .push
        restartRow.orientation = .horizontal
        restartRow.alignment = .centerY
        restartRow.spacing = 12
        restartRow.addArrangedSubview(restartHint)
        restartRow.addArrangedSubview(restart)
        restartRow.isHidden = true

        let hotkeyText = shortcut.map { "截图快捷键是 \($0.displayString)。" } ?? "截图快捷键还没有设置。"
        let hint = Self.label(hotkeyText + "按了没反应时，可能被微信、QQ 等应用的截图快捷键占用，"
                              + "请在那边改掉，或在 Glimpse 的「设置」里换一个。",
                              font: .systemFont(ofSize: 12), width: textWidth)
        hint.textColor = .materialSecondaryText

        launchAtLogin.target = self
        launchAtLogin.action = #selector(launchAtLoginClicked)
        loginItemError.font = .systemFont(ofSize: 12)
        loginItemError.textColor = .systemRed
        openLoginItems.target = self
        openLoginItems.action = #selector(openLoginItemsClicked)
        openLoginItems.bezelStyle = .push
        openLoginItems.controlSize = .small
        loginItemRow.orientation = .horizontal
        loginItemRow.alignment = .centerY
        loginItemRow.spacing = 8
        loginItemRow.addArrangedSubview(loginItemError)
        loginItemRow.addArrangedSubview(openLoginItems)
        loginItemRow.isHidden = true

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")!,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = .materialSecondaryText
        close.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        for view in [icon, title, body, request, restartRow, hint, launchAtLogin, loginItemRow] as [NSView] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(4, after: launchAtLogin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(close)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func showRestart(_ offer: RestartOffer?) {
        restartRow.isHidden = offer == nil
        // Return presses the button the window is asking for: 「重新启动」 once a restart is what is needed.
        let restartIsNeeded = offer == .prominent || offer == .captureRefused
        request.keyEquivalent = restartIsNeeded ? "" : "\r"
        restart.keyEquivalent = restartIsNeeded ? "\r" : ""
        switch offer {
        case nil:
            break
        case .quiet:
            showRestartHint("打开开关后若没有生效，请重新启动 Glimpse", size: 11, color: .materialTertiaryText)
            restart.controlSize = .small
        case .prominent:
            showRestartHint("已经打开了开关？需要重新启动 Glimpse 才能生效。", size: 12, color: .materialSecondaryText)
            restart.controlSize = .regular
        case .captureRefused:
            showRestartHint("系统设置里已允许，但截图仍被拒绝。请重新启动 Glimpse；若仍不行，在系统设置里关掉再打开 Glimpse 的开关。",
                            size: 12, color: .materialSecondaryText)
            restart.controlSize = .regular
        }
    }

    /// The restart could not be started (PermissionService.relaunch); stays until the offer changes.
    func showRestartFailed() {
        restartRow.isHidden = false
        showRestartHint("无法自动重启，请手动退出后重新打开", size: 12, color: .systemRed)
    }

    private func showRestartHint(_ text: String, size: CGFloat, color: NSColor) {
        restartHint.stringValue = text
        restartHint.font = .systemFont(ofSize: size)
        restartHint.textColor = color
    }

    /// The checkbox shows the system's state; a failure shows why (design doc §6), with 「打开登录项设置」 when
    /// Glimpse was switched off in System Settings → General → Login Items (as on the settings page).
    func showLoginItem(_ display: LoginItemService.Display) {
        launchAtLogin.state = display.isOn ? .on : .off
        loginItemError.stringValue = display.error ?? ""
        openLoginItems.isHidden = !display.needsApproval
        loginItemError.preferredMaxLayoutWidth = display.needsApproval ? Self.textWidth - 130 : Self.textWidth
        loginItemRow.isHidden = display.error == nil
    }

    private static func label(_ text: String, font: NSFont, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .materialText
        label.preferredMaxLayoutWidth = width
        return label
    }

    @objc private func requestClicked() { onRequest?() }
    @objc private func restartClicked() { onRestart?() }
    @objc private func closeClicked() { onClose?() }
    @objc private func launchAtLoginClicked() { onLaunchAtLoginChange?(launchAtLogin.state == .on) }
    @objc private func openLoginItemsClicked() { onOpenLoginItems?() }
}
```

- [ ] **Step 3：接到会话、菜单栏、AppDelegate，登录项的显示逻辑共用**

`LoginItemService.Display` 是「开机自动启动」该显示什么（开关、红字、要不要「打开登录项设置」按钮）的唯一来源：设置页的 `SettingsModel` 改成用它（页面代码不动），引导窗口也用它。

按顺序做下面 18 处替换（每段原文在各自文件里只出现一次）：

（1）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    init(settings: SettingsStore) {
        self.settings = settings
    }
```

替换为

```swift
    /// The Screen Recording permission is missing (never granted, or revoked), or ScreenCaptureKit refused
    /// the capture anyway: the app delegate opens the onboarding window instead of an overlay (design doc
    /// §3.8 step 4, §6).
    var onPermissionMissing: ((PermissionService.Problem) -> Void)?
    /// Called before capturing; returns whether it hid one of Glimpse's windows (the onboarding window),
    /// which must not end up in the frozen screen.
    var onCaptureWillStart: (() -> Bool)?
    /// A capture worked (the permission is there): the app delegate refreshes the menu bar mark at once.
    var onCaptureSucceeded: (() -> Void)?
    /// The session is over: true once the overlay of a capture that worked is gone, false right after a
    /// capture that failed for another reason than the permission. The app delegate closes, or shows
    /// again, the onboarding window it hid; closing it hands the keyboard back to the previous app, which
    /// must not happen while the overlay is up.
    var onCaptureFinished: ((Bool) -> Void)?
    /// Set when the capture worked; close() then reports `onCaptureFinished(true)`.
    private var captureSucceeded = false

    init(settings: SettingsStore) {
        self.settings = settings
    }
```

（2）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.requestOrOpenSettings()
            return
        }
```

替换为

```swift
        // Only the preflight is checked: after a refused capture the user can still try again.
        guard PermissionService.isGranted else {
            onPermissionMissing?(.missing)
            return
        }
```

（3）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        // Before capturing: a HUD still on screen would be in the screenshot.
        let hudWasVisible = hud.dismiss()
        observeScreenChanges()
        Task { @MainActor in
            if hudWasVisible {
```

替换为

```swift
        // Before capturing: a HUD or the onboarding window still on screen would be in the screenshot.
        let hudWasVisible = hud.dismiss()
        let windowWasHidden = onCaptureWillStart?() ?? false
        observeScreenChanges()
        Task { @MainActor in
            if hudWasVisible || windowWasHidden {
```

（4）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
                let result = try await capture.captureAll()
```

替换为

```swift
                let result = try await capture.captureAll()
                PermissionService.captureRefused = false
                captureSucceeded = true
                onCaptureSucceeded?()
```

（5）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        mouseScreenView = nil
        // The windows are ordered out above.
```

替换为

```swift
        mouseScreenView = nil
        if captureSucceeded {
            captureSucceeded = false
            onCaptureFinished?(true)
        }
        // The windows are ordered out above.
```

（6）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
            } catch {
                NSLog("Glimpse: capture failed: \(error)")
                close()
```

替换为

```swift
            } catch where PermissionService.isPermissionDenial(error) {
                NSLog("Glimpse: capture refused, screen recording permission is missing: \(error)")
                PermissionService.captureRefused = true
                close()
                onPermissionMissing?(.captureRefused)
            } catch {
                NSLog("Glimpse: capture failed: \(error)")
                close()
                onCaptureFinished?(false)
```

（7）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
final class StatusItemController: NSObject, NSMenuDelegate {
```

替换为

```swift
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
```

（8）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
    private var isMenuOpen = false
```

替换为

```swift
    private var isMenuOpen = false
    private var needsPermission = false

    private static let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glimpse")
    /// `viewfinder.trianglebadge.exclamationmark` is missing on older systems.
    private static let warningIcon = NSImage(systemSymbolName: "viewfinder.trianglebadge.exclamationmark",
                                             accessibilityDescription: "Glimpse：需要屏幕录制权限")
        ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Glimpse：需要屏幕录制权限")
```

（9）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glimpse")
```

替换为

```swift
        item.button?.image = Self.icon
```

（10）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
    /// Closes the status menu first if it is open, then runs `action` once it has faded out.
```

替换为

```swift
    /// Marks the icon while the Screen Recording permission is missing (design doc §6). Checked on every
    /// activation, so the image is only swapped when the state changes.
    func setNeedsPermission(_ needed: Bool) {
        guard needed != needsPermission else { return }
        needsPermission = needed
        item.button?.image = needed ? Self.warningIcon : Self.icon
    }

    /// Closes the status menu first if it is open, then runs `action` once it has faded out.
```

（11）`App/Sources/AppDelegate.swift`：把

```swift
    private var settingsWindow: SettingsWindowController?
```

替换为

```swift
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var activationObserver: NSObjectProtocol?
```

（12）`App/Sources/AppDelegate.swift`：把

```swift
        settingsWindow = SettingsWindowController(model: SettingsModel(settings: settings, hotkeys: hotkeys))
    }
```

替换为

```swift
        settingsWindow = SettingsWindowController(model: SettingsModel(settings: settings, hotkeys: hotkeys))

        let onboarding = OnboardingWindowController(settings: settings)
        onboarding.onGranted = { [weak self] in self?.refreshPermissionMark() }
        self.onboarding = onboarding
        session?.onPermissionMissing = { [weak self] problem in self?.showOnboarding(problem) }
        session?.onCaptureWillStart = { [weak onboarding] in onboarding?.hideForCapture() ?? false }
        session?.onCaptureSucceeded = { [weak self] in self?.refreshPermissionMark() }
        session?.onCaptureFinished = { [weak self] succeeded in self?.onboarding?.captureFinished(succeeded: succeeded) }
        // The permission can be granted or revoked in System Settings at any time; check on the way back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionMark() }
        }
        refreshPermissionMark()
        if !PermissionService.isGranted { onboarding.show(reason: .missing) } // first launch, or still not granted (§3.8)
    }
```

（13）`App/Sources/AppDelegate.swift`：把

```swift
    @MainActor
    private func showSettings() {
        settingsWindow?.show()
    }
```

替换为

```swift
    @MainActor
    private func showSettings() {
        settingsWindow?.show()
    }

    @MainActor
    private func showOnboarding(_ problem: PermissionService.Problem) {
        refreshPermissionMark()
        onboarding?.show(reason: problem)
    }

    /// Missing, or refused by ScreenCaptureKit since the last capture that worked (design doc §6).
    @MainActor
    private func refreshPermissionMark() {
        statusItem?.setNeedsPermission(!PermissionService.isGranted || PermissionService.captureRefused)
    }
```

（14）`App/Sources/Services/LoginItemService.swift`：把

```swift
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

替换为

```swift
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// What a 「开机自动启动」 control shows. Shared by the settings page and the onboarding window, so both
    /// read the system the same way.
    @MainActor
    struct Display {
        private(set) var isOn = false
        private(set) var error: String?
        /// The error is fixed in System Settings → Login Items; the control offers 「打开登录项设置」.
        private(set) var needsApproval = false
        /// The system's state when `error` was set: the error stays until that state changes.
        private var statusAtError: SMAppService.Status?

        /// Reads the system's state, also when Glimpse comes back from System Settings. Switched off in
        /// System Settings → Login Items shows the hint and its button right away; any other error stays until
        /// the system's state changes.
        mutating func reload() {
            let status = LoginItemService.status
            isOn = status == .enabled
            if status == .requiresApproval {
                error = Failure.requiresApproval.errorDescription
                needsApproval = true
                statusAtError = status
            } else if error != nil, needsApproval || status != statusAtError {
                error = nil
                needsApproval = false
                statusAtError = nil
            }
        }

        /// The user flipped the control. A failure puts it back and says why (design doc §6).
        mutating func set(_ enabled: Bool) {
            error = nil
            needsApproval = false
            do {
                try LoginItemService.setEnabled(enabled)
            } catch {
                self.error = error.localizedDescription
                needsApproval = (error as? Failure).map {
                    if case .requiresApproval = $0 { true } else { false }
                } ?? false
                statusAtError = LoginItemService.status
            }
            isOn = LoginItemService.isEnabled
        }

        /// For SwiftUI: the control follows the click and the old error goes, as a change of its own before
        /// `set(_:)`, so putting the control back is always a change the page sees, even when the same
        /// failure happens twice in a row.
        mutating func follow(_ enabled: Bool) {
            isOn = enabled
            error = nil
            needsApproval = false
        }
    }
}
```

（15）`App/Sources/Settings/SettingsModel.swift`：把

```swift
import Observation
import ServiceManagement
```

替换为

```swift
import Observation
```

（16）`App/Sources/Settings/SettingsModel.swift`：把

```swift
    private(set) var launchAtLogin = false
    private(set) var loginItemError: String?
    /// The error is fixed in System Settings → Login Items; the page offers a button for it.
    private(set) var loginItemNeedsApproval = false
    /// The system's state when `loginItemError` was set: the error stays until that state changes.
    @ObservationIgnored private var statusAtLoginItemError: SMAppService.Status?
```

替换为

```swift
    /// 「开机自动启动」: the switch, and the red line under it when it failed.
    private(set) var loginItem = LoginItemService.Display()
    var launchAtLogin: Bool { loginItem.isOn }
    var loginItemError: String? { loginItem.error }
    /// The error is fixed in System Settings → Login Items; the page offers a button for it.
    var loginItemNeedsApproval: Bool { loginItem.needsApproval }
```

（17）`App/Sources/Settings/SettingsModel.swift`：把

```swift
    /// The system's login item state, also when Glimpse comes back from System Settings. Switched off in
    /// System Settings → Login Items shows the hint and its button right away; any other error stays until
    /// the system's state changes.
    func reloadLoginItem() {
        let status = LoginItemService.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemError = LoginItemService.Failure.requiresApproval.errorDescription
            loginItemNeedsApproval = true
            statusAtLoginItemError = status
        } else if loginItemError != nil, loginItemNeedsApproval || status != statusAtLoginItemError {
            loginItemError = nil
            loginItemNeedsApproval = false
            statusAtLoginItemError = nil
        }
    }
```

替换为

```swift
    /// The system's login item state, also when Glimpse comes back from System Settings.
    func reloadLoginItem() {
        loginItem.reload()
    }
```

（18）`App/Sources/Settings/SettingsModel.swift`：把

```swift
        // Follow the switch first and clear the old error, so putting it back below is always a change the
        // page sees, even when the same failure happens twice in a row.
        launchAtLogin = enabled
        loginItemError = nil
        loginItemNeedsApproval = false
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            loginItemError = error.localizedDescription
            loginItemNeedsApproval = (error as? LoginItemService.Failure).map {
                if case .requiresApproval = $0 { true } else { false }
            } ?? false
            statusAtLoginItemError = LoginItemService.status
        }
        launchAtLogin = LoginItemService.isEnabled // a failure puts the switch back (design doc §6)
```

替换为

```swift
        loginItem.follow(enabled)
        loginItem.set(enabled) // a failure puts the switch back (design doc §6)
```

- [ ] **Step 4：编译**

Run: `cd . && grep -rn "ScreenRecordingPermission\|requestOrOpenSettings" App/Sources`
Expected: 没有输出

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误、没有新增警告，最后一行输出 app 路径

Run: `cd Core && swift test`
Expected: `Test run with 178 tests in 27 suites passed`

- [ ] **Step 5：手动检查（用户在真机上做）**

Run: `cd . && scripts/run.sh`。重新编译后屏幕录制权限已失效，正好走一遍引导流程。想从「从没申请过」开始测时，先执行 `tccutil reset ScreenCapture com.anglerdw.glimpse && defaults delete com.anglerdw.glimpse didRequestScreenRecording`。

- 启动：Dock 里出现 Glimpse 图标，屏幕中央出现玻璃引导窗口（macOS 26 液态玻璃；14 / 15 毛玻璃，能透出后面的桌面）：强调色的取景框图标、「允许 Glimpse 录制屏幕」、说明、「去授权」、快捷键提示（含微信 / QQ 那句）、「开机自动启动」勾选框（开发版默认不勾，第 8 条；勾上后测完记得取消）；引导窗口关闭后 Dock 图标消失
- 拖动：在 macOS 26 和 14 / 15（如有）上分别按住窗口背景（文字、空白处）拖动，窗口跟着走、玻璃不闪不错位；按钮和勾选框上按下不会拖动窗口。拖开后关掉再按 ⇧⌘A 打开：留在拖到的位置（只在第一次打开时居中）
- 回车：没有重启提示或只有小字弱提示时，回车 = 「去授权」；出现明显的重启提示（或截图被拒模式）时，回车 = 「重新启动 Glimpse」
- 菜单栏图标带警告标记
- 按 ⇧⌘A 或菜单「截图」：不出现覆盖层（不会黑屏），引导窗口回到最前面
- 点「去授权」：从没申请过时只出现系统的询问框（不会同时打开系统设置）；之后再点会直接打开「系统设置 → 隐私与安全性 → 屏幕录制」，列表里有 Glimpse
- 在系统设置里打开 Glimpse 的开关。macOS 可能自己提示「退出并重新打开」：选它的话，重启后不再出现引导窗口，菜单栏标记消失，⇧⌘A 正常截图。选「稍后」再点回引导窗口：如果 1 秒内检测到授权，窗口自动关闭、标记消失；检测不到时窗口里出现「已经打开了开关？需要重新启动 Glimpse 才能生效。」和「重新启动 Glimpse」，点它：菜单栏图标消失后约 1 秒内重新出现，不再有引导窗口，⇧⌘A 正常截图（快捷键没有因为新旧实例冲突而失效：菜单里「截图」旁仍显示 ⇧⌘A）
- 没点过「去授权」时切到别的应用再切回来：不出现重启提示
- 从没申请过时第一次点「去授权」（先执行上面的 `tccutil reset` 和 `defaults delete`）：只弹系统询问框，引导窗口里立刻多一行小字「打开开关后若没有生效，请重新启动 Glimpse」和小号「重新启动 Glimpse」按钮（实施前说明第 12 条）。分两条路各走一次：(a) 在询问框里点「拒绝」→ 回到引导窗口，仍是这行小字；(b) 在询问框里点「打开系统设置」→ 在系统设置里打开开关 → 点回引导窗口：1 秒内检测到授权就自动关闭；检测不到时点那个小号「重新启动 Glimpse」，重启后不再出现引导窗口
- 第二次及以后点「去授权」（直接打开系统设置）后回来仍未授权：小字换成明显的「已经打开了开关？需要重新启动 Glimpse 才能生效。」和常规按钮
- 关掉引导窗口再按 ⇧⌘A 打开：如果之前打开过系统设置，回到 Glimpse 时「重新启动」那一行仍会出现
- ✕ 和 Esc 都能关闭引导窗口；关闭后按 ⇧⌘A 再次打开
- 引导窗口没有主菜单，⌘W / ⌘Q 不起作用（已接受），用 Esc 或 ✕ 关闭
- 从菜单栏点「截图」时（延迟 0.25 秒后调用），系统可能拒绝把 Glimpse 激活；窗口仍会显示在最前并能直接点击、输入，确认这一点即可
- 勾掉「开机自动启动」：「系统设置 → 通用 → 登录项」里 Glimpse 消失；再勾上出现；失败时勾选框回到原状并显示红字原因
- 勾上「开机自动启动」后，在「系统设置 → 通用 → 登录项」里关掉 Glimpse，再点回引导窗口：勾选框变成未勾，下方红字「需要在「系统设置 → 通用 → 登录项」里允许 Glimpse」和「打开登录项设置」按钮（点它打开登录项设置）；在那里重新打开后点回来，红字消失（与设置页表现一致）
- 授权后在系统设置里**关掉** Glimpse 的屏幕录制开关，回到任意应用按 ⇧⌘A：不出现黑屏覆盖层，引导窗口出现，菜单栏图标带标记
- 截图被拒模式（不好人为制造：macOS 15+ 定期确认录屏权限时点「拒绝」或类似情况才会出现，遇到时检查）：引导窗口直接显示「系统设置里已允许，但截图仍被拒绝。请重新启动 Glimpse；若仍不行，在系统设置里关掉再打开 Glimpse 的开关。」和「重新启动 Glimpse」，过几秒也不会自己关掉，只能用 ✕ / Esc / 重新启动关闭；菜单栏图标带标记，直到下一次截图成功；窗口开着时按 ⇧⌘A：窗口先消失，冻结画面里没有它，截图成功后标记消失；覆盖层里 Esc、方向键、⌘C 都正常（键盘没被抢走、覆盖层不闪）；覆盖层关掉后窗口不再回来，键盘回到截图前在用的应用（再次被拒则窗口重新出现）
- 重新启动失败的兜底（同样无法人为制造，代码审查过）：子进程起不来时重启那一行变成红字「无法自动重启，请手动退出后重新打开」并响一声；当前进程 10 秒内没退出时子进程放弃，不会出现两个 Glimpse
- 已授权时退出再打开：不出现引导窗口，菜单栏图标没有标记
- 设置窗口照常（批次 A 的检查抽查两三项）

- [ ] **Step 6：停下，不 commit**

**批次 B 检查点：** 用户确认授权流程（含重新启动）和撤销授权后的表现，再进入批次 C。

---

## 批次 C：识别文字

### Task 7：阅读顺序（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/OCR/ReadingOrder.swift`
- Test: `Core/Tests/GlimpseCoreTests/ReadingOrderTests.swift`

Vision 返回的每一行是一个 `RecognizedLine`（文字 + 单位正方形里的框，左上角原点）。排序规则见实施前说明第 16 条。用合成的框测试（§8「中英混排样图，验证阅读顺序」）：不在单元测试里跑 Vision，真机检查覆盖实际识别。

- [ ] **Step 1：写失败的测试**

新建 `Core/Tests/GlimpseCoreTests/ReadingOrderTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct ReadingOrderTests {
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.05) -> RecognizedLine {
        RecognizedLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func nothingRecognisedIsEmpty() {
        #expect(ReadingOrder.text(of: []) == "")
    }

    @Test func rowsGoTopToBottomWhateverTheInputOrder() {
        let lines = [line("第三行", x: 0.1, y: 0.5), line("第一行", x: 0.1, y: 0.1), line("第二行", x: 0.1, y: 0.3)]
        #expect(ReadingOrder.text(of: lines) == "第一行\n第二行\n第三行")
    }

    @Test func piecesOnOneRowGoLeftToRightWithASpace() {
        let lines = [line("value", x: 0.6, y: 0.2), line("名称：", x: 0.1, y: 0.2)]
        #expect(ReadingOrder.text(of: lines) == "名称： value")
    }

    @Test func aSlightlyLowerOrTallerNeighbourIsTheSameRow() {
        let lines = [line("左", x: 0.1, y: 0.20, height: 0.05),   // centre 0.225
                     line("右", x: 0.6, y: 0.22, height: 0.06),   // centre 0.25, inside 左; 左's centre inside it
                     line("下一行", x: 0.1, y: 0.26, height: 0.05)] // centre 0.285, below 左
        #expect(ReadingOrder.text(of: lines) == "左 右\n下一行")
    }

    @Test func aTallHeadingDoesNotSwallowTheLinesBesideIt() {
        // A big number on the left, two caption lines on its right.
        let lines = [line("50%", x: 0.05, y: 0.10, width: 0.3, height: 0.20),
                     line("第一行说明", x: 0.5, y: 0.10, height: 0.05),
                     line("第二行说明", x: 0.5, y: 0.20, height: 0.05)]
        #expect(ReadingOrder.text(of: lines) == "50%\n第一行说明\n第二行说明")
    }

    @Test func aStaircaseDoesNotChainIntoOneRow() {
        let lines = (0..<4).map { line("第\($0)段", x: 0.1 + CGFloat($0) * 0.2, y: 0.1 + CGFloat($0) * 0.02, width: 0.15) }
        #expect(ReadingOrder.text(of: lines) == "第0段 第1段\n第2段 第3段")
    }

    @Test func aSmallBadgeBetweenTwoPiecesDoesNotSplitTheirRow() {
        let lines = [line("A", x: 0.05, y: 0.10, height: 0.05),           // centre 0.125
                     line("B", x: 0.40, y: 0.11, width: 0.05, height: 0.01), // centre 0.115: in A's middle half
                     line("C", x: 0.50, y: 0.12, height: 0.05)]           // centre 0.145: A's row
        #expect(ReadingOrder.text(of: lines) == "A B C")
    }

    @Test func mixedChineseAndEnglish() {
        let lines = [line("Glimpse 截图工具", x: 0.05, y: 0.05, width: 0.6),
                     line("Version 0.1", x: 0.05, y: 0.15),
                     line("快捷键", x: 0.05, y: 0.25), line("⇧⌘A", x: 0.5, y: 0.255)]
        #expect(ReadingOrder.text(of: lines) == "Glimpse 截图工具\nVersion 0.1\n快捷键 ⇧⌘A")
    }

    @Test func blankLinesAreDropped() {
        let lines = [line("  ", x: 0.1, y: 0.1), line("文字", x: 0.1, y: 0.3)]
        #expect(ReadingOrder.text(of: lines) == "文字")
    }
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter ReadingOrderTests`
Expected: 编译失败，`cannot find type 'RecognizedLine' in scope`

- [ ] **Step 3：实现**

新建 `Core/Sources/GlimpseCore/OCR/ReadingOrder.swift`：

```swift
import CoreGraphics
import Foundation

/// One line Vision recognised. `frame` is in the image's unit square with a top-left origin, y down
/// (Vision's own boxes are bottom-left; the app flips them).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

/// Puts recognised lines in reading order (design doc §3.5): rows top to bottom, each row left to right.
/// Pieces on one row (table cells, a label and its value) are joined with a space, rows with a newline.
/// Columns side by side are read row by row, not column by column, as most screenshot tools do.
public enum ReadingOrder {
    public static func text(of lines: [RecognizedLine]) -> String {
        rows(of: lines).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// Lines grouped into rows. A line joins a row when its vertical centre lies within the row's first line
    /// and that line's centre lies within it: a slightly lower or taller neighbour still counts, a tall
    /// heading does not swallow the lines beside it, and the row never grows, so a staircase of slightly
    /// offset lines cannot chain into one row. The latest row is tried first; earlier rows only past rows started
    /// by a much smaller piece (under half the line's height: a badge, a superscript), so such a piece between
    /// two pieces of one row does not split that row, while a normal line in between still ends it.
    static func rows(of lines: [RecognizedLine]) -> [[RecognizedLine]] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let index = rowIndex(for: line, in: rows) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func rowIndex(for line: RecognizedLine, in rows: [[RecognizedLine]]) -> Int? {
        for index in rows.indices.reversed() {
            let first = rows[index][0].frame
            if sharesRow(line.frame, first) { return index }
            guard first.height < line.frame.height / 2 else { return nil } // only a small piece is looked past
        }
        return nil
    }

    /// Similar heights: each centre lies within the other. One more than twice as tall as the other: the short
    /// piece's centre lies within the middle half of the tall one (a badge inside a line of text), which
    /// still keeps the lines beside a tall heading, at its top and bottom, out of its row.
    private static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        func centre(_ r: CGRect, isWithin s: CGRect) -> Bool { r.midY >= s.minY && r.midY <= s.maxY }
        let (short, tall) = a.height <= b.height ? (a, b) : (b, a)
        if tall.height > short.height * 2 {
            return centre(short, isWithin: tall.insetBy(dx: 0, dy: tall.height / 4))
        }
        return centre(a, isWithin: b) && centre(b, isWithin: a)
    }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test`
Expected: `Test run with 187 tests in 28 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 8：Vision 识别与结果面板

**Files:**
- Create: `App/Sources/OCR/OCRService.swift`、`App/Sources/OCR/OCRResultPanel.swift`、`App/Sources/OCR/OCRController.swift`

- `OCRService`：§3.5 的参数原样照抄（`["zh-Hans", "zh-Hant", "en-US"]`、`.accurate`、`usesLanguageCorrection = true`），在后台线程跑，把 Vision 左下角原点的框翻成左上角；调用方的任务被取消时 `request.cancel()` 让 Vision 停下。
- `OCRResultPanel`：实施前说明第 17 条。文字框沿用 P2 文字工具的做法：菜单栏应用没有「编辑」菜单，⌘C / ⌘V / ⌘X / ⌘A / ⌘Z / ⇧⌘Z 由文字框自己处理；输入法组字时 Esc 只取消组字。
- `OCRController`：识别 → 有文字就复制并显示「已复制」→ 面板。新的识别取消旧的；写剪贴板前先确认没被取消、面板还开着（实施前说明第 17 条）。`dismissPanel()` 供新截图开始时收起面板、取消进行中的识别（Task 9 接上）。结果面板不显示 Dock 图标（第 23 条）。

- [ ] **Step 1：三个新文件**

新建 `App/Sources/OCR/OCRService.swift`：

```swift
import CoreGraphics
import GlimpseCore
import Vision

/// Local, offline text recognition with Vision (design doc §3.5, §5.1): accurate mode, Simplified and
/// Traditional Chinese and English, with language correction. Nothing leaves the Mac.
enum OCRService {
    /// The lines Vision finds in `image`, in no particular order (`ReadingOrder` sorts them).
    /// Runs off the main thread; cancelling the calling task stops Vision (it then throws).
    static func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        let box = RequestBox(request)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let request = box.request
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return (request.results ?? []).compactMap { observation -> RecognizedLine? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    // Vision's box is normalised with a bottom-left origin; RecognizedLine is top-left.
                    let box = observation.boundingBox
                    return RecognizedLine(text: text, frame: CGRect(x: box.minX, y: 1 - box.maxY,
                                                                    width: box.width, height: box.height))
                }
            }.value
        } onCancel: {
            box.request.cancel()
        }
    }
}

/// Hands the request to the background task and to the cancellation handler. Vision documents `cancel()`
/// as callable from another thread while `perform` runs; nothing else touches the request concurrently.
private final class RequestBox: @unchecked Sendable {
    let request: VNRecognizeTextRequest

    init(_ request: VNRecognizeTextRequest) {
        self.request = request
    }
}
```

新建 `App/Sources/OCR/OCRResultPanel.swift`：

```swift
import AppKit
import GlimpseCore

/// The text recognition result (design doc §3.5): a glass panel with the text, editable, a 「复制」 button,
/// and 「已复制」 next to the title once the text is on the clipboard. Esc, ⌘W or ✕ closes it.
/// A non-activating panel that still takes the keyboard, like the overlay: the app the user was in stays
/// active, and closing the panel hands the keyboard straight back to it.
final class OCRResultPanel: NSPanel {
    enum State: Equatable {
        case recognizing
        case copied(String)
        case noText
        case failed
    }

    private static let size = CGSize(width: 440, height: 300)
    private static let inset: CGFloat = 16

    private let material = MaterialView(cornerRadius: 12, blendsBehindWindow: true)
    private let status = NSTextField(labelWithString: "")
    private let textView = OCRTextView(frame: .zero)
    private let scrollView = NSScrollView()
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    /// Called whenever the panel closes (Esc, ⌘W, ✕, or a new capture starting).
    var onDismiss: (() -> Void)?
    /// Centred on the selection's screen the first time only; afterwards it stays where the user put it.
    private var hasBeenPlaced = false

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let size = Self.size, inset = Self.inset
        material.frame = CGRect(origin: .zero, size: size)
        material.autoresizingMask = [.width, .height]
        contentView = material
        let content = material.contentView

        let title = NSTextField(labelWithString: "识别文字")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .materialText
        title.sizeToFit()
        title.frame.origin = CGPoint(x: inset, y: inset)
        content.addSubview(title)

        status.font = .systemFont(ofSize: 12)
        status.textColor = .materialSecondaryText
        status.frame = CGRect(x: title.frame.maxX + 8, y: inset + 1, width: 200, height: title.frame.height)
        content.addSubview(status)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")!,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = .materialSecondaryText
        close.frame = CGRect(x: size.width - inset - 20, y: inset - 2, width: 20, height: 20)
        content.addSubview(close)

        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.bezelStyle = .push
        copyButton.sizeToFit()
        copyButton.frame.origin = CGPoint(x: size.width - inset - copyButton.frame.width,
                                          y: size.height - inset - copyButton.frame.height)
        content.addSubview(copyButton)

        let textTop = title.frame.maxY + 10
        scrollView.frame = CGRect(x: inset, y: textTop, width: size.width - inset * 2,
                                  height: copyButton.frame.minY - 10 - textTop)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        textView.configure()
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.onEscape = { [weak self] in self?.dismiss() }
        textView.onEdit = { [weak self] in
            guard let self else { return }
            status.stringValue = "" // edited: the clipboard has the old text
            copyButton.isEnabled = !textView.string.isEmpty
        }
        scrollView.documentView = textView
        content.addSubview(scrollView)
    }

    override var canBecomeKey: Bool { true }

    /// Opens in the middle of `screen` (the one the selection was on) the first time, afterwards where the
    /// user left it (unless that is no longer on any screen), and takes the keyboard.
    func show(_ state: State, on screen: NSScreen?) {
        update(state)
        let isOnScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !hasBeenPlaced || !isOnScreen, let visible = (screen ?? NSScreen.main)?.visibleFrame {
            setFrameOrigin(CGPoint(x: (visible.midX - frame.width / 2).rounded(),
                                   y: (visible.midY - frame.height / 2).rounded()))
            hasBeenPlaced = true
        }
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(textView)
    }

    /// Replaces the text; only a recognised text can be edited.
    func update(_ state: State) {
        textView.isEditable = false // before replacing the text: setting it is not an edit
        switch state {
        case .recognizing:
            status.stringValue = "正在识别…"
            textView.string = ""
        case .copied(let text):
            status.stringValue = "已复制"
            textView.string = text
        case .noText:
            status.stringValue = "未识别到文字"
            textView.string = ""
        case .failed:
            status.stringValue = "识别失败"
            textView.string = ""
        }
        if case .copied = state { textView.isEditable = true }
        // The undo stack points into the text just replaced: ⌘Z there would raise an out-of-range exception.
        textView.undoManager?.removeAllActions()
        copyButton.isEnabled = !textView.string.isEmpty
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        // Only these four count: Caps Lock or fn must not stop ⌘W.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command, Self.isW(event) else { return false }
        dismiss()
        return true
    }

    /// The W key: by character, or by key code (13) when the layout types no Latin letters (Russian, Greek…).
    private static func isW(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return key == "w" || (!key.unicodeScalars.allSatisfy(\.isASCII) && event.keyCode == 13)
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }

    @objc private func closeClicked() {
        dismiss()
    }

    @objc private func copyClicked() {
        guard !textView.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        status.stringValue = "已复制"
    }
}

/// The editable result. A menu-bar app has no Edit menu, so the usual editing shortcuts are mapped here
/// (as in the annotation text box); Esc closes the panel unless an input method is composing.
private final class OCRTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onEdit: (() -> Void)?

    /// Plain text in the material's text colour, no smart substitutions: what was recognised stays as it is.
    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = .systemFont(ofSize: 13)
        textColor = .materialText
        insertionPointColor = .materialText
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { return super.cancelOperation(sender) }
        onEscape?()
    }

    override func didChangeText() {
        super.didChangeText()
        onEdit?()
    }

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

新建 `App/Sources/OCR/OCRController.swift`：

```swift
import AppKit
import GlimpseCore

/// Recognises the text of a selection and shows it (design doc §3.5): the result goes to the clipboard
/// at once and into the result panel, where it can be edited and copied again. No HUD: the panel says
/// 「已复制」 itself (§3.8.1).
@MainActor
final class OCRController {
    /// Created on the first recognition.
    private var panel: OCRResultPanel?
    /// The recognition whose result the panel waits for; a newer one replaces it.
    private var current: Task<Void, Never>?

    /// `image` is the selection's frozen pixels without annotations; the panel opens on `screen`.
    func recognize(_ image: CGImage, on screen: NSScreen?) {
        current?.cancel() // stops the older recognition's Vision request too
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.show(.recognizing, on: screen)
        current = Task {
            let text: String?
            do {
                text = ReadingOrder.text(of: try await OCRService.recognize(image))
            } catch {
                if !Task.isCancelled { NSLog("Glimpse: text recognition failed: \(error)") }
                text = nil
            }
            // Replaced by a newer recognition, or the panel was closed meanwhile: leave the clipboard alone.
            guard !Task.isCancelled, panel.isVisible else { return }
            guard let text else { return panel.update(.failed) }
            guard !text.isEmpty else { return panel.update(.noText) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel.update(.copied(text))
        }
    }

    private func makePanel() -> OCRResultPanel {
        let panel = OCRResultPanel()
        panel.onDismiss = { [weak self] in self?.current?.cancel() } // closed: the recognition is not wanted
        return panel
    }

    /// A new capture is starting: the panel must not end up in the frozen screen, and a recognition still
    /// running is dropped. Returns whether the panel was on screen.
    func dismissPanel() -> Bool {
        current?.cancel()
        current = nil
        guard let panel, panel.isVisible else { return false }
        panel.dismiss()
        return true
    }
}
```

- [ ] **Step 2：编译**

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误，最后一行输出 app 路径（这三个类型还没被用到，下一个任务接上）

- [ ] **Step 3：停下，不 commit**

---

### Task 9：工具栏、菜单、快捷键三个入口

**Files:**
- Modify（整体替换）: `App/Sources/Toolbar/ToolbarItem.swift`
- Modify: `App/Sources/Overlay/OverlayContentView.swift`、`App/Sources/Overlay/SelectionView.swift`、`App/Sources/Overlay/CaptureSessionController.swift`、`App/Sources/MenuBar/StatusItemController.swift`、`App/Sources/AppDelegate.swift`

- 工具栏第三组加「识别文字」（实施前说明第 21 条）；`shortcut` 改成可选，没有单键的按钮提示只显示名称。
- `SelectionView.finish(_:)` 改为内部可见（工具栏按钮直接调用），识别文字时用 `Renderer.crop` 取原始像素（第 15 条）。`recognizesTextOnSelection` 为 true 时，选区一确定就识别：放到下一轮 run loop 再调 `finish`，让调用方自己的回调（清掉其他屏、交还焦点）先在会话还开着时跑完；Esc 先到的话窗口已关，什么也不做。
- 会话 `start(recognizingText:)`；收到 `.recognizeText` 时关覆盖层、交给 `OCRController`，不复制图片、不弹 HUD。每次开始截图先收起识别结果面板（同 HUD、引导窗口，实施前说明第 17 条）。延后一轮的识别只在选区仍是当时那一块时才进行。
- 菜单加「识别文字」；`AppDelegate` 的识别文字快捷键换成真正的识别。

- [ ] **Step 1：工具栏按钮**

`App/Sources/Toolbar/ToolbarItem.swift` 整体替换为：

```swift
import GlimpseCore

/// One toolbar button. Order and grouping follow design doc §3.3.
enum ToolbarItem: Hashable {
    case tool(Tool)
    case undo, redo
    case recognizeText, save
    case cancel, confirm

    /// Separators go between groups.
    static let groups: [[ToolbarItem]] = [
        Tool.allCases.map { .tool($0) },
        [.undo, .redo],
        [.recognizeText, .save],
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
        case .recognizeText: "text.viewfinder"
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
        case .recognizeText: "识别文字"
        case .save: "保存"
        case .cancel: "取消"
        case .confirm: "完成"
        }
    }

    /// Shown in the tooltip next to the name (design doc §3.3); nil for buttons without a key in the overlay.
    var shortcut: String? {
        switch self {
        case .tool(let tool): tool.shortcut.uppercased()
        case .undo: "⌘Z"
        case .redo: "⇧⌘Z"
        case .recognizeText: nil
        case .save: "⌘S"
        case .cancel: "Esc"
        case .confirm: "↩"
        }
    }

    var toolTip: String { shortcut.map { "\(title)（\($0)）" } ?? title }
}
```

（1）`App/Sources/Overlay/OverlayContentView.swift`：把

```swift
        case .save:
            selectionView.perform(.save)
```

替换为

```swift
        case .recognizeText:
            selectionView.finish(.recognizeText)
        case .save:
            selectionView.perform(.save)
```

- [ ] **Step 2：SelectionView**

在 `App/Sources/Overlay/SelectionView.swift` 里按顺序做下面 6 处替换（每段原文在文件里只出现一次）：

（1）`App/Sources/Overlay/SelectionView.swift`：把

```swift
enum OverlayFinishAction {
    case copy
    case save
}
```

替换为

```swift
enum OverlayFinishAction {
    case copy
    case save
    /// The selection's frozen pixels, without annotations, go to text recognition (design doc §3.5).
    case recognizeText
}
```

（2）`App/Sources/Overlay/SelectionView.swift`：把

```swift
    weak var chromeDelegate: SelectionViewChromeDelegate?
```

替换为

```swift
    weak var chromeDelegate: SelectionViewChromeDelegate?
    /// Text recognition from the menu or its shortcut (design doc §3.5): the selection is recognised as soon
    /// as it is made, with no editing phase. Set by the session before the overlay shows.
    var recognizesTextOnSelection = false
```

（3）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        drag = .none
        phase = .editing(tool: nil)
        refreshDisplay()
        refreshHoverAtMouse()
    }
```

替换为

```swift
        drag = .none
        if recognizesTextOnSelection {
            // Straight to recognition, without the toolbar. On the next turn of the run loop, so the caller's
            // own callbacks (other screens reset, focus) still run against a live session.
            refreshDisplay()
            let chosen = newSelection.rect
            DispatchQueue.main.async { [weak self] in
                // Cancelled (window closed) or selection cleared or replaced meanwhile: nothing to recognise.
                guard let self, self.window?.isVisible == true, self.selection?.rect == chosen else { return }
                self.finish(.recognizeText)
            }
            return
        }
        phase = .editing(tool: nil)
        refreshDisplay()
        refreshHoverAtMouse()
    }
```

（4）`App/Sources/Overlay/SelectionView.swift`：把

```swift
    private func finish(_ action: OverlayFinishAction) {
```

替换为

```swift
    /// Ends the capture with the selection, or while selecting with the hover target. Keys, double click
    /// and the toolbar's buttons all end up here.
    func finish(_ action: OverlayFinishAction) {
```

（5）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        guard let image = Renderer.composite(captured.image, annotations: canvas.document.annotations,
                                             toPixelRect: pixels,
                                             pixelated: { [canvas] in canvas.mosaicSource.pixelated(blockSize: $0) }) else {
```

替换为

```swift
        let rendered = action == .recognizeText
            // Text is read from the frozen pixels alone, without the annotations (design doc §3.2 step 4).
            ? Renderer.crop(captured.image, toPixelRect: pixels)
            : Renderer.composite(captured.image, annotations: canvas.document.annotations, toPixelRect: pixels,
                                 pixelated: { [canvas] in canvas.mosaicSource.pixelated(blockSize: $0) })
        guard let image = rendered else {
            // When recognising text from the menu or its shortcut, the overlay stays up without a toolbar:
            // dragging or clicking again makes a new selection (and recognises it), Esc leaves.
```

（6）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        case .finishCopy:
            finish(.copy)
        case .save:
            finish(.save)
```

替换为

```swift
        case .finishCopy:
            finish(recognizesTextOnSelection ? .recognizeText : .copy) // Enter on a window while recognising text
        case .save:
            finish(recognizesTextOnSelection ? .recognizeText : .save)
```

- [ ] **Step 3：CaptureSessionController**

在 `App/Sources/Overlay/CaptureSessionController.swift` 里按顺序做下面 7 处替换：

（1）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    private let settings: SettingsStore
    private let capture = CaptureService()
```

替换为

```swift
    private let settings: SettingsStore
    private let ocr: OCRController
    private let capture = CaptureService()
    /// This session recognises text instead of editing (the menu's or the shortcut's 识别文字).
    private var recognizingText = false
```

（2）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    init(settings: SettingsStore) {
        self.settings = settings
    }
```

替换为

```swift
    init(settings: SettingsStore, ocr: OCRController) {
        self.settings = settings
        self.ocr = ocr
    }
```

（3）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    func start() {
```

替换为

```swift
    /// `recognizingText`: 识别文字 from the menu or its shortcut (design doc §3.5): the selection is recognised
    /// as soon as it is made, without the editing phase.
    func start(recognizingText: Bool = false) {
```

（4）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        isRunning = true
        screensChangedDuringCapture = false
```

替换为

```swift
        isRunning = true
        self.recognizingText = recognizingText
        screensChangedDuringCapture = false
```

（5）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
            window.selectionView.delegate = self
```

替换为

```swift
            window.selectionView.delegate = self
            window.selectionView.recognizesTextOnSelection = recognizingText
```

（6）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        close()
        // Saving also copies (design doc §3.2), so a failed save still leaves the image on the clipboard.
```

替换为

```swift
        close()
        if action == .recognizeText {
            ocr.recognize(image, on: screen) // only the text goes to the clipboard (design doc §3.5)
            return
        }
        // Saving also copies (design doc §3.2), so a failed save still leaves the image on the clipboard.
```

（7）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
        // Before capturing: a HUD or the onboarding window still on screen would be in the screenshot.
        let hudWasVisible = hud.dismiss()
        let windowWasHidden = onCaptureWillStart?() ?? false
        observeScreenChanges()
        Task { @MainActor in
            if hudWasVisible || windowWasHidden {
```

替换为

```swift
        // Before capturing: a HUD, the text recognition result or the onboarding window still on screen
        // would be in the screenshot. A recognition still running is dropped with its panel.
        let hudWasVisible = hud.dismiss()
        let ocrPanelWasVisible = ocr.dismissPanel()
        let windowWasHidden = onCaptureWillStart?() ?? false
        observeScreenChanges()
        Task { @MainActor in
            if hudWasVisible || ocrPanelWasVisible || windowWasHidden {
```

- [ ] **Step 4：菜单和 AppDelegate**

按顺序做下面 8 处替换：

（1）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
/// The menu bar icon and its menu (design doc §3.7): 截图, 设置…, 退出.
```

替换为

```swift
/// The menu bar icon and its menu (design doc §3.7): 截图, 识别文字, 设置…, 退出.
```

（2）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
    private let onCapture: () -> Void
    private let onSettings: () -> Void
```

替换为

```swift
    private let onCapture: () -> Void
    private let onRecognizeText: () -> Void
    private let onSettings: () -> Void
```

（3）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
```

替换为

```swift
    init(onCapture: @escaping () -> Void, onRecognizeText: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onRecognizeText = onRecognizeText
        self.onSettings = onSettings
```

（4）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
        actionItems[.screenshot] = captureItem
        menu.addItem(.separator())
```

替换为

```swift
        actionItems[.screenshot] = captureItem
        let ocrItem = NSMenuItem(title: "识别文字", action: #selector(recognizeTextClicked), keyEquivalent: "")
        ocrItem.target = self
        menu.addItem(ocrItem)
        actionItems[.ocr] = ocrItem
        menu.addItem(.separator())
```

（5）`App/Sources/MenuBar/StatusItemController.swift`：把

```swift
    @objc private func settingsClicked() {
```

替换为

```swift
    @objc private func recognizeTextClicked() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { [onRecognizeText] in onRecognizeText() }
    }

    @objc private func settingsClicked() {
```

（6）`App/Sources/AppDelegate.swift`：把

```swift
        session = CaptureSessionController(settings: settings)
        let statusItem = StatusItemController(onCapture: { [weak self] in self?.startCapture() },
                                              onSettings: { [weak self] in self?.showSettings() })
```

替换为

```swift
        session = CaptureSessionController(settings: settings, ocr: OCRController())
        let statusItem = StatusItemController(onCapture: { [weak self] in self?.startCapture() },
                                              onRecognizeText: { [weak self] in self?.startRecognizingText() },
                                              onSettings: { [weak self] in self?.showSettings() })
```

（7）`App/Sources/AppDelegate.swift`：把

```swift
            .ocr: { NSSound.beep() }, // text recognition arrives in Task 9
```

替换为

```swift
            .ocr: { [weak self] in
                self?.statusItem?.performAfterMenuCloses { [weak self] in self?.startRecognizingText() }
            },
```

（8）`App/Sources/AppDelegate.swift`：把

```swift
    @MainActor
    private func showSettings() {
```

替换为

```swift
    @MainActor
    private func startRecognizingText() {
        session?.start(recognizingText: true)
    }

    @MainActor
    private func showSettings() {
```

- [ ] **Step 5：编译**

Run: `cd . && grep -rn "NSSound.beep() }, // text recognition" App/Sources`
Expected: 没有输出（批次 A 的占位已换掉）

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误、没有新增警告，最后一行输出 app 路径

Run: `cd Core && swift test`
Expected: `Test run with 187 tests in 28 suites passed`

- [ ] **Step 6：停下，不 commit**

**批次 C 不上真机：** 识别文字和贴图在 Task 11 末尾一起检查（实施前说明第 25 条），直接进入批次 D。

---

## 批次 D：贴图

### Task 10：贴图缩放与坐标换算（Core）

**Files:**
- Create: `Core/Sources/GlimpseCore/Pin/PinZoom.swift`
- Modify: `Core/Sources/GlimpseCore/Geometry/CoordinateSpace.swift`、`Core/Sources/GlimpseCore/Geometry/WindowHitTester.swift`
- Test: `Core/Tests/GlimpseCoreTests/PinZoomTests.swift`、`Core/Tests/GlimpseCoreTests/CoordinateSpaceTests.swift`、`Core/Tests/GlimpseCoreTests/WindowHitTesterTests.swift`

缩放规则见实施前说明第 18 条：每个滚轮事件乘以 `exp(delta × k)`（滚轮 k = 0.1，触控板的点级增量 k = 0.01），捏合乘以 `1 + magnification`；限制在 [最小值, 最大值]，最大值是 5 和「长边 10000pt」中较小的那个；经过 100%、或朝 100% 走到相差 3% 以内时停在正好 1；新窗口以鼠标为中心缩放，100% 时大小就是图片原尺寸，其他倍数取到屏幕像素（`backingScale`）上。`appKitRect(fromLocal:in:)` 是 `localRect(fromAppKit:in:)` 的逆：贴图要出现在选区的位置。`WindowHitTester.removingOwnWindows(_:ownPID:)`：窗口列表只剔除 Glimpse 自己层级为 0 的窗口，贴图等层级高于 0 的留作遮挡（实施前说明第 20 条）。

- [ ] **Step 1：写失败的测试**

新建 `Core/Tests/GlimpseCoreTests/PinZoomTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import GlimpseCore

struct PinZoomTests {
    let image = CGSize(width: 400, height: 200)

    @Test func wheelAwayZoomsInAndTowardsZoomsOut() {
        #expect(PinZoom.zoom(1, scrolledBy: 1, precise: false, imageSize: image) > 1)
        #expect(PinZoom.zoom(1, scrolledBy: -1, precise: false, imageSize: image) < 1)
        // A trackpad's point deltas are ten times finer than wheel lines.
        let wheel = PinZoom.zoom(1, scrolledBy: 1, precise: false, imageSize: image)
        let trackpad = PinZoom.zoom(1, scrolledBy: 10, precise: true, imageSize: image)
        #expect(abs(wheel - trackpad) < 1e-9)
    }

    @Test func zoomIsClamped() {
        #expect(PinZoom.zoom(4.9, scrolledBy: 100, precise: false, imageSize: image) == PinZoom.maximumZoom)
        #expect(PinZoom.zoom(1, scrolledBy: -100, precise: false, imageSize: image) == 0.12) // 24 / 200
        #expect(PinZoom.minimum(imageSize: CGSize(width: 4000, height: 3000)) == 0.1)
        #expect(PinZoom.minimum(imageSize: CGSize(width: 300, height: 16)) == 1) // already smaller than 24pt
    }

    @Test func bigImagesStopAtTenThousandPoints() {
        let big = CGSize(width: 4000, height: 1000)
        #expect(PinZoom.maximum(imageSize: big) == 2.5)
        #expect(PinZoom.zoom(2, scrolledBy: 100, precise: false, imageSize: big) == 2.5)
    }

    @Test func pinchZoomsByTheMagnification() {
        #expect(abs(PinZoom.zoom(1, magnifiedBy: 0.25, imageSize: image) - 1.25) < 1e-9)
        #expect(abs(PinZoom.zoom(1, magnifiedBy: -0.5, imageSize: image) - 0.5) < 1e-9)
        #expect(PinZoom.zoom(1, magnifiedBy: -5, imageSize: image) == 0.12) // clamped to the 24pt minimum
    }

    @Test func zoomStopsAtActualSizeOnTheWayThrough() {
        // Crossing 100% stops there, by wheel or by pinch.
        #expect(PinZoom.zoom(0.9, scrolledBy: 2, precise: false, imageSize: image) == 1)
        #expect(PinZoom.zoom(1.1, scrolledBy: -2, precise: false, imageSize: image) == 1)
        #expect(PinZoom.zoom(0.9, magnifiedBy: 0.2, imageSize: image) == 1)
        // Heading towards 100% and within 3% of it: snaps.
        #expect(PinZoom.zoom(0.95, scrolledBy: 3, precise: true, imageSize: image) == 1)
        // Leaving 100%, however finely, is not held back.
        #expect(PinZoom.zoom(1, scrolledBy: 1, precise: true, imageSize: image) > 1)
        #expect(PinZoom.zoom(1.01, scrolledBy: 1, precise: true, imageSize: image) > 1.01)
        #expect(PinZoom.zoom(1, scrolledBy: -1, precise: true, imageSize: image) < 1)
    }

    @Test func zoomKeepsThePointUnderTheMouse() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 200)
        let zoomed = PinZoom.frame(frame, zoomedTo: 2, imageSize: image, anchor: CGPoint(x: 200, y: 150), backingScale: 2)
        #expect(zoomed == CGRect(x: 0, y: 50, width: 800, height: 400))
    }

    @Test func zoomedFramesLandOnThePixelGrid() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let zoomed = PinZoom.frame(frame, zoomedTo: 1.013, imageSize: image, anchor: CGPoint(x: 133, y: 77), backingScale: 2)
        #expect(zoomed.origin.x * 2 == (zoomed.origin.x * 2).rounded())
        #expect(zoomed.origin.y * 2 == (zoomed.origin.y * 2).rounded())
        #expect(zoomed.size == CGSize(width: 405, height: 202.5)) // 405.2 × 202.6 to half points
        let onePoint = PinZoom.frame(frame, zoomedTo: 1.013, imageSize: image, anchor: CGPoint(x: 133, y: 77), backingScale: 1)
        #expect(onePoint.size == CGSize(width: 405, height: 203))
    }

    @Test func actualSizeIsTheImageSizeExactly() {
        // A capture from a 1.5× screen is not whole points; at 100% it must still map 1:1 to its pixels.
        let odd = CGSize(width: 200.5, height: 100.5)
        let frame = CGRect(x: 10, y: 20, width: 220, height: 110)
        let zoomed = PinZoom.frame(frame, zoomedTo: 1, imageSize: odd, anchor: CGPoint(x: 60, y: 50), backingScale: 2)
        #expect(zoomed.size == odd)
    }
}
```

（1）`Core/Tests/GlimpseCoreTests/CoordinateSpaceTests.swift`：把

```swift
    @Test func containsInclusiveCountsMaxEdges() {
```

替换为

```swift
    @Test func localRectToAppKitOnExternalScreen() {
        // The inverse of localRect(fromAppKit:): 100pt right of and 30pt below the external screen's top-left.
        let local = CGRect(x: 100, y: 30, width: 300, height: 200)
        let global = CoordinateSpace.appKitRect(fromLocal: local, in: external)
        #expect(global == CGRect(x: -2460, y: 887, width: 300, height: 200))
        #expect(CoordinateSpace.localRect(fromAppKit: global, in: external) == local)
    }

    @Test func containsInclusiveCountsMaxEdges() {
```

（2）`Core/Tests/GlimpseCoreTests/WindowHitTesterTests.swift`：把

```swift
    @Test func tinyWindowsAreSkippedNotBlocking() {
```

替换为

```swift
    @Test func ownPinsBlockTheWindowBehindButAreNeverHit() {
        // Glimpse is pid 20: a pinned screenshot (floating, layer 3) over the front window, and a normal
        // Glimpse window (layer 0, such as the settings window) elsewhere.
        let pin = WindowInfo(windowID: 8, frame: CGRect(x: 150, y: 150, width: 100, height: 100), layer: 3, ownerPID: 20)
        let settings = WindowInfo(windowID: 9, frame: CGRect(x: 600, y: 100, width: 200, height: 200), layer: 0, ownerPID: 20)
        let kept = WindowHitTester.removingOwnWindows([pin, settings] + windows, ownPID: 20)
        #expect(kept.map(\.windowID) == [8, 1, 2, 3])
        // Over the pin nothing is highlighted; beside it the window behind still is.
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 200, y: 200), in: kept) == nil)
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 300, y: 300), in: kept)?.windowID == 2)
        // Where the settings window was, the window behind it is the target.
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 700, y: 200), in: kept)?.windowID == 3)
    }

    @Test func tinyWindowsAreSkippedNotBlocking() {
```

- [ ] **Step 2：运行测试，确认失败**

Run: `cd Core && swift test --filter "PinZoomTests|CoordinateSpaceTests|WindowHitTesterTests"`
Expected: 编译失败，`cannot find 'PinZoom' in scope`；`CoordinateSpaceTests.swift` 里报 `incorrect argument labels in call (have 'fromLocal:in:', expected 'fromCG:primaryScreenHeight:')`（`appKitRect` 现在只有 `appKitRect(fromCG:primaryScreenHeight:)` 一个，编译器按它报参数名不对）；`WindowHitTesterTests.swift` 里报 `type 'WindowHitTester' has no member 'removingOwnWindows'`

- [ ] **Step 3：实现**

新建 `Core/Sources/GlimpseCore/Pin/PinZoom.swift`：

```swift
import CoreGraphics
import Foundation

/// Scroll-wheel and pinch zoom for pinned images (design doc §3.6). Zoom 1 is the capture's own size in points.
public enum PinZoom {
    /// Never past 500%.
    public static let maximumZoom: CGFloat = 5
    /// Nor past this many points on the longer side: a big capture at 500% would be a window larger than
    /// any screen and a huge backing store.
    public static let maximumSide: CGFloat = 10_000

    /// No smaller than 10%, and the shorter side no smaller than 24pt, unless the image is smaller to start with.
    public static func minimum(imageSize: CGSize) -> CGFloat {
        let shorter = min(imageSize.width, imageSize.height)
        guard shorter > 0 else { return 1 }
        return min(1, max(0.1, 24 / shorter))
    }

    /// 500%, or less when the longer side would pass `maximumSide`; never below the minimum.
    public static func maximum(imageSize: CGSize) -> CGFloat {
        let longer = max(imageSize.width, imageSize.height)
        guard longer > 0 else { return maximumZoom }
        return max(minimum(imageSize: imageSize), min(maximumZoom, maximumSide / longer))
    }

    /// The zoom after one scroll event. `delta` is positive for "zoom in" (wheel away from the user);
    /// precise (trackpad) deltas are in points and much finer than a wheel's lines.
    public static func zoom(_ current: CGFloat, scrolledBy delta: CGFloat, precise: Bool, imageSize: CGSize) -> CGFloat {
        settle(current, current * exp(delta * (precise ? 0.01 : 0.1)), imageSize: imageSize)
    }

    /// The zoom after one trackpad pinch event (`NSEvent.magnification`: 0.1 is 10% larger).
    public static func zoom(_ current: CGFloat, magnifiedBy magnification: CGFloat, imageSize: CGSize) -> CGFloat {
        settle(current, current * max(0.01, 1 + magnification), imageSize: imageSize)
    }

    /// Within this much of 100%, a zoom heading towards it stops there.
    static let actualSizeSnap: CGFloat = 0.03

    /// 100% is where the image is sharp, so a zoom that crosses it, or comes within `actualSizeSnap` of it
    /// on the way there, stops at exactly 1. Leaving 100% is never held back, however fine the steps.
    private static func settle(_ current: CGFloat, _ next: CGFloat, imageSize: CGSize) -> CGFloat {
        let crossed = (current < 1 && next > 1) || (current > 1 && next < 1)
        let arriving = abs(next - 1) < abs(current - 1) && abs(next - 1) <= actualSizeSnap
        let settled = crossed || arriving ? 1 : next
        return min(max(settled, minimum(imageSize: imageSize)), maximum(imageSize: imageSize))
    }

    /// The window frame at `zoom`, scaled about `anchor` (the mouse, in the same coordinates as `frame`), so
    /// the pixel under the mouse stays under it. On the screen's pixel grid (`backingScale` pixels per point);
    /// at exactly 100% the size is the image's own, so every image pixel lands on one screen pixel.
    public static func frame(_ frame: CGRect, zoomedTo zoom: CGFloat, imageSize: CGSize, anchor: CGPoint,
                             backingScale: CGFloat) -> CGRect {
        let scale = max(1, backingScale)
        func onGrid(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let size = zoom == 1 ? imageSize
            : CGSize(width: max(1 / scale, onGrid(imageSize.width * zoom)),
                     height: max(1 / scale, onGrid(imageSize.height * zoom)))
        let fx = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let fy = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        return CGRect(x: onGrid(anchor.x - fx * size.width), y: onGrid(anchor.y - fy * size.height),
                      width: size.width, height: size.height)
    }
}
```

（1）`Core/Sources/GlimpseCore/Geometry/CoordinateSpace.swift`：把

```swift
    public static func localRect(fromCG rect: CGRect, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGRect {
```

替换为

```swift
    public static func appKitRect(fromLocal rect: CGRect, in screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    public static func localRect(fromCG rect: CGRect, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGRect {
```

（2）`Core/Sources/GlimpseCore/Geometry/WindowHitTester.swift`：把

```swift
    /// `windows` must be ordered front-to-back
```

替换为

```swift
    /// Drops Glimpse's own normal windows (layer 0, such as the settings window): they are never a target.
    /// Its windows above layer 0 (pinned screenshots, the text recognition panel) are kept as occluders:
    /// they are in the frozen screen, so the window behind one must not light up under the mouse.
    public static func removingOwnWindows(_ windows: [WindowInfo], ownPID: pid_t) -> [WindowInfo] {
        windows.filter { $0.ownerPID != ownPID || $0.layer > 0 }
    }

    /// `windows` must be ordered front-to-back
```

- [ ] **Step 4：运行测试，确认通过**

Run: `cd Core && swift test`
Expected: `Test run with 197 tests in 29 suites passed`

- [ ] **Step 5：停下，不 commit**

---

### Task 11：贴图浮窗

**Files:**
- Create: `App/Sources/Pin/PinWindow.swift`、`App/Sources/Pin/PinWindowController.swift`
- Modify: `App/Sources/Toolbar/ToolbarItem.swift`、`App/Sources/Overlay/OverlayContentView.swift`、`App/Sources/Overlay/SelectionView.swift`、`App/Sources/Overlay/CaptureSessionController.swift`、`App/Sources/AppDelegate.swift`、`App/Sources/Services/CaptureService.swift`

- `PinWindow`：不激活、不成为 key 的浮动面板（`isFloatingPanel` 即 `.floating` 层级，低于覆盖层的 `.screenSaver`，所以截图时覆盖层盖得住它；也低于 Dock 和菜单栏，接受）；图像放在图层里按窗口大小缩放；拖动、滚轮（忽略惯性滚动）、捏合、双击、右键菜单（实施前说明第 18、19 条）。右键菜单走 AppKit 自己的右键路径（`menu(for:)` → `NSMenu.popUpContextMenu(_:with:for:)`，同时支持 ⌃ 点按），不自己调 `popUp(positioning:at:in:)`。
- `PinWindowController`：持有所有贴图；复制 / 保存走 `OutputService`，结果用 HUD 提示（与 ⌘S 一样先复制再保存）。双击或菜单「关闭」发生在贴图窗口的 `sendEvent` 里：`close()` 后留到下一轮 runloop 再释放（同会话的 `close()`）。显示器变化后把不在任何屏幕上的贴图移回主屏。
- 贴图的 HUD 提示经会话新加的 `showHUD(_:on:)`：截图进行中就放进 `pendingHUD`（实施前说明「HUD」一条）。触控板捏合也缩放（第 18 条）。
- `SelectionView.finish` 把图片的位置（由裁出的像素矩形换算回 AppKit 全局坐标）随图片一起交给会话；会话收到 `.pin`：关覆盖层后在这个位置贴图，剪贴板不动。
- `CaptureService`：窗口列表改用 `WindowHitTester.removingOwnWindows`（自己的贴图留作遮挡），旧注释改成第 20 条的结论。

- [ ] **Step 1：贴图浮窗**

新建 `App/Sources/Pin/PinWindow.swift`：

```swift
import AppKit
import GlimpseCore

/// One pinned screenshot (design doc §3.6): always on top, borderless, with a shadow. Drag to move,
/// scroll (or pinch) to zoom about the mouse, double-click to close; the right-click menu copies, saves, sets the
/// opacity or closes. Holds only the composed image, in memory (§1: nothing is written to disk).
/// A non-activating panel that never takes the keyboard, so pinning leaves the active app alone.
final class PinWindow: NSPanel {
    enum Command {
        case copy, save, close
    }

    let image: CGImage
    let scale: CGFloat
    /// What the controller does for a menu item or a double click.
    var onCommand: ((PinWindow, Command) -> Void)?

    /// The image's size at 100%, in points.
    private var imageSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
    private var zoomFactor: CGFloat = 1

    /// `frame` is where the selection was, in AppKit global coordinates: the pin appears right on top of it.
    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(contentRect: CGRect(origin: frame.origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // The floating level: above normal windows, below the overlay (.screenSaver), so a capture covers it.
        // It is also below the Dock and the menu bar; accepted, a pin dragged there just slides under them.
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinImageView(image: image)
        view.attach(to: self)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Scroll wheel or two-finger scroll: zoom about the mouse.
    func zoom(by event: NSEvent) {
        // Wheel away from the user zooms in, whatever the natural-scrolling setting.
        // Momentum after a flick would keep zooming once the fingers are off the trackpad.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard delta != 0 else { return }
        setZoomFactor(PinZoom.zoom(zoomFactor, scrolledBy: delta, precise: event.hasPreciseScrollingDeltas,
                                   imageSize: imageSize))
    }

    /// Trackpad pinch: zoom about the mouse too.
    func zoom(byMagnification event: NSEvent) {
        setZoomFactor(PinZoom.zoom(zoomFactor, magnifiedBy: event.magnification, imageSize: imageSize))
    }

    private func setZoomFactor(_ next: CGFloat) {
        guard next != zoomFactor else { return }
        zoomFactor = next
        setFrame(PinZoom.frame(frame, zoomedTo: zoomFactor, imageSize: imageSize, anchor: NSEvent.mouseLocation,
                               backingScale: backingScaleFactor), display: true)
    }
}

/// Shows the image scaled to the window and turns mouse input into window commands.
private final class PinImageView: NSView {
    private weak var pin: PinWindow?

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func attach(to pin: PinWindow) {
        self.pin = pin
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let pin else { return }
        if event.clickCount == 2 {
            pin.onCommand?(pin, .close)
        } else {
            pin.performDrag(with: event) // the system moves the window until the mouse is released
        }
    }

    override func scrollWheel(with event: NSEvent) {
        pin?.zoom(by: event)
    }

    override func magnify(with event: NSEvent) {
        pin?.zoom(byMagnification: event)
    }

    /// AppKit's own right-click path (rightMouseDown, or a control-click, → NSMenu.popUpContextMenu(_:with:for:))
    /// asks for this menu: it opens on the first click even while another app is active, with no
    /// popUp(positioning:at:in:) of our own.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pin else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("复制", .copy))
        menu.addItem(item("保存", .save))
        let opacity = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for percent in [100, 75, 50] {
            let level = NSMenuItem(title: "\(percent)%", action: #selector(opacityPicked(_:)), keyEquivalent: "")
            level.target = self
            level.tag = percent
            level.state = Int((pin.alphaValue * 100).rounded()) == percent ? .on : .off
            levels.addItem(level)
        }
        opacity.submenu = levels
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item("关闭", .close))
        return menu
    }

    private func item(_ title: String, _ command: PinWindow.Command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(commandPicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        return item
    }

    @objc private func commandPicked(_ sender: NSMenuItem) {
        guard let pin, let command = sender.representedObject as? PinWindow.Command else { return }
        pin.onCommand?(pin, command)
    }

    @objc private func opacityPicked(_ sender: NSMenuItem) {
        pin?.alphaValue = CGFloat(sender.tag) / 100
    }
}
```

新建 `App/Sources/Pin/PinWindowController.swift`：

```swift
import AppKit
import GlimpseCore

/// Every pinned screenshot (design doc §3.6); any number at once. A pin lives until it is closed or
/// Glimpse quits.
@MainActor
final class PinWindowController {
    /// Shows a HUD message. The capture session sets it, so a message that arrives while a capture is on
    /// screen waits for it to close instead of being captured or covered.
    var onHUD: ((HUDMessage, NSScreen?) -> Void)?

    private let settings: SettingsStore
    private var pins: [PinWindow] = []
    private var screenObserver: NSObjectProtocol?

    init(settings: SettingsStore) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringBackStrandedPins() }
        }
    }

    /// Pins `image` at `frame` (AppKit global coordinates: where the selection was).
    func pin(_ image: CGImage, scale: CGFloat, at frame: CGRect) {
        let pin = PinWindow(image: image, scale: scale, frame: frame)
        pin.onCommand = { [weak self] pin, command in self?.perform(command, on: pin) }
        pins.append(pin)
        pin.orderFrontRegardless() // never key: the active app keeps the keyboard
    }

    private func perform(_ command: PinWindow.Command, on pin: PinWindow) {
        switch command {
        case .copy:
            OutputService.copy(pin.image, scale: pin.scale)
            onHUD?(.copied, pin.screen)
        case .save:
            save(pin)
        case .close:
            // This runs inside the pin's sendEvent (double click or menu item): keep it alive until the next
            // runloop turn so AppKit never returns into a freed window.
            pin.close()
            pins.removeAll { $0 === pin }
            DispatchQueue.main.async { _ = pin }
        }
    }

    /// A display was unplugged or rearranged: a pin that is now on no screen moves to the middle of the main
    /// screen (the top-left corner when it is larger), so it can be reached and closed again.
    private func bringBackStrandedPins() {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return } // the menu-bar screen
        for pin in pins where !NSScreen.screens.contains(where: { $0.frame.intersects(pin.frame) }) {
            let size = pin.frame.size
            let origin = CGPoint(x: max(visible.minX, visible.midX - size.width / 2).rounded(),
                                 y: min(visible.maxY - size.height, visible.midY - size.height / 2).rounded())
            pin.setFrameOrigin(origin)
        }
    }

    /// Like ⌘S in the overlay: copies too, so a failed save still leaves the image on the clipboard.
    private func save(_ pin: PinWindow) {
        let image = pin.image, scale = pin.scale, screen = pin.screen
        OutputService.copy(image, scale: scale)
        let directory = settings.saveDirectory
        let folder = FileManager.default.displayName(atPath: directory.path)
        let date = Date()
        Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    _ = try OutputService.savePNG(image, scale: scale, to: directory, date: date)
                    return true
                } catch {
                    NSLog("Glimpse: saving a pin failed, image is on the clipboard: \(error)")
                    return false
                }
            }.value
            self?.onHUD?(saved ? .saved(folder: folder) : .saveFailed, screen)
        }
    }
}
```

- [ ] **Step 2：工具栏按钮**

按顺序做下面 6 处替换：

（1）`App/Sources/Toolbar/ToolbarItem.swift`：把

```swift
/// One toolbar button. Order and grouping follow design doc §3.3.
enum ToolbarItem: Hashable {
    case tool(Tool)
    case undo, redo
    case recognizeText, save
```

替换为

```swift
/// One toolbar button. Order and grouping follow design doc §3.3.
enum ToolbarItem: Hashable {
    case tool(Tool)
    case undo, redo
    case recognizeText, pin, save
```

（2）`App/Sources/Toolbar/ToolbarItem.swift`：把

```swift
        [.recognizeText, .save],
```

替换为

```swift
        [.recognizeText, .pin, .save],
```

（3）`App/Sources/Toolbar/ToolbarItem.swift`：把

```swift
        case .recognizeText: "text.viewfinder"
```

替换为

```swift
        case .recognizeText: "text.viewfinder"
        case .pin: "pin"
```

（4）`App/Sources/Toolbar/ToolbarItem.swift`：把

```swift
        case .recognizeText: "识别文字"
```

替换为

```swift
        case .recognizeText: "识别文字"
        case .pin: "贴图"
```

（5）`App/Sources/Toolbar/ToolbarItem.swift`：把

```swift
        case .recognizeText: nil
```

替换为

```swift
        case .recognizeText, .pin: nil
```

（6）`App/Sources/Overlay/OverlayContentView.swift`：把

```swift
        case .recognizeText:
            selectionView.finish(.recognizeText)
```

替换为

```swift
        case .recognizeText:
            selectionView.finish(.recognizeText)
        case .pin:
            selectionView.finish(.pin)
```

- [ ] **Step 3：会话、AppDelegate、注释**

按顺序做下面 13 处替换：

（1）`App/Sources/Overlay/SelectionView.swift`：把

```swift
    /// The selection's frozen pixels, without annotations, go to text recognition (design doc §3.5).
    case recognizeText
}
```

替换为

```swift
    /// The selection's frozen pixels, without annotations, go to text recognition (design doc §3.5).
    case recognizeText
    /// The composed image is pinned where the selection was (design doc §3.6).
    case pin
}
```

（2）`App/Sources/Overlay/SelectionView.swift`：把

```swift
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction)
```

替换为

```swift
    /// `frame` is where the image was on screen, in AppKit global coordinates (a pin appears right there).
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, frame: CGRect,
                       action: OverlayFinishAction)
```

（3）`App/Sources/Overlay/SelectionView.swift`：把

```swift
        delegate?.selectionView(self, didFinishWith: image, scale: captured.info.scale, action: action)
```

替换为

```swift
        // The image covers the whole pixels around the selection, so its frame is taken from those pixels,
        // not from the selection: a pin then sits exactly on the pixels it shows.
        let scale = captured.info.scale
        let local = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                           width: pixels.width / scale, height: pixels.height / scale)
        delegate?.selectionView(self, didFinishWith: image, scale: scale,
                                frame: CoordinateSpace.appKitRect(fromLocal: local, in: captured.info), action: action)
```

（4）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    private let ocr: OCRController
```

替换为

```swift
    private let ocr: OCRController
    private let pins: PinWindowController
```

（5）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    init(settings: SettingsStore, ocr: OCRController) {
        self.settings = settings
        self.ocr = ocr
    }
```

替换为

```swift
    init(settings: SettingsStore, ocr: OCRController, pins: PinWindowController) {
        self.settings = settings
        self.ocr = ocr
        self.pins = pins
        pins.onHUD = { [weak self] message, screen in self?.showHUD(message, on: screen) }
    }

    /// A HUD message from outside the overlay (the pins' copy and save): shown now, or, while a capture is on
    /// screen, once it closes (pendingHUD), so it is neither captured nor covered by the overlay.
    func showHUD(_ message: HUDMessage, on screen: NSScreen?) {
        if isRunning {
            pendingHUD = (message, screen)
        } else {
            hud.show(message, on: screen)
        }
    }
```

（6）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, action: OverlayFinishAction) {
        let capturedAt = self.capturedAt // close() clears it
```

替换为

```swift
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, frame: CGRect,
                       action: OverlayFinishAction) {
        let capturedAt = self.capturedAt // close() clears it
```

（7）`App/Sources/Overlay/CaptureSessionController.swift`：把

```swift
            ocr.recognize(image, on: screen) // only the text goes to the clipboard (design doc §3.5)
            return
        }
```

替换为

```swift
            ocr.recognize(image, on: screen) // only the text goes to the clipboard (design doc §3.5)
            return
        }
        if action == .pin {
            pins.pin(image, scale: scale, at: frame) // nothing on the clipboard (§3.2)
            return
        }
```

（8）`App/Sources/AppDelegate.swift`：把

```swift
        session = CaptureSessionController(settings: settings, ocr: OCRController())
```

替换为

```swift
        session = CaptureSessionController(settings: settings, ocr: OCRController(),
                                           pins: PinWindowController(settings: settings))
```

（9）`App/Sources/Services/CaptureService.swift`：把

```swift
            // Nothing excluded: our status-bar item belongs to this process, so excluding the app
            // would drop it from the image. Pin windows (P3) will need explicit exclusion then.
```

替换为

```swift
            // Nothing excluded: our status-bar item belongs to this process, so excluding the app
            // would drop it from the image. Pinned screenshots stay in it too, like any window on screen
            // (design doc §3.6); the window list keeps them only as occluders, so they are never snapped to.
```

（10）`App/Sources/Services/CaptureService.swift`：把

```swift
    /// Front-to-back, CG global frames, excluding Glimpse's own windows.
```

替换为

```swift
    /// Front-to-back, CG global frames; of Glimpse's own windows only the occluders (pins, panels) are kept.
```

（11）`App/Sources/Services/CaptureService.swift`：把

```swift
    /// menu bar, floating panels); it only ever returns layer 0. Fully transparent windows (alpha 0),
    /// our own windows and anything at or above the screen-saver level (cursor, shielding, our overlay
    /// level) are dropped here so invisible full-screen system windows cannot block highlighting.
```

替换为

```swift
    /// menu bar, floating panels); it only ever returns layer 0. Fully transparent windows (alpha 0)
    /// and anything at or above the screen-saver level (cursor, shielding, our overlay level) are dropped
    /// here so invisible full-screen system windows cannot block highlighting. Of our own windows only
    /// those above layer 0 stay, as occluders: a pinned screenshot hides the window behind it.
```

（12）`App/Sources/Services/CaptureService.swift`：把

```swift
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
```

替换为

```swift
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
```

（13）`App/Sources/Services/CaptureService.swift`：把

```swift
        return WindowHitTester.removingDisplayCoveringOverlays(all, displayFrames: displayFrames)
```

替换为

```swift
        return WindowHitTester.removingDisplayCoveringOverlays(WindowHitTester.removingOwnWindows(all, ownPID: ownPID),
                                                               displayFrames: displayFrames)
```

- [ ] **Step 4：编译**

Run: `cd . && grep -rn "HUDController()" App/Sources`
Expected: 只有 `App/Sources/Overlay/CaptureSessionController.swift` 一处（HUD 仍由会话持有）

Run: `cd . && scripts/build.sh`
Expected: 没有编译错误、没有新增警告，最后一行输出 app 路径

Run: `cd Core && swift test`
Expected: `Test run with 197 tests in 29 suites passed`

- [ ] **Step 5：手动检查（用户在真机上做）**

Run: `cd . && scripts/run.sh`，按引导窗口重新授权。本次一并检查批次 C 的识别文字和批次 D 的贴图。

**识别文字**（准备一个有中英混排、多行文字的窗口，如本计划文件在编辑器里打开）：

- 工具栏：… │ 撤销 重做 │ 识别文字 保存 │ ✕ ✓；悬停「识别文字」提示只有名称
- 框选一段中英混排文字，先在上面画个矩形，再点「识别文字」：覆盖层关闭，屏幕中央出现玻璃面板「识别文字 正在识别…」，随后显示文字和「已复制」；到别的应用 ⌘V 粘贴出的是这段文字（不是图片）；画的矩形没有影响识别
- 文字顺序：从上到下、行内从左到右；繁体中文也能识别
- 在面板里改几个字：「已复制」消失；点「复制」：「已复制」回来，粘贴出的是改过的文字；面板里中文输入法能用，⌘A / ⌘C / ⌘V / ⌘Z 有效
- Esc、⌘W、✕ 都能关闭面板；关闭后原来的应用仍有键盘焦点（直接打字能进原来的输入框）；面板打开时原来的应用也没有失去「活跃」状态（菜单栏应用名不变）
- 框选一块没有文字的区域识别：面板显示「未识别到文字」，剪贴板不变
- 菜单「识别文字」：出现覆盖层；拖出一个区域松手：不出工具栏，直接出结果面板；再试单击一个窗口、按空格（整屏）、悬停窗口按 Enter：都直接识别；Esc 退出不出面板
- 设置里给识别文字设 ⌃⌥O：菜单「识别文字」旁显示 ⌃⌥O；按 ⌃⌥O 进入识别（批次 A 的提示音没有了）
- 识别中立刻再识别一次：面板只显示后一次的结果
- 第二次识别后在面板里按 ⌘Z：不崩溃、不会撤回到上一次的文字；「正在识别…」「未识别到文字」时文字框不能输入
- 把面板拖到一边，再识别一次：面板留在拖到的位置
- 面板开着时按 ⇧⌘A：面板先收起，冻结画面里没有它
- 截图、保存、贴色等原有功能照常
- 打开结果面板时 Dock 里**不**出现 Glimpse 图标；面板打开时切到别的应用，面板仍浮在上面（`.floating`）：请判断这样是否合适
- 识别刚开始就按 Esc 关掉面板：等几秒，剪贴板没有被识别结果覆盖

**贴图：**

- 工具栏第三组：识别文字 贴图 保存；悬停「贴图」提示只有名称
- 框选一块，画个箭头，点「贴图」：覆盖层关闭，同一位置出现一模一样的图（含箭头），带阴影、无边框，与原画面严丝合缝（不偏一像素；有 1.5 倍等非整数缩放的屏幕时也试一次）；100% 时清晰不发虚；剪贴板没变（⌘V 粘贴的还是之前的内容）
- 拖动贴图：跟手移动，松开即停
- 鼠标滚轮向前推：以鼠标为中心放大，往回滚缩小；触控板双指滚动、双指捏合同样以鼠标为中心缩放；放到很大停在 500%（整屏大小的截图更早停住，长边不超过 10000pt），缩到很小停在约 24pt 高 / 宽（大截图停在 10%）；缩放经过 100% 时停在 100%，停住后图像清晰（与刚贴出时一样）；触控板双指快速一甩松手，手离开后不再继续缩放；系统「自然滚动」开关切换后方向不变
- 双击贴图：关闭
- 右键：别的应用是活跃应用时，第一次右键就弹出菜单（不用点两次），⌃ 点按也能弹出；菜单是系统菜单（macOS 26 上是液态玻璃）：复制 / 保存 / 透明度 ▸ / ─ / 关闭；「复制」→ HUD「已复制到剪贴板」，⌘V 粘贴出带箭头的图；「保存」→ HUD「已保存到「下载」」，下载文件夹多一个 PNG，剪贴板里也有；「透明度 ▸ 50%」→ 变半透明，再打开菜单 50% 前有勾；「关闭」→ 关闭
- 贴三张：同时存在，各自独立拖动、缩放、关闭
- 在 TextEdit 里打字时点一下 / 拖一下贴图：TextEdit 仍然是活跃应用，接着打字能输入；切到别的应用，贴图仍在最上层
- 切换桌面空间、进入全屏应用：贴图仍显示
- 有贴图时按 ⇧⌘A：冻结画面里能看到贴图；鼠标移到贴图上，高亮的是整屏：既不吸附贴图本身，也不吸附被贴图挡住的窗口；鼠标移出贴图，照常吸附下面的窗口；识别结果面板开着时同理
- 两块屏幕时：把贴图拖到另一块（不同缩放倍数）上，大小按点保持，内容不错位；贴图留在外接屏上时拔掉外接屏：贴图回到主屏中间，还能拖动、关闭
- 把贴图拖到 Dock 或菜单栏的位置：被它们盖在下面（`.floating` 层级，接受）
- 正在截图（覆盖层在屏幕上）时，之前点的贴图「保存」才完成：提示不出现在覆盖层里，关掉覆盖层后才出现
- 识别文字、保存、复制等照常

- [ ] **Step 6：停下，不 commit**

**批次 C + D 检查点：** 用户确认识别文字和贴图，再进入收尾。

---

## 批次 E：收尾

### Task 12：收尾验证

- [ ] **Step 1：全部单元测试**

Run: `cd Core && swift test`
Expected: `Test run with 197 tests in 29 suites passed`

- [ ] **Step 2：干净编译**

Run: `cd . && rm -rf build && scripts/build.sh`
Expected: 没有错误、没有新增编译警告；最后一行输出 app 路径

- [ ] **Step 3：自查**

Run: `cd . && grep -rn "ScreenRecordingPermission\|requestOrOpenSettings\|(P3)\|P3 adds\|P3 replaces\|P3:\|Task [0-9]\|arrives in" App/Sources Core/Sources`
Expected: 没有输出（「P3 displays」「P3 stays P3」说的是 Display P3 色彩空间，不在匹配范围内；如有其他残留，按当前行为改写注释）

Run: `cd . && grep -rn "controlAccentColor" App/Sources`
Expected: 只有 `App/Sources/Material/InterfaceAccent.swift` 和 `App/Sources/Settings/SettingsView.swift`（色点的兜底）

- [ ] **Step 4：同步设计文档**

`docs/superpowers/specs/2026-11-04-glimpse-design.md` 里做下面 10 处替换，把本计划的决定写回设计文档（实施前说明第 10、19、12 / 13、23、6、4、8、24、14 条；若用户评审时否决了第 19 条，跳过（2））。放大镜的文字（§3.2、§4.3）已由放大镜任务更新为 17 × 17、135 × 213、不画中心方框，本计划不用再改：

（1）把

```
点「去授权」时，**先调用一次 `CGRequestScreenCaptureAccess()`**，让 Glimpse 出现在「系统设置 → 隐私与安全性 → 屏幕录制」列表里（应用从没申请过的话，列表里没有它，用户只能手动点「+」添加），再打开系统设置的这个页面。
```

替换为

```
点「去授权」时，**先调用一次 `CGRequestScreenCaptureAccess()`**，让 Glimpse 出现在「系统设置 → 隐私与安全性 → 屏幕录制」列表里（应用从没申请过的话，列表里没有它，用户只能手动点「+」添加），再打开系统设置的这个页面。第一次点时系统会弹自己的询问框（框上有「打开系统设置」按钮），这一次不另开系统设置，免得两个窗口叠在一起。
```

（2）把

```
工具栏、颜色栏、尺寸标签、贴图右键菜单、识别结果面板、引导窗口统一使用这一套材质。
```

替换为

```
工具栏、颜色栏、尺寸标签、识别结果面板、引导窗口、HUD 统一使用这一套材质。贴图的右键菜单用系统菜单：macOS 26 的系统菜单本身就是液态玻璃，自绘还要重做键盘导航和子菜单。
```

（3）把

```
3. 「从系统设置回来」以 Glimpse 重新变成活跃应用为准（`NSApplication.didBecomeActiveNotification`）。此时仍检测不到授权 → 引导窗口显示「重新启动 Glimpse」按钮，点击后自动重启应用（启动一个新实例再退出当前实例）；重启后检测到授权就不再显示引导窗口
```

替换为

```
3. 「从系统设置回来」以 Glimpse 重新变成活跃应用为准（`NSApplication.didBecomeActiveNotification`）。此时仍检测不到授权（且之前确实打开过系统设置，只在系统询问框里点了拒绝的不算）→ 引导窗口显示「重新启动 Glimpse」按钮，点击后自动重启应用（起一个子进程，等当前实例退出、再等 0.3 秒后打开应用，最多等 10 秒，当前实例没退出就放弃；不先开新实例，否则新实例注册同一个全局快捷键会和旧实例冲突；子进程起不来时提示「无法自动重启，请手动退出后重新打开」）；重启后检测到授权就不再显示引导窗口
```

（4）把

```
| `PermissionService` | 申请屏幕录制授权（让应用出现在系统设置列表里）、检查 / 轮询授权状态、重启应用 | CoreGraphics |
```

替换为

```
| `PermissionService` | 申请屏幕录制授权（让应用出现在系统设置列表里）、检查 / 轮询授权状态、重启应用（等当前进程退出后再打开） | CoreGraphics |
```

（5）把

```
菜单栏常驻图标，不占 Dock。菜单只有：截图、识别文字、设置…、退出。
```

替换为

```
菜单栏常驻图标，平时不占 Dock；设置窗口、引导窗口打开时显示 Dock 图标（被别的窗口挡住时能用 Dock 或 ⌘Tab 切回来），都关闭后消失，键盘回到之前的应用。菜单只有：截图、识别文字、设置…、退出。
```

（6）把

```
| 界面强调色 | 跟随系统（可选：跟随系统 / 几种预设色）。作用于选区边框、手柄、选中按钮、✓ 等界面强调色；不影响标注颜色 |
```

替换为

```
| 界面强调色 | 跟随系统（可选：跟随系统 / 蓝、紫、粉、红、橙、绿、石墨；不放黄色：选中按钮是强调色底 + 白色图标，黄底白字看不清）。作用于选区边框、手柄、选中按钮、✓ 等界面强调色；不影响标注颜色 |
```

（7）把

```
另有「关于」。只有全局快捷键可改；截图界面里的单键（R / O / A / P / T / M / N、C 等）固定，不做成设置项（用户选定）。其余行为（PNG 格式、保存时同时复制、截图不含鼠标指针、6 个预设色、日夜间跟随系统等）不做成设置项。
```

替换为

```
另有「关于」。全局快捷键必须带 ⌘、⌃ 或 ⌥（F 键除外）；系统常用组合（只带 ⌘ 的 Q / W / C / V / X / Z / A / S / H / M / Tab / 空格 / 逗号、⇧⌘Z，以及切换输入法的 ⌃空格、⌃⌥空格）和只带 ⌥ 的字符键（会挡住 ⌥E → ´ 这类特殊字符的输入，只用 ⌥ 时只能配 F 键或空格）不收。只有全局快捷键可改；截图界面里的单键（R / O / A / P / T / M / N、C 等）固定，不做成设置项（用户选定）。其余行为（PNG 格式、保存时同时复制、截图不含鼠标指针、6 个预设色、日夜间跟随系统等）不做成设置项。
```

（8）把

```
- 开机自动启动开关（用放进 /Applications 的那份 .app 测，重启电脑验证；从 Xcode 的 DerivedData 运行时路径会变，结果不可靠）
```

替换为

```
- 开机自动启动开关（用放进 /Applications 的那份 .app 测，重启电脑验证；从 Xcode 的 DerivedData 运行时路径会变，结果不可靠）；Debug 编译不会自动登记登录项，默认开启只在 Release 版第一次运行时生效
```

（9）把

```
两个入口：截图工具栏的「识别文字」按钮（识别当前选区），或菜单栏菜单「识别文字」/ 用户自设的快捷键。后者选区一确定就直接识别，不进入编辑阶段。识别语言显式设为 `["zh-Hans", "zh-Hant", "en-US"]`，accurate 模式，开启 `usesLanguageCorrection`（macOS 14 起都支持）。结果按阅读顺序拼接，自动复制到剪贴板，同时弹出结果面板：文字可以修改，有「复制」按钮，Esc 关闭。没识别到文字时提示「未识别到文字」。
```

替换为

```
两个入口：截图工具栏的「识别文字」按钮（识别当前选区），或菜单栏菜单「识别文字」/ 用户自设的快捷键。后者选区一确定就直接识别，不进入编辑阶段；覆盖层外观与普通截图相同，不加「识别模式」提示。识别语言显式设为 `["zh-Hans", "zh-Hant", "en-US"]`，accurate 模式，开启 `usesLanguageCorrection`（macOS 14 起都支持）。结果按阅读顺序拼接，自动复制到剪贴板，同时弹出结果面板：文字可以修改，有「复制」按钮，Esc 关闭。没识别到文字时提示「未识别到文字」。
```
（10）把

```
| 没有屏幕录制权限 / 权限被撤销 | 不弹覆盖层，打开引导窗口（见 3.8）；菜单栏图标显示提示标记 |
```

替换为

```
| 没有屏幕录制权限 / 权限被撤销 | 不弹覆盖层，打开引导窗口（见 3.8）；菜单栏图标显示提示标记 |
| 系统设置里显示已授权，但截图被系统拒绝（ScreenCaptureKit 报 `userDeclined`） | 不弹「截图失败」，引导窗口直接提示重新启动（若仍不行，在系统设置里关掉再打开开关）；这时检测结果一直是「已授权」，窗口不会自动关闭；菜单栏图标显示提示标记，直到下一次截图成功 |
```

- [ ] **Step 5：交给用户做完整验收**

由用户按 Task 4、6、9、11 的手动检查清单走一遍，并补充（§8 手动验收清单）：
- **开机自动启动**（Release 版，实施前说明第 8 条）：
  1. 先确认「系统设置 → 通用 → 登录项」里没有指向 `build/` 的 Glimpse（有的话在开发版设置里把开关关掉），退出开发版
  2. 编 Release 版并签名：`cd . && xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet build && codesign --force --sign - build/Build/Products/Release/Glimpse.app`
  3. 清掉默认值标记，让 Release 版像第一次运行：`defaults delete com.anglerdw.glimpse loginItemDefaultApplied`（没有这个键时报错可忽略）
  4. `cp -R build/Build/Products/Release/Glimpse.app /Applications/` 后从 /Applications 打开，重新授予屏幕录制权限：设置里「开机自动启动」已经是开的，登录项里的 Glimpse 指向 /Applications
  5. 重启电脑：Glimpse 自动启动（菜单栏有图标）；关掉开关再重启：不启动
  6. 打开开关后，在「系统设置 → 通用 → 登录项」里把 Glimpse 关掉，回到 Glimpse 设置：开关是关的，下面立即出现红字「需要在「系统设置 → 通用 → 登录项」里允许 Glimpse」和「打开登录项设置」按钮。再在 Glimpse 里打开开关：开关弹回关闭，红字「需要在「系统设置 → 通用 → 登录项」里允许 Glimpse」和「打开登录项设置」按钮；点按钮去系统设置里打开 Glimpse，回到 Glimpse：开关变成打开，红字和按钮消失
  7. 验完删除 /Applications 里的副本，回到开发版
- 首次启动授权流程，包括「需要重启才生效」和授权被撤销后的表现（批次 B 的清单）
- 两块不同缩放倍数的屏幕：识别文字面板出现在选区所在屏；贴图原位出现
- 日夜间各走一遍：设置窗口、引导窗口、识别结果面板、贴图阴影；macOS 14 / 15 机器（如有）：引导窗口和结果面板是毛玻璃
- 多个贴图浮窗同时存在

- [ ] **Step 6：停下，不 commit**

汇报内容：改了哪些文件、测试结果（197 tests in 29 suites）、编译结果、需要用户在真机上确认的清单、执行中发现的问题。

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| `SMAppService.mainApp.register()` 对 ad-hoc 签名或 `build/` 下的开发版失败 / 要求批准 | 开机自动启动开关打不开 | 失败时开关回到原状并显示原因（§6）；正式验证用 /Applications 里的副本（Task 12） |
| 录制快捷键时窗口失去焦点但录制状态残留 | 全局快捷键一直被暂停 | 窗口 `close()` / `resignKey()` 都会结束录制（交出第一响应者），录制按钮离开窗口也结束 |
| `NSHostingController` 里的分组表单高度不合适 | 底部留白或需要滚动 | 固定 480 × 600，内容超出时表单自己滚动；真机看后可只改 `SettingsView` 里的 `.frame` |
| macOS 15+ 打开屏幕录制开关后系统自己弹「退出并重新打开」 | 与「重新启动 Glimpse」按钮重复 | 两条路都能用：系统重启后检测到授权就不再显示引导窗口 |
| `CGPreflightScreenCaptureAccess()` 授权后在当前进程里一直返回 false | 引导窗口不自动关 | 这正是「重新启动 Glimpse」的用途（§3.8 第 3 步） |
| 重启脚本的子进程随父进程一起被结束 | 点「重新启动」后应用没有回来 | `Process` 起的子进程不随 `NSApp.terminate` 结束；万一没回来，用户从启动台再打开即可，Task 6 手动检查确认 |
| 非激活面板里的输入法、⌘ 快捷键 | 结果面板不能编辑 | 与 P2 文字框同样的做法（面板可成为 key，文字框自己处理编辑快捷键），P2 已在真机验证 |
| 菜单栏应用在非活跃状态下弹贴图右键菜单 | 菜单不出现或需要点两次 | `menu(for:)` 走 AppKit 自己的右键路径（`rightMouseDown` / ⌃ 点按 → `NSMenu.popUpContextMenu(_:with:for:)`，专为从事件弹出的右键菜单设计），不依赖应用激活；不自己调 `popUp(positioning:at:in:)`。Task 11 手动检查确认第一次右键就弹出 |
| 选区内容很多时 Vision 耗时 | 面板「正在识别…」停留较久 | 识别在后台线程，面板先出现；新的识别或新的截图会取消旧的任务，并用 `request.cancel()` 让 Vision 停下 |
| HUD / 放大镜任务后续又改了相关文件 | 本计划的替换原文对不上 | 执行每处替换前先确认原文仍只出现一次；对不上时按当前代码的同一位置改，并在汇报里说明 |
| 切到 `.regular` 时没有主菜单 | 菜单栏左侧只有应用名、没有菜单项 | 接受（第 2、23 条）；设置窗口的 ⌘W / ⌘Q 由窗口自己处理 |
| 从全局快捷键打开引导窗口时激活被系统拒绝 | 窗口在前但不是活跃应用 | 先 `orderFrontRegardless` + `makeKey`，窗口可见可点；点一下即激活 |

## 真机反馈修正（2026-11-05 晚）

- 提取文字结果面板改为贴着选区出现（新增 Core `OCRPanelLayout`：下方右对齐 → 上方 → 选区内，挪进可见区域、离边 8pt；`OCRController.recognize(_:selection:on:)` 从会话拿选区的 AppKit 屏幕坐标），去掉「首次居中、之后记住拖动位置」；菜单 / 快捷键入口同一条路径；`OCRPanelLayoutTests` 7 条。
- 功能改名「识别文字」→「提取文字」：工具栏提示 / 无障碍名、菜单栏、设置行、结果面板标题与状态（正在提取… / 未提取到文字 / 提取失败）、设置「关于」说明、设计文档；标识符不变。
- 产品名只显示「Glimpse」：设置「关于」去掉「· 瞥」（CFBundleDisplayName 本来就是 Glimpse，窗口标题「Glimpse 设置」不变）。
- 版本显示改为「版本 0.1.0（Build 1）」，「Glimpse」下面一行次要色版权；`project.yml` 增加 `NSHumanReadableCopyright: © 2026 AnglerDW`。
- HUD 从下三分之一移到可见区域正中（`HUDLayout` + `HUDTests` 同步）。
- 界面强调色也作为 Glimpse 自己窗口的主题色：设置表单 `.tint`（跟随系统时不设）、快捷键录制按钮录制中底色、引导窗口「开机自动启动」改为 SwiftUI 小号开关并跟随强调色、图标与「去授权」随改动重绘、结果面板「复制」按钮；都随 `AccentObservation` / 模型变化即时更新（新增 `AccentColor.tint`）。
- 贴图悬停时左上角（内缩 6pt）显示 20pt 圆形玻璃 ✕，移开隐藏，第一下点击生效、不抢焦点，走与双击相同的关闭路径；任一边小于 44pt 的贴图不显示（新增 Core `PinCloseButtonLayout` + 3 条测试）。
- 评审修正：截图开始前隐藏所有贴图 ✕（`PinWindowController.setCloseButtonsSuppressed(_:)`，有 ✕ 在屏上时与 HUD 一样等一个 runloop 再截图；截图结束、显示器变化把贴图挪回时按鼠标位置重新显示），避免鼠标停在贴图上按快捷键时 ✕ 被截进冻结画面。
- 评审修正：引导窗口只有当前主要按钮（回车对应的「去授权」/「重新启动 Glimpse」）填强调色，`showRestart` 和强调色变化共用 `applyAccent()`；结果面板「复制」只在可用时填色（`refreshCopyButton()`）。
- 评审修正：填强调色的文字按钮（复制、去授权 / 重新启动、录制中的快捷键按钮）按 WCAG 对比度选字色：白字低于 3:1 用黑字（Core `RGBA.relativeLuminance` / `contrastRatio(with:)` / `filledButtonPrefersDarkTitle`，App `NSColor.glimpseAccentTitle` + `NSButton.applyAccentFill(_:)`）；`AccentContrastTests` 3 条。
- 评审修正：贴图 ✕ 只在圆内接收点击；跟踪区域只加一次（`.inVisibleRect`），不再移除别的跟踪区域；14 / 15 上 ✕ 用紧凑投影（`MaterialView(compactShadow:)`）；设计文档注明 75% / 50% 透明度下 ✕ 玻璃变平。
- 评审修正：`OCRPanelLayoutTests` 增加选区伸进菜单栏的两条（下方仍放得下 / 上下都放不下落到选区内）。

### 真机检查清单（本批）

1. 结果面板位置：屏幕中部选区 → 下方右对齐；贴底选区 → 上方；整屏 / 上下都放不下 → 选区右下角内侧；贴左右边的窄选区 → 被挪进屏幕、离边 8pt；伸进菜单栏的选区；副屏（含负坐标排列）；菜单和快捷键入口同样；拖开后再提取一次 → 回到新选区旁。
2. 改名：工具栏提示、菜单栏、设置快捷键行、面板标题和状态（正在提取… / 未提取到文字 / 提取失败）。
3. 设置「关于」：「Glimpse」+ 版权一行 + 「版本 0.1.0（Build 1）」。
4. HUD（复制、保存、保存失败、取色、贴图复制 / 保存）出现在屏幕可见区域正中。
5. 7 种强调色 + 跟随系统，各在日间 / 夜间：设置窗口开关、录制中的快捷键按钮（底色、文字看得清）、引导窗口图标 / 主要按钮 / 开关（切换「重新启动」为主要按钮后填色跟着换）、结果面板「复制」（有文字时填色、空时不填）；橙、绿、夜间石墨上应是黑字，其余白字；设置开着时切换强调色立即生效；跟随系统时在系统设置换强调色也跟上。
6. 贴图 ✕：悬停出现、移开消失；贴图刚出现在鼠标下时立刻有 ✕；别的应用在前台时第一下点击就关闭且前台应用不失焦；在 ✕ 外的角上按下仍能拖动；缩放后 ✕ 跟着左上角；任一边 < 44pt 不出现；75% / 50% 透明度下仍看得清；浅色 / 深色图片、日夜间都看得清；14 / 15 上 ✕ 的投影不脏。
7. 鼠标停在贴图上（✕ 显示中）按截图 / 提取文字快捷键：冻结画面里没有 ✕；截图结束后鼠标仍在贴图上则 ✕ 重新出现。
