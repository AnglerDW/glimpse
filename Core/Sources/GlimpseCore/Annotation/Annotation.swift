import CoreGraphics

/// One vector annotation. Every coordinate and size is in pixels of its screen's frozen image
/// (top-left origin), not relative to the selection: moving or resizing the selection leaves
/// annotations where they are on the picture (design doc §5.2).
public struct Annotation: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        /// Raw pointer samples; smoothed when drawn.
        case pen([CGPoint])
        /// The brush path. The area it covers shows the original frame in `blockSize`-pixel blocks.
        case mosaic([CGPoint], blockSize: Int)
        case counter(center: CGPoint, number: Int)
        /// `origin` is the top-left of the first line; lines are split on newlines. `scale` is the screen's
        /// pixels per point: the text is laid out at `size / scale` points and scaled up, like the text box it
        /// was typed in, because fallback fonts (Chinese, emoji, …) size themselves from the point size.
        case text(origin: CGPoint, string: String, scale: CGFloat)
    }

    public var shape: Shape
    public var color: RGBA
    /// Stroke width (rectangle, ellipse, arrow, pen), brush diameter (mosaic),
    /// badge diameter (counter) or font size (text), in pixels.
    public var size: CGFloat

    public init(shape: Shape, color: RGBA, size: CGFloat) {
        self.shape = shape
        self.color = color
        self.size = size
    }

    /// Everything this annotation may paint, with a pixel to spare for anti-aliasing.
    public var bounds: CGRect {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .arrow(let from, let to):
            let head = ArrowMetrics.headHalfWidth(lineWidth: size)
            return Self.boundingBox([from, to]).insetBy(dx: -head - 1, dy: -head - 1)
        case .pen(let points), .mosaic(let points, _):
            return Self.boundingBox(points).insetBy(dx: -size / 2 - 1, dy: -size / 2 - 1)
        case .counter(let center, _):
            return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size).insetBy(dx: -1, dy: -1)
        case .text(let origin, let string, let scale):
            let points = TextLayout.size(of: string, fontSize: size / scale)
            // Fallback glyphs (Chinese, emoji) can stand out of the fixed-height lines by a fraction of the size.
            return CGRect(x: origin.x, y: origin.y, width: points.width * scale, height: points.height * scale)
                .insetBy(dx: -1, dy: -size / 4 - 1)
        }
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Arrow proportions, all scaling with the line width (design doc §3.4): the shaft tapers from a thin
/// tail to its full width where the head starts, and the head is clearly wider than that.
/// The head's half-width is the widest part, so it alone sizes `Annotation.bounds`.
public enum ArrowMetrics {
    /// Half the shaft's width at the tail; the tail stays at least a pixel wide.
    public static func tailHalfWidth(lineWidth: CGFloat) -> CGFloat { max(0.5, lineWidth * 0.15) }
    /// Half the shaft's width where it meets the head.
    public static func shaftHalfWidth(lineWidth: CGFloat) -> CGFloat { lineWidth * 0.8 }
    public static func headLength(lineWidth: CGFloat) -> CGFloat { lineWidth * 4.5 }
    public static func headHalfWidth(lineWidth: CGFloat) -> CGFloat { lineWidth * 2.2 }
}
