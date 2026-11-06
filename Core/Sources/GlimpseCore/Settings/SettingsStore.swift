import Foundation

/// A global shortcut in Carbon terms: virtual key code + Carbon modifier flags
/// (cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘A
    public static let defaultScreenshot = KeyCombo(keyCode: 0, modifiers: KeyCombo.command | KeyCombo.shift)
    /// ⌃O (kVK_ANSI_O = 31): 提取文字, the same as iShot.
    public static let defaultOCR = KeyCombo(keyCode: 31, modifiers: KeyCombo.control)
}

// Safe: the only state is a `UserDefaults`, which is thread-safe.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    private enum Key {
        static let screenshotHotkey = "screenshotHotkey"
        static let ocrHotkey = "ocrHotkey"
        static let saveDirectory = "saveDirectory"
        static let accentColor = "accentColor"
        static let loginItemDefaultApplied = "loginItemDefaultApplied"
        static let interfaceLanguage = "interfaceLanguage"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` means the user cleared the shortcut.
    public var screenshotHotkey: KeyCombo? {
        get { hotkey(forKey: Key.screenshotHotkey, default: .defaultScreenshot) }
        set { setHotkey(newValue, forKey: Key.screenshotHotkey) }
    }

    /// ⌃O until chosen (design doc §3.1); `nil` once the user cleared it. Text recognition also goes through
    /// the toolbar and the menu.
    public var ocrHotkey: KeyCombo? {
        get { hotkey(forKey: Key.ocrHotkey, default: .defaultOCR) }
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

    /// The interface language (design doc §3.9): Glimpse's own record of the choice, which the settings page
    /// shows; the app mirrors it into `AppleLanguages`, which is what actually switches the language at the next
    /// launch. Unset, or a code this version does not know, follows the system; choosing `.system` removes the key.
    public var interfaceLanguage: InterfaceLanguage {
        get { defaults.string(forKey: Key.interfaceLanguage).flatMap(InterfaceLanguage.init(rawValue:)) ?? .system }
        set {
            if newValue == .system {
                defaults.removeObject(forKey: Key.interfaceLanguage)
            } else {
                defaults.set(newValue.rawValue, forKey: Key.interfaceLanguage)
            }
        }
    }

    /// Launch at login is recommended on at first onboarding (design doc §3.8, §3.9), but never registered
    /// without the user: the onboarding switch shows on until this is set. The system keeps the real state;
    /// this only records that the user has chosen (flipped a switch, or clicked 「去授权」 with the switch
    /// as shown), so the recommendation is not shown or applied again.
    public var loginItemDefaultApplied: Bool {
        get { defaults.bool(forKey: Key.loginItemDefaultApplied) }
        set { defaults.set(newValue, forKey: Key.loginItemDefaultApplied) }
    }

    public var saveDirectory: URL {
        get { SettingsStore.parseSaveDirectory(defaults.object(forKey: Key.saveDirectory)) ?? SettingsStore.defaultSaveDirectory }
        set { defaults.set(newValue, forKey: Key.saveDirectory) }
    }

    /// Returns an absolute file URL, or `nil` when the stored value is unusable (unset, relative path,
    /// non-file URL, garbage). Unusable values fall back to Downloads. A well-formed absolute path that is
    /// missing or is a file is deliberately kept: saving then fails and takes the copy-only path (spec §6)
    /// instead of silently writing somewhere the user did not choose.
    static func parseSaveDirectory(_ raw: Any?) -> URL? {
        let url: URL?
        switch raw {
        case let string as String:
            if string.hasPrefix("file://") {
                url = URL(string: string)
            } else {
                let path = (string as NSString).expandingTildeInPath
                url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
            }
        case let data as Data:
            url = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data)) as URL?
        default:
            url = nil
        }
        guard let url, url.isFileURL, url.path.hasPrefix("/") else { return nil }
        return url
    }

    public static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
