import CoreGraphics

/// An annotation being dragged out: rectangle, ellipse, arrow, pen or mosaic. Points are image pixels.
/// Counter and text are placed with a click and never need a draft.
public struct AnnotationDraft: Equatable, Sendable {
    public let tool: Tool
    public let color: RGBA
    public let size: CGFloat
    private let mosaicBlockSize: Int
    private var points: [CGPoint]
    private var constrained = false

    /// Nil for tools that are not dragged (counter, text). `mosaicBlockSize` is required for the
    /// mosaic (in pixels, from the screen's scale) and ignored by every other tool.
    public init?(tool: Tool, start: CGPoint, color: RGBA, size: CGFloat, mosaicBlockSize: Int? = nil) {
        guard tool != .counter, tool != .text else { return nil }
        precondition(tool != .mosaic || mosaicBlockSize != nil, "A mosaic draft needs its block size")
        self.tool = tool
        self.color = color
        self.size = size
        self.mosaicBlockSize = mosaicBlockSize ?? 1
        points = [start]
    }

    /// `constrained` is ⇧: square / circle for rectangle and ellipse, 45° steps for the arrow.
    /// Pen and mosaic keep every sample at least a pixel from the previous one.
    public mutating func extend(to point: CGPoint, constrained: Bool) {
        self.constrained = constrained
        switch tool {
        case .rectangle, .ellipse, .arrow:
            points = [points[0], point]
        case .pen, .mosaic:
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
            points.append(point)
        case .counter, .text:
            break
        }
    }

    /// ⇧ pressed or released without moving the mouse.
    public mutating func setConstrained(_ constrained: Bool) {
        self.constrained = constrained
    }

    /// What the draft would commit now; nil while a shape or arrow is too small to see (a click, no drag).
    /// A pen or mosaic click keeps its single point and draws a dot.
    public var annotation: Annotation? {
        let start = points[0]
        let shape: Annotation.Shape
        switch tool {
        case .rectangle, .ellipse:
            guard points.count == 2 else { return nil }
            let rect = ShapeGeometry.rect(from: start, to: points[1], square: constrained)
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            shape = tool == .rectangle ? .rectangle(rect) : .ellipse(rect)
        case .arrow:
            guard points.count == 2 else { return nil }
            let end = constrained ? ShapeGeometry.snapped45(from: start, to: points[1]) : points[1]
            guard hypot(end.x - start.x, end.y - start.y) >= 2 else { return nil }
            shape = .arrow(from: start, to: end)
        case .pen:
            shape = .pen(points)
        case .mosaic:
            shape = .mosaic(points, blockSize: mosaicBlockSize)
        case .counter, .text:
            return nil
        }
        return Annotation(shape: shape, color: color, size: size)
    }

    /// What the latest change can repaint, for redrawing while dragging. Shapes and arrows are redrawn
    /// whole. A pen or mosaic stroke only grows at its end: with midpoint smoothing
    /// (`ShapeGeometry.smoothedPath`), appending a sample replaces the closing line from the midpoint of
    /// the previous two samples with a curve through the last sample, plus a new closing line. Both lie
    /// within the hull of the last three samples, so comparing this before and after a change covers
    /// the old and the new end, widened by half the brush and a pixel for anti-aliasing.
    public var tailBounds: CGRect {
        switch tool {
        case .pen, .mosaic:
            return Annotation.boundingBox(Array(points.suffix(3))).insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .rectangle, .ellipse, .arrow, .counter, .text:
            return annotation?.bounds ?? .null
        }
    }
}
