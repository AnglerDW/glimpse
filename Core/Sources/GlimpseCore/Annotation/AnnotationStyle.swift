import CoreGraphics

/// A colour as sRGB components in 0...1.
public struct RGBA: Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`, opaque.
    public init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Light fills (yellow, white) need dark text on top, e.g. the counter's number.
    /// Orange (luma ≈ 0.64) stays below the threshold and keeps white text (plan decision 11).
    public var prefersDarkText: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.7
    }

    /// WCAG 2 relative luminance (sRGB components linearised), 0 for black … 1 for white. Alpha is ignored.
    public var relativeLuminance: CGFloat {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio between two colours, 1 … 21.
    public func contrastRatio(with other: RGBA) -> CGFloat {
        let (a, b) = (relativeLuminance, other.relativeLuminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The title of a button filled with this colour (the interface accent on 「复制」, 「去授权」…) is dark
    /// when white would fall below 3:1, WCAG's minimum for large text and UI components, where Apple's own
    /// white-on-blue default button sits: red, pink, purple and blue keep white; orange, green and the
    /// brighter graphite get dark text.
    public var filledButtonPrefersDarkTitle: Bool {
        contrastRatio(with: RGBA(red: 1, green: 1, blue: 1)) < 3
    }
}

/// The six preset annotation colours, in palette order (design doc §4.3).
public enum PaletteColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, blue, black

    /// `black` becomes white in dark appearance so it stays visible (design doc §4.3).
    /// The resolved colour is stored in the annotation, so switching appearance later does not repaint it.
    public func rgba(darkAppearance: Bool) -> RGBA {
        switch self {
        case .red: RGBA(hex: 0xFF3B30)
        case .orange: RGBA(hex: 0xFF9500)
        case .yellow: RGBA(hex: 0xFFCC00)
        case .green: RGBA(hex: 0x34C759)
        case .blue: RGBA(hex: 0x007AFF)
        case .black: darkAppearance ? RGBA(hex: 0xFFFFFF) : RGBA(hex: 0x000000)
        }
    }
}

/// The three width levels in the style palette. Persisted by name, so reordering cases cannot
/// change what a stored style means.
public enum StrokeWidth: String, CaseIterable, Codable, Sendable {
    case thin, medium, thick

    /// Position in the palette, thin first; indexes the per-tool size tables.
    public var index: Int {
        switch self {
        case .thin: 0
        case .medium: 1
        case .thick: 2
        }
    }
}

/// The colour and width level every tool draws with. One for all tools, so switching tools keeps it
/// (design doc §3.3); mosaic uses only the width.
public struct AnnotationStyle: Equatable, Codable, Sendable {
    public var color: PaletteColor
    public var width: StrokeWidth

    public init(color: PaletteColor, width: StrokeWidth) {
        self.color = color
        self.width = width
    }

    public static let standard = AnnotationStyle(color: .red, width: .medium)

    /// Each field falls back to `.standard` on its own, so one unreadable value (say, a colour name from
    /// a later version) does not reset the other.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? container.decode(PaletteColor.self, forKey: .color)) ?? Self.standard.color
        width = (try? container.decode(StrokeWidth.self, forKey: .width)) ?? Self.standard.width
    }
}

extension Tool {
    /// What a width level means for this tool, in points: stroke width (rectangle, ellipse, arrow, pen),
    /// font size (text), brush diameter (mosaic) or badge diameter (counter).
    public func size(for width: StrokeWidth) -> CGFloat {
        let sizes: [CGFloat] = switch self {
        case .rectangle, .ellipse, .arrow, .pen: [2, 4, 6]
        case .text: [14, 20, 28]
        case .mosaic: [12, 24, 40]
        case .counter: [20, 26, 34]
        }
        return sizes[width.index]
    }
}
