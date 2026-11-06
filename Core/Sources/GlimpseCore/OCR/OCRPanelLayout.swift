import CoreGraphics

/// Where the text extraction result panel opens (design doc §3.5): next to the selection it came from, like the
/// overlay toolbar. AppKit screen coordinates (y up); `selection` is the selection's frame on screen and
/// `visibleFrame` that screen's visible frame (without menu bar and Dock).
public enum OCRPanelLayout {
    /// Space between the selection and the panel.
    public static let gap: CGFloat = 8
    /// The panel keeps at least this far from the edges of the visible frame.
    public static let screenMargin: CGFloat = 8

    public enum Side: Equatable, Sendable { case below, above, inside }

    /// Below the selection with right edges aligned; above it when there is no room below; over the
    /// selection's bottom-right corner (inset by `gap`) when neither fits. Then shifted to stay
    /// `screenMargin` inside `visibleFrame`, on whole points.
    public static func frame(size: CGSize, selection: CGRect, visibleFrame: CGRect) -> (frame: CGRect, side: Side) {
        let x = selection.maxX - size.width
        let below = selection.minY - gap - size.height
        if below >= visibleFrame.minY + screenMargin {
            return (clamped(x: x, y: below, size: size, in: visibleFrame), .below)
        }
        let above = selection.maxY + gap
        if above + size.height <= visibleFrame.maxY - screenMargin {
            return (clamped(x: x, y: above, size: size, in: visibleFrame), .above)
        }
        return (clamped(x: x - gap, y: selection.minY + gap, size: size, in: visibleFrame), .inside)
    }

    /// `size` at (x, y) rounded, shifted into `visible` minus the margin. A panel larger than the visible
    /// frame keeps its top-left corner on screen (title and ✕ stay reachable).
    private static func clamped(x: CGFloat, y: CGFloat, size: CGSize, in visible: CGRect) -> CGRect {
        let cx = max(visible.minX + screenMargin, min(x.rounded(), visible.maxX - screenMargin - size.width))
        let cy = min(visible.maxY - screenMargin - size.height, max(y.rounded(), visible.minY + screenMargin))
        return CGRect(origin: CGPoint(x: cx, y: cy), size: size)
    }
}
