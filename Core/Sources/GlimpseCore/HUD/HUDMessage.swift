import CoreGraphics
import Foundation

/// What the HUD says after a capture ends (design doc §3.8.1): one SF Symbol and one line of text.
public enum HUDMessage: Equatable, Sendable {
    /// The image went to the clipboard (✓ / Enter / ⌘C / double click).
    case copied
    /// The PNG was written; `folder` is the save folder's display name (「下载」).
    case saved(folder: String)
    /// The PNG could not be written; the image is still on the clipboard (saving copies first).
    case saveFailed
    /// C / ⇧C: the colour value under the cursor went to the clipboard as text.
    case colorCopied(String)
    /// ScreenCaptureKit failed.
    case captureFailed
    /// The display layout changed during the capture; the frozen images no longer match the screens.
    case screensChanged

    public var text: String {
        switch self {
        case .copied:
            String(localized: "已拷贝到剪贴板", bundle: .module, comment: "HUD after copying the capture")
        case .saved(let folder):
            String(localized: "已保存到「\(folder)」", bundle: .module, comment: "HUD after saving; the folder's name")
        case .saveFailed:
            String(localized: "保存失败，图片已拷贝到剪贴板", bundle: .module, comment: "HUD when the PNG could not be written")
        case .colorCopied(let value):
            String(localized: "已拷贝颜色 \(value)", bundle: .module, comment: "HUD after copying a colour value (hex or RGB)")
        case .captureFailed:
            String(localized: "截图失败", bundle: .module, comment: "HUD when the capture failed")
        case .screensChanged:
            String(localized: "显示器变化，已取消截图", bundle: .module, comment: "HUD when displays changed mid-capture")
        }
    }

    /// SF Symbol name shown before the text.
    public var symbolName: String {
        switch self {
        case .copied, .saved: "checkmark.circle.fill"
        case .colorCopied: "eyedropper"
        case .saveFailed, .captureFailed, .screensChanged: "exclamationmark.triangle.fill"
        }
    }

    /// Failures tint their symbol (orange); the rest use the text colour.
    public var isFailure: Bool {
        switch self {
        case .saveFailed, .captureFailed, .screensChanged: true
        case .copied, .saved, .colorCopied: false
        }
    }
}

/// Where the HUD sits (design doc §3.8.1). AppKit screen coordinates (y up).
public enum HUDLayout {
    /// How long a message stays before it fades out.
    public static let displayDuration: Double = 2
    /// Fade in / out; skipped with Reduce Motion.
    public static let fadeDuration: Double = 0.15

    /// Centred in `visibleFrame` (the screen minus menu bar and Dock), both ways.
    /// The origin is on whole points so the glass edge and the text stay crisp.
    public static func frame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let x = (visibleFrame.midX - size.width / 2).rounded()
        let y = (visibleFrame.midY - size.height / 2).rounded()
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
