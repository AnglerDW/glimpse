import CoreGraphics

/// Where the editing chrome (toolbar, style palette, size label) goes around a selection.
/// Every rect is screen-local points (top-left origin, y down), like `Selection`.
/// `obstacle` is an area the chrome must stay out of: on a notch screen, the camera housing. Callers pass nil
/// when there is none. A placement that would touch it (with the usual margin) counts as "no room" and falls
/// back the same way a placement that leaves the screen does.
public enum OverlayLayout {
    /// Space between the selection and the toolbar, and between the toolbar and the style palette.
    public static let gap: CGFloat = 8
    /// Chrome keeps at least this far from every screen edge.
    public static let screenMargin: CGFloat = 4

    public struct ToolbarPosition: Equatable, Sendable {
        public enum Side: Equatable, Sendable { case below, above, inside }
        public let frame: CGRect
        public let side: Side

        public init(frame: CGRect, side: Side) {
            self.frame = frame
            self.side = side
        }
    }

    /// Below the selection; above it when there is no room below; inside its bottom edge as a last
    /// resort (design doc §3.2). Right-aligned with the selection so ✕ ✓ sit next to its right edge,
    /// then shifted sideways to stay on screen.
    public static func toolbar(size: CGSize, selection: CGRect, screen: CGRect, obstacle: CGRect? = nil) -> ToolbarPosition {
        let below = selection.maxY + gap
        let belowFrame = frame(x: selection.maxX - size.width, y: below, size: size, screen: screen)
        if below + size.height <= screen.maxY - screenMargin, isClear(belowFrame, of: obstacle) {
            return ToolbarPosition(frame: belowFrame, side: .below)
        }
        let above = selection.minY - gap - size.height
        let aboveFrame = frame(x: selection.maxX - size.width, y: above, size: size, screen: screen)
        if above >= screen.minY + screenMargin, isClear(aboveFrame, of: obstacle) {
            return ToolbarPosition(frame: aboveFrame, side: .above)
        }
        return ToolbarPosition(frame: frame(x: selection.maxX - gap - size.width,
                                            y: selection.maxY - gap - size.height, size: size, screen: screen),
                               side: .inside)
    }

    /// The colour / width palette goes on the side of the toolbar away from the selection (below a toolbar
    /// that is below or inside it, above a toolbar that is above it) and flips when that side has no room.
    /// Left-aligned with the toolbar, where the tool buttons are.
    public static func palette(size: CGSize, toolbar: ToolbarPosition, screen: CGRect, obstacle: CGRect? = nil) -> CGRect {
        let below = toolbar.frame.maxY + gap
        let above = toolbar.frame.minY - gap - size.height
        let fitsBelow = below + size.height <= screen.maxY - screenMargin
            && isClear(frame(x: toolbar.frame.minX, y: below, size: size, screen: screen), of: obstacle)
        let fitsAbove = above >= screen.minY + screenMargin
            && isClear(frame(x: toolbar.frame.minX, y: above, size: size, screen: screen), of: obstacle)
        let y: CGFloat
        switch toolbar.side {
        case .below, .inside: y = fitsBelow || !fitsAbove ? below : above
        case .above: y = fitsAbove || !fitsBelow ? above : below
        }
        return frame(x: toolbar.frame.minX, y: y, size: size, screen: screen)
    }

    /// Above the selection's top-left corner; inside it when there is no room above or when the toolbar
    /// (which may sit above the selection) would cover the label.
    public static func sizeLabel(size: CGSize, selection: CGRect, screen: CGRect, avoiding toolbar: CGRect?,
                                 obstacle: CGRect? = nil) -> CGRect {
        let above = frame(x: selection.minX, y: selection.minY - size.height - 6, size: size, screen: screen)
        let roomAbove = selection.minY - size.height - 6 >= screen.minY + screenMargin
        if roomAbove, isClear(above, of: obstacle), toolbar.map({ !$0.intersects(above) }) ?? true { return above }
        return frame(x: selection.minX + 6, y: selection.minY + 6, size: size, screen: screen)
    }

    /// A toolbar button's tooltip: centred on the button, on the toolbar's selection-facing side (the style
    /// palette may occupy the other side), flipped when that side has no room.
    public static func toolTip(size: CGSize, button: CGRect, toolbarSide: ToolbarPosition.Side, screen: CGRect,
                               obstacle: CGRect? = nil) -> CGRect {
        let above = button.minY - 6 - size.height
        let below = button.maxY + 6
        let x = button.midX - size.width / 2
        let fitsAbove = above >= screen.minY + screenMargin
            && isClear(frame(x: x, y: above, size: size, screen: screen), of: obstacle)
        let fitsBelow = below + size.height <= screen.maxY - screenMargin
            && isClear(frame(x: x, y: below, size: size, screen: screen), of: obstacle)
        let preferAbove = toolbarSide != .above
        let y = preferAbove ? (fitsAbove || !fitsBelow ? above : below) : (fitsBelow || !fitsAbove ? below : above)
        return frame(x: button.midX - size.width / 2, y: y, size: size, screen: screen)
    }

    /// True when `rect` stays `screenMargin` away from `obstacle` (or there is none).
    public static func isClear(_ rect: CGRect, of obstacle: CGRect?) -> Bool {
        guard let obstacle else { return true }
        return !rect.intersects(obstacle.insetBy(dx: -screenMargin, dy: -screenMargin))
    }

    /// A rect of `size` at (x, y) on whole points (so text and edges stay crisp), shifted to stay
    /// `screenMargin` inside `screen`.
    private static func frame(x: CGFloat, y: CGFloat, size: CGSize, screen: CGRect) -> CGRect {
        let cx = max(screen.minX + screenMargin, min(x.rounded(), screen.maxX - screenMargin - size.width))
        let cy = max(screen.minY + screenMargin, min(y.rounded(), screen.maxY - screenMargin - size.height))
        return CGRect(origin: CGPoint(x: cx, y: cy), size: size)
    }
}
