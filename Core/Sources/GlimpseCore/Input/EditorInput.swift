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
    case editing(tool: Tool?)
    /// Typing into a text annotation: every key except Esc belongs to the text box.
    case typing
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
    public var option: Bool
    public var control: Bool

    public init(key: Key, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

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
        case .typing:
            return input.key == .escape ? .endTyping : .passToTextField
        case .selecting:
            if input.key != .escape && (input.option || input.control) { return .ignore }
            return routeSelecting(input)
        case .editing(let tool):
            if input.key == .escape {
                return tool == nil ? .exit : .deselectTool
            }
            if input.option || input.control { return .ignore }
            return routeEditing(input, currentTool: tool)
        }
    }

    public static func rightClick(phase: EditorPhase) -> EditorAction {
        if case .selecting = phase { return .exit }
        return .reselect
    }

    /// Double-click finishes only with no tool, so rapid clicks with the counter/pen tools never finish by accident.
    public static func doubleClickFinishes(phase: EditorPhase) -> Bool {
        phase == .editing(tool: nil)
    }

    private static func routeSelecting(_ input: KeyInput) -> EditorAction {
        switch input.key {
        case .escape: return .exit
        case .space: return .selectFullScreen
        // Enter / ⌘C / ⌘S act on the current hover target (window or whole screen).
        case .enter: return .finishCopy
        case .character(let c):
            switch (c.lowercased(), input.command) {
            case ("c", false): return .copyColor(input.shift ? .rgb : .hex)
            case ("c", true): return .finishCopy
            case ("s", true): return .save
            default: return .ignore
            }
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
