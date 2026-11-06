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
