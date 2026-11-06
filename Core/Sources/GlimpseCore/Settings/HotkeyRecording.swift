import Foundation

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
            case .needsModifier:
                String(localized: "快捷键需要包含 ⌘、⌃ 或 ⌥", bundle: .module, comment: "Shortcut recorder: rejected key")
            case .unsupportedKey:
                String(localized: "不支持这个键，请换一个", bundle: .module, comment: "Shortcut recorder: rejected key")
            case .sameAsOther:
                String(localized: "已用作另一个快捷键，请换一个", bundle: .module, comment: "Shortcut recorder: rejected key")
            case .reserved:
                String(localized: "这是系统常用的快捷键（如拷贝、粘贴、退出），请换一个", bundle: .module,
                       comment: "Shortcut recorder: rejected key")
            case .typesCharacter:
                String(localized: "只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃", bundle: .module,
                       comment: "Shortcut recorder: rejected key")
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
