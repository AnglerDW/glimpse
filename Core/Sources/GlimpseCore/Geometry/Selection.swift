import CoreGraphics

/// The eight resize handles around a selection.
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// A selection rectangle in screen-local points (top-left origin), always kept inside `bounds`.
public struct Selection: Equatable, Sendable {
    public private(set) var rect: CGRect
    public let bounds: CGRect

    public init(rect: CGRect, bounds: CGRect) {
        self.bounds = bounds
        self.rect = Selection.clamp(rect, to: bounds)
    }

    public static func fromDrag(start: CGPoint, end: CGPoint, bounds: CGRect) -> Selection {
        Selection(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                               width: abs(end.x - start.x), height: abs(end.y - start.y)),
                  bounds: bounds)
    }

    /// Too thin to be a real screenshot; treated as "no selection".
    public var isUsable: Bool { rect.width >= 2 && rect.height >= 2 }

    public mutating func moveOrigin(to origin: CGPoint) {
        let x = max(bounds.minX, min(origin.x, bounds.maxX - rect.width))
        let y = max(bounds.minY, min(origin.y, bounds.maxY - rect.height))
        rect.origin = CGPoint(x: x, y: y)
    }

    public mutating func move(by delta: CGVector) {
        moveOrigin(to: CGPoint(x: rect.minX + delta.dx, y: rect.minY + delta.dy))
    }

    /// Arrow-key nudge: 1pt, or 10pt with Shift.
    public mutating func nudge(dx: Int, dy: Int, large: Bool) {
        let step: CGFloat = large ? 10 : 1
        move(by: CGVector(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step))
    }

    /// Moves `handle` to `point`, computed from `original` (the rect when the drag began),
    /// so dragging past the opposite edge flips the rect instead of collapsing it.
    public mutating func resize(_ handle: Handle, to point: CGPoint, original: CGRect) {
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
        var x0 = original.minX, x1 = original.maxX, y0 = original.minY, y1 = original.maxY
        switch handle {
        case .topLeft: x0 = p.x; y0 = p.y
        case .top: y0 = p.y
        case .topRight: x1 = p.x; y0 = p.y
        case .right: x1 = p.x
        case .bottomRight: x1 = p.x; y1 = p.y
        case .bottom: y1 = p.y
        case .bottomLeft: x0 = p.x; y1 = p.y
        case .left: x0 = p.x
        }
        rect = Selection.clamp(CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0)),
                               to: bounds)
    }

    public static func handlePoint(_ handle: Handle, of r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .left: CGPoint(x: r.minX, y: r.midY)
        }
    }

    /// The handle nearest to `point` among those within `tolerance` (per axis); nil if none.
    /// Picking the nearest keeps handles distinguishable when hit zones overlap on small selections.
    /// On a selection too small to have an interior beyond its handle zones (shorter side <= 2 * tolerance),
    /// points in its central core (the rect inset by min(tolerance, side / 4) per axis) return nil so it can
    /// still be grabbed and moved. Points nearer an edge keep hitting handles, so a thin strip against a
    /// screen edge can still be resized from its inner side.
    public func handle(at point: CGPoint, tolerance: CGFloat = 6) -> Handle? {
        if min(rect.width, rect.height) <= 2 * tolerance {
            let core = rect.insetBy(dx: min(tolerance, rect.width / 4), dy: min(tolerance, rect.height / 4))
            if point.x > core.minX, point.x < core.maxX, point.y > core.minY, point.y < core.maxY { return nil }
        }
        var best: (handle: Handle, distance: CGFloat)?
        for h in Handle.allCases {
            let c = Selection.handlePoint(h, of: rect)
            guard abs(c.x - point.x) <= tolerance, abs(c.y - point.y) <= tolerance else { continue }
            let d = hypot(c.x - point.x, c.y - point.y)
            if best == nil || d < best!.distance { best = (h, d) }
        }
        return best?.handle
    }

    private static func clamp(_ r: CGRect, to b: CGRect) -> CGRect {
        let i = r.standardized.intersection(b)
        return i.isNull ? CGRect(x: b.minX, y: b.minY, width: 0, height: 0) : i
    }
}
