import CoreGraphics
import Foundation

/// Geometry behind the shape tools (design doc §3.4). Pixel coordinates, top-left origin.
public enum ShapeGeometry {
    /// The rect a drag spans. With `square` (⇧) both sides take the longer one, growing in the drag's direction.
    public static func rect(from start: CGPoint, to end: CGPoint, square: Bool) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
    }

    /// ⇧ on the arrow: the end moves to the nearest multiple of 45° around `start`, keeping the drag length.
    public static func snapped45(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let octant = Int((atan2(dy, dx) / (CGFloat.pi / 4)).rounded())
        let (ux, uy) = directions45[(octant % 8 + 8) % 8]
        return CGPoint(x: start.x + length * ux, y: start.y + length * uy)
    }

    /// Unit vectors at 0°, 45°, … 315°, exact so horizontal and vertical arrows have no stray
    /// 1e-16 component from cos / sin.
    private static let directions45: [(CGFloat, CGFloat)] = {
        let d = CGFloat(0.5).squareRoot()
        return [(1, 0), (d, d), (0, 1), (-d, d), (-1, 0), (-d, -d), (0, -1), (d, -d)]
    }()

    /// A solid arrow as one filled outline (ArrowMetrics): a shaft that tapers from a thin tail to its
    /// full width where the head starts, and a wider pointed head. The head takes at most 60% of the
    /// length, so a short arrow keeps a shaft: its head shortens and every width shrinks with it.
    /// Empty for a zero-length arrow.
    public static func arrowPath(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let dx = tip.x - start.x, dy = tip.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return path }
        let fullHead = ArrowMetrics.headLength(lineWidth: lineWidth)
        let headLength = min(fullHead, length * 0.6)
        let shrink = headLength / fullHead
        let headHalf = ArrowMetrics.headHalfWidth(lineWidth: lineWidth) * shrink
        let shaftHalf = ArrowMetrics.shaftHalfWidth(lineWidth: lineWidth) * shrink
        let tailHalf = min(ArrowMetrics.tailHalfWidth(lineWidth: lineWidth), shaftHalf)
        let ux = dx / length, uy = dy / length   // along the arrow
        let nx = -uy, ny = ux                    // across it
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        func offset(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + nx * d, y: p.y + ny * d) }
        path.addLines(between: [
            offset(start, tailHalf), offset(base, shaftHalf), offset(base, headHalf), tip,
            offset(base, -headHalf), offset(base, -shaftHalf), offset(start, -tailHalf),
        ])
        path.closeSubpath()
        return path
    }

    /// The pen's smoothed stroke (design doc §3.4): quadratic curves through the midpoints of the samples,
    /// using each sample as the control point, so corners from jittery mouse input round off.
    /// One sample gives a zero-length segment, which a round cap draws as a dot.
    public static func smoothedPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: last)
            return path
        }
        for i in 1..<(points.count - 1) {
            let next = points[i + 1]
            let mid = CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: last)
        return path
    }
}
