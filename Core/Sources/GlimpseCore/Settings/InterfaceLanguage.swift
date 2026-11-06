import Foundation

/// The interface language picked in Settings (design doc §3.9): follow the system, or one of the languages the
/// string catalogs ship. Persisted by raw value, which is the catalog's language identifier.
public enum InterfaceLanguage: String, CaseIterable, Codable, Sendable {
    /// No override: macOS picks from the user's languages (English for the ones Glimpse lacks).
    case system
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja, ko, de, fr, es
    case ptBR = "pt-BR"
    case ru, it

    /// The xcstrings language identifier; nil for `.system`.
    public var code: String? {
        self == .system ? nil : rawValue
    }

    /// What `AppleLanguages` in the app's defaults should hold: nil removes the override.
    public var appleLanguagesValue: [String]? {
        code.map { [$0] }
    }

    /// The language's name in that language, never translated (as in System Settings → Language & Region);
    /// nil for `.system`.
    public var nativeName: String? {
        switch self {
        case .system: nil
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .ptBR: "Português (Brasil)"
        case .ru: "Русский"
        case .it: "Italiano"
        }
    }

    /// The menu item: the native name, or the localized 「跟随系统」.
    public var title: String {
        nativeName ?? String(localized: "跟随系统", bundle: .module, comment: "Interface language / accent colour: follow the system")
    }
}
