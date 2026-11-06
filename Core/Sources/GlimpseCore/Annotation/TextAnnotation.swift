import CoreGraphics

extension Annotation {
    /// Where a text box opens for a click (pixels; `fontSize` in pixels on a screen with `scale` pixels per
    /// point): the first line is centred vertically on the click, so the caret appears where the user clicked.
    public static func textOrigin(forClickAt point: CGPoint, fontSize: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y - TextLayout.lineHeight(fontSize: fontSize / scale) * scale / 2)
    }

    /// The committed text annotation, or nil when the box holds only whitespace: an empty text box
    /// is dropped when typing ends (design doc §3.2.1).
    public static func text(origin: CGPoint, string: String, color: RGBA, size: CGFloat, scale: CGFloat) -> Annotation? {
        guard string.contains(where: { !$0.isWhitespace }) else { return nil }
        return Annotation(shape: .text(origin: origin, string: string, scale: scale), color: color, size: size)
    }
}
