# Icon Composer 分层

macOS 26 的液态玻璃图标用 Xcode 26 自带的 Icon Composer（`Xcode.app/Contents/Applications/Icon Composer.app`）做：新建 macOS 图标工程，按下面顺序把三个 SVG 拖进去，材质都选「玻璃」，导出 `Glimpse.icon` 放到 `App/Resources/`。

| 顺序（下 → 上） | 文件 | 说明 |
|---|---|---|
| 背景 | `background.svg` | 蓝色渐变，满幅；Icon Composer 自己加圆角 |
| 第 1 层 | `brackets.svg` | 四个取景角，白色；玻璃材质给厚度、顶光和投影 |
| 第 2 层 | `window.svg` | 磨砂窗口 + 三个按钮 + 文字行；玻璃材质，透明度 0.85 左右 |

深色、着色、透明三种外观由 Icon Composer 从这三层自动生成，不用另画。
macOS 14 / 15 用的是 `../AppIcon.svg` 渲染出的 `AppIcon.appiconset`（`scripts/render-app-icon.sh`）。
