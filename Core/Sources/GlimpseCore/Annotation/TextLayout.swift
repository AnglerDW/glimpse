import CoreGraphics
import CoreText
import Foundation

/// Line metrics for text annotations, shared by the renderer and the text box shown while typing.
public enum TextLayout {
    /// The system UI font, the same one `NSFont.systemFont(ofSize:)` returns; bold for counter numbers.
    /// Cached per size, because annotation bounds are measured on every redraw.
    public static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        fontCache.font(size: size, bold: bold) {
            let regular = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            guard bold else { return regular }
            return CTFontCreateCopyWithSymbolicTraits(regular, size, nil, .traitBold, .traitBold) ?? regular
        }
    }

    private static let fontCache = FontCache()

    /// Fixed distance between baselines. The text box uses the same value so typing and the
    /// committed annotation line up.
    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// Distance from the top of the text to the baseline of line `index` (0-based): the bottom of that
    /// fixed-height line minus the descent rounded to whole units. This is where TextKit 1 puts the baseline
    /// with a fixed line height; the text box also pins it there for lines with fallback fonts.
    /// The text is laid out in points, so this is in points too.
    public static func baseline(line index: Int, fontSize: CGFloat) -> CGFloat {
        CGFloat(index + 1) * lineHeight(fontSize: fontSize) - CTFontGetDescent(font(size: fontSize)).rounded()
    }

    /// Splits on any newline ("\n", "\r\n", "\r"); keeps empty lines.
    public static func lines(of string: String) -> [String] {
        string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    public static func line(_ text: String, fontSize: CGFloat, color: CGColor, bold: Bool = false) -> CTLine {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font(size: fontSize, bold: bold),
                                           kCTForegroundColorAttributeName: color]
        let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        return CTLineCreateWithAttributedString(string)
    }

    /// Draws `line` upright with its baseline starting at `origin`, in a context whose CTM is y-down
    /// (CoreText assumes y-up, so the text is flipped locally).
    public static func draw(_ line: CTLine, baselineOrigin origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Width of the widest line × (line count × line height).
    public static func size(of string: String, fontSize: CGFloat) -> CGSize {
        let lines = lines(of: string)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let width = lines.map { CGFloat(CTLineGetTypographicBounds(line($0, fontSize: fontSize, color: black), nil, nil, nil)) }.max() ?? 0
        return CGSize(width: ceil(width), height: lineHeight(fontSize: fontSize) * CGFloat(lines.count))
    }
}

/// Fonts by (size, bold), shared by every thread that measures or draws text.
// Safe: `fonts` is only touched while holding `lock`, and CTFont is immutable.
private final class FontCache: @unchecked Sendable {
    private struct Key: Hashable {
        let size: CGFloat
        let bold: Bool
    }

    private let lock = NSLock()
    private var fonts: [Key: CTFont] = [:]

    func font(size: CGFloat, bold: Bool, make: () -> CTFont) -> CTFont {
        lock.withLock {
            let key = Key(size: size, bold: bold)
            if let font = fonts[key] { return font }
            let font = make()
            fonts[key] = font
            return font
        }
    }
}
