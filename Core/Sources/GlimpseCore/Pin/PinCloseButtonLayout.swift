import CoreGraphics

/// The close button a pin shows while the mouse is over it (design doc §3.6). Rects are in the pin's
/// content view, AppKit coordinates (y up), so the top-left corner is (minX, maxY).
public enum PinCloseButtonLayout {
    /// The round button's diameter.
    public static let diameter: CGFloat = 20
    /// Distance from the pin's top and left edges.
    public static let inset: CGFloat = 6
    /// A pin smaller than this on either side shows no button: it would cover most of the image and leave
    /// nothing to drag. Such a pin still closes by double click or the right-click menu.
    public static let minimumPinSide: CGFloat = 44

    /// The button's frame in a pin of `size`, or nil when the pin is too small for one.
    public static func frame(in size: CGSize) -> CGRect? {
        guard size.width >= minimumPinSide, size.height >= minimumPinSide else { return nil }
        return CGRect(x: inset, y: size.height - inset - diameter, width: diameter, height: diameter)
    }
}
