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
        #expect(HotkeyRecording.Rejection.reserved.message == LocalizedText.current("这是系统常用的快捷键（如拷贝、粘贴、退出），请换一个"))
    }

    /// The default 提取文字 shortcut must pass its own recorder (and show as ⌃O).
    @Test func recordsTheDefaultOCRShortcut() {
        #expect(HotkeyRecording.interpret(keyCode: 31, modifiers: KeyCombo.control, other: .defaultScreenshot)
                == .record(.defaultOCR))
        #expect(KeyCombo.defaultOCR.displayString == "⌃O")
        // ⌃O for the screenshot while 提取文字 still has it: the same combo twice is refused.
        #expect(HotkeyRecording.interpret(keyCode: 31, modifiers: KeyCombo.control, other: .defaultOCR)
                == .reject(.sameAsOther))
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
        #expect(HotkeyRecording.Rejection.typesCharacter.message == LocalizedText.current("只用 ⌥ 时只能配 F 键或空格，请再加 ⌘ 或 ⌃"))
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
