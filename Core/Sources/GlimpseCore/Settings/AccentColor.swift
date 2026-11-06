import Foundation

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
        case .system: String(localized: "跟随系统", bundle: .module, comment: "Interface language / accent colour: follow the system")
        case .blue: String(localized: "蓝色", bundle: .module, comment: "Accent colour")
        case .purple: String(localized: "紫色", bundle: .module, comment: "Accent colour")
        case .pink: String(localized: "粉色", bundle: .module, comment: "Accent colour")
        case .red: String(localized: "红色", bundle: .module, comment: "Accent colour")
        case .orange: String(localized: "橙色", bundle: .module, comment: "Accent colour")
        case .green: String(localized: "绿色", bundle: .module, comment: "Accent colour")
        case .graphite: String(localized: "石墨色", bundle: .module, comment: "Accent colour")
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
