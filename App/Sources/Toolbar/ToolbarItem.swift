import Foundation
import GlimpseCore

/// One toolbar button. Order and grouping follow design doc §3.3.
enum ToolbarItem: Hashable {
    case tool(Tool)
    case undo, redo
    case recognizeText, pin, save
    case cancel, confirm

    /// Separators go between groups.
    static let groups: [[ToolbarItem]] = [
        Tool.allCases.map { .tool($0) },
        [.undo, .redo],
        [.recognizeText, .pin, .save],
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
        case .pin: "pin"
        case .save: "square.and.arrow.down"
        case .cancel: "xmark"
        case .confirm: "checkmark"
        }
    }

    var title: String {
        switch self {
        case .tool(.rectangle): String(localized: "矩形", comment: "Toolbar: tool name")
        case .tool(.ellipse): String(localized: "椭圆", comment: "Toolbar: tool name")
        case .tool(.arrow): String(localized: "箭头", comment: "Toolbar: tool name")
        case .tool(.pen): String(localized: "画笔", comment: "Toolbar: tool name")
        case .tool(.text): String(localized: "文字", comment: "Toolbar: tool name")
        case .tool(.mosaic): String(localized: "马赛克", comment: "Toolbar: tool name")
        case .tool(.counter): String(localized: "序号", comment: "Toolbar: numbered badge tool")
        case .undo: String(localized: "撤销", comment: "Toolbar button")
        case .redo: String(localized: "重做", comment: "Toolbar button")
        case .recognizeText: String(localized: "提取文字", comment: "Shortcut row / menu item / toolbar button / panel title: extract text (OCR)")
        case .pin: String(localized: "贴图", comment: "Toolbar button: pin the capture on screen")
        case .save: String(localized: "保存", comment: "Save (toolbar button / pin menu item)")
        case .cancel: String(localized: "取消", comment: "Toolbar button")
        case .confirm: String(localized: "完成", comment: "Toolbar button: finish and copy")
        }
    }

    /// Shown in the tooltip next to the name (design doc §3.3); nil for buttons without a key in the overlay.
    var shortcut: String? {
        switch self {
        case .tool(let tool): tool.shortcut.uppercased()
        case .undo: "⌘Z"
        case .redo: "⇧⌘Z"
        case .recognizeText, .pin: nil
        case .save: "⌘S"
        case .cancel: "Esc"
        case .confirm: "↩"
        }
    }

    var toolTip: String {
        shortcut.map { String(localized: "\(title)（\($0)）", comment: "Toolbar tooltip: name and key") } ?? title
    }
}
