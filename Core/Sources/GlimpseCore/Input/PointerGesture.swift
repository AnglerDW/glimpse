import CoreGraphics

public enum PointerGesture {
    /// Moving no more than this between mouse-down and mouse-up counts as a click.
    public static let dragThreshold: CGFloat = 3

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }
}
