import AppKit
import GlimpseCore

/// Draws the menu bar icon (design doc §3.7) as template images, one per `StatusIconFrame`, cached. Each
/// image carries a 1x and a 2x bitmap, so AppKit picks the right one for the screen the menu bar is on
/// (every screen's menu bar with 「显示器具有单独的空间」). The drawing is black on clear and tinted by the
/// system, and nothing but the frame affects the pixels, so a cached image never goes stale.
///
/// The canvas is 18 × 18 points with y down, as in the SVG the icon was designed in; the context is
/// flipped so the paths can be written in those coordinates.
@MainActor
enum StatusIcon {
    /// Points; `NSStatusItem.squareLength` leaves room around it.
    static let size: CGFloat = 18
    /// Backing scales a bitmap is drawn for.
    private static let scales: [CGFloat] = [1, 2]

    private static var cache: [StatusIconFrame: NSImage] = [:]

    /// The template image for `frame`, drawn once.
    static func image(for frame: StatusIconFrame) -> NSImage {
        if let cached = cache[frame] { return cached }
        let image = draw(frame)
        cache[frame] = image
        return image
    }

    private static func draw(_ frame: StatusIconFrame) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        for scale in scales {
            guard let bitmap = bitmap(frame, scale: scale) else { continue } // never in practice
            let rep = NSBitmapImageRep(cgImage: bitmap)
            rep.size = NSSize(width: size, height: size) // 36 px at 2x is still 18 pt
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        image.accessibilityDescription = description(of: frame)
        return image
    }

    private static func bitmap(_ frame: StatusIconFrame, scale: CGFloat) -> CGImage? {
        let pixels = Int((size * scale).rounded())
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // SVG coordinates: origin top-left, points.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setFillColor(.black)
        context.setStrokeColor(.black)
        Canvas(context: context, scale: scale).draw(frame)
        return context.makeImage()
    }

    private static func description(of frame: StatusIconFrame) -> String {
        switch frame {
        case .idle: "Glimpse"
        case .needsPermission: String(localized: "Glimpse：需要屏幕录制权限", comment: "Accessibility: menu bar icon")
        case .done: String(localized: "Glimpse：已完成", comment: "Accessibility: menu bar icon")
        case .recognizing, .recognizingStill: String(localized: "Glimpse：正在提取文字", comment: "Accessibility: menu bar icon")
        case .recordingHotkey, .recordingHotkeyStill: String(localized: "Glimpse：正在录制快捷键", comment: "Accessibility: menu bar icon")
        case .pinned: String(localized: "Glimpse：有贴图", comment: "Accessibility: menu bar icon")
        }
    }
}

/// The drawing itself. Lines are 1.5 pt on Retina and 1 pt on 1x screens (both an odd number of pixels),
/// and the still shapes are snapped to pixel centres so the strokes do not blur across two pixels.
/// The numbers are the ones in the design doc's §3.7 table and 画法 list.
private struct Canvas {
    let context: CGContext
    let scale: CGFloat

    private static let centre = CGPoint(x: 9, y: 9)
    private static let centreDotRadius: CGFloat = 1.7
    private static let cornerRadius: CGFloat = 2

    // 完成: the corners shrink to this and come back; the centre dot opens into a ring that reaches
    // `apertureMaxRadius` while fading; the ✓ starts once `checkStartsAt` of the tightening has passed.
    private static let tightenedScale: CGFloat = 0.78
    private static let apertureMaxRadius: CGFloat = 6
    private static let checkStartsAt: CGFloat = 0.25
    private static let checkPoints = (CGPoint(x: 5.6, y: 9.4), CGPoint(x: 8, y: 11.8), CGPoint(x: 12.7, y: 6.6))

    // 提取文字中: three rows, and the scan line sweeping between `scanTop` and `scanBottom`.
    private static let rows: [(y: CGFloat, endX: CGFloat)] = [(6.5, 12.5), (9, 12.5), (11.5, 9.5)]
    private static let rowStartX: CGFloat = 5.5
    private static let scanTop: CGFloat = 5.5
    private static let scanBottom: CGFloat = 10.7
    private static let scanStartX: CGFloat = 4.5
    private static let scanEndX: CGFloat = 13.5
    private static let faintRowAlpha: CGFloat = 0.25

    // 录制快捷键中: a ripple from the dot's edge out to `rippleMaxRadius`, fading from `rippleStartAlpha`.
    private static let rippleMaxRadius: CGFloat = 6
    private static let rippleStartAlpha: CGFloat = 0.9
    private static let stillRippleRadius: CGFloat = 4
    private static let stillRippleAlpha: CGFloat = 0.4

    // 有贴图: the dot in place of the top-right corner, popping in with an ease-out-back overshoot.
    private static let pinDotCentre = CGPoint(x: 14, y: 4)
    private static let pinDotRadius: CGFloat = 2.4
    /// The usual ease-out-back constant (c1); the curve overshoots to about 1.1 before settling.
    private static let popOvershoot: CGFloat = 1.70158

    // 缺权限: the ⚠ in place of the bottom-right corner, with the ! cut out of it.
    private static let warningTriangle = (CGPoint(x: 13.6, y: 9.6), CGPoint(x: 17.5, y: 16.4), CGPoint(x: 9.7, y: 16.4))
    private static let warningBar = (CGPoint(x: 13.6, y: 11.3), CGPoint(x: 13.6, y: 13.4))
    private static let warningDotCentre = CGPoint(x: 13.6, y: 15.2)

    /// Corner strokes; the ✓ and the scan line are a little heavier, the ! in the ⚠ a little lighter.
    var lineWidth: CGFloat { scale >= 2 ? 1.5 : 1 }
    var checkLineWidth: CGFloat { scale >= 2 ? 1.8 : 1.2 }
    var scanLineWidth: CGFloat { scale >= 2 ? 1.2 : 1 }
    var warningBarWidth: CGFloat { scale >= 2 ? 1.3 : 1 }
    var warningDotRadius: CGFloat { scale >= 2 ? 0.75 : 0.5 }

    func draw(_ frame: StatusIconFrame) {
        switch frame {
        case .idle:
            drawCorners()
            fillCircle(at: Self.centre, radius: Self.centreDotRadius)
        case .needsPermission:
            drawCorners(skipping: .bottomRight)
            drawWarningCorner()
            fillCircle(at: Self.centre, radius: Self.centreDotRadius)
        case .done(let step):
            drawDone(progress: min(CGFloat(step + 1) / CGFloat(StatusIconTimeline.doneLastStep + 1), 1))
        case .recognizing(let step):
            drawCorners()
            drawRecognizing(phase: CGFloat(step) / CGFloat(StatusIconTimeline.recognizingCycle))
        case .recognizingStill:
            drawCorners()
            drawRecognizing(phase: nil)
        case .recordingHotkey(let step):
            drawCorners()
            fillCircle(at: Self.centre, radius: Self.centreDotRadius)
            let phase = CGFloat(step) / CGFloat(StatusIconTimeline.recordingCycle)
            let radius = Self.centreDotRadius + (Self.rippleMaxRadius - Self.centreDotRadius) * phase
            strokeCircle(at: Self.centre, radius: radius, width: lineWidth, alpha: Self.rippleStartAlpha * (1 - phase))
        case .recordingHotkeyStill:
            drawCorners()
            fillCircle(at: Self.centre, radius: Self.centreDotRadius)
            strokeCircle(at: Self.centre, radius: Self.stillRippleRadius, width: lineWidth, alpha: Self.stillRippleAlpha)
        case .pinned(let step):
            drawCorners(skipping: .topRight)
            drawPinCorner(progress: min(CGFloat(step + 1) / CGFloat(StatusIconTimeline.pinnedLastStep + 1), 1))
            fillCircle(at: Self.centre, radius: Self.centreDotRadius)
        }
    }

    // MARK: - Viewfinder corners

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft

        /// Start of the stroke, the corner the arc rounds, end of the stroke (SVG coordinates).
        var points: (start: CGPoint, corner: CGPoint, end: CGPoint) {
            switch self {
            case .topLeft: (CGPoint(x: 2, y: 6.5), CGPoint(x: 2, y: 2), CGPoint(x: 6.5, y: 2))
            case .topRight: (CGPoint(x: 11.5, y: 2), CGPoint(x: 16, y: 2), CGPoint(x: 16, y: 6.5))
            case .bottomRight: (CGPoint(x: 16, y: 11.5), CGPoint(x: 16, y: 16), CGPoint(x: 11.5, y: 16))
            case .bottomLeft: (CGPoint(x: 6.5, y: 16), CGPoint(x: 2, y: 16), CGPoint(x: 2, y: 11.5))
            }
        }
    }

    /// The four corners, scaled about the centre by `tightness` (1 = at rest). Only the resting shape is
    /// snapped: snapping every frame of the tightening would make it jitter.
    private func drawCorners(skipping skipped: Corner? = nil, tightness: CGFloat = 1) {
        context.setLineWidth(lineWidth)
        for corner in Corner.allCases where corner != skipped {
            let (start, cornerPoint, end) = corner.points
            let path = CGMutablePath()
            path.move(to: place(start, tightness: tightness))
            path.addArc(tangent1End: place(cornerPoint, tightness: tightness), tangent2End: place(end, tightness: tightness),
                        radius: Self.cornerRadius * tightness)
            path.addLine(to: place(end, tightness: tightness))
            context.addPath(path)
            context.strokePath()
        }
    }

    private func place(_ point: CGPoint, tightness: CGFloat) -> CGPoint {
        guard tightness != 1 else { return snapped(point) }
        return CGPoint(x: Self.centre.x + (point.x - Self.centre.x) * tightness,
                       y: Self.centre.y + (point.y - Self.centre.y) * tightness)
    }

    // MARK: - Scenes

    /// `progress` 0 → 1 over the tightening: the corners shrink to `tightenedScale` and come back, the centre
    /// dot opens like an aperture and fades, the ✓ is drawn left to right. At 1 only the ✓ and the resting
    /// corners remain.
    private func drawDone(progress: CGFloat) {
        let tightness = progress >= 1 ? 1 : 1 - (1 - Self.tightenedScale) * sin(.pi * progress)
        drawCorners(tightness: tightness)
        if progress < 1 {
            // The dot becomes a ring that widens and thins out.
            let outer = Self.centreDotRadius + (Self.apertureMaxRadius - Self.centreDotRadius) * progress
            let inner = max(0, outer - Self.centreDotRadius - 0.6 * (1 - progress))
            context.setAlpha(1 - progress)
            let ring = CGMutablePath()
            ring.addEllipse(in: CGRect(x: Self.centre.x - outer, y: Self.centre.y - outer, width: outer * 2, height: outer * 2))
            ring.addEllipse(in: CGRect(x: Self.centre.x - inner, y: Self.centre.y - inner, width: inner * 2, height: inner * 2))
            context.addPath(ring)
            context.fillPath(using: .evenOdd)
            context.setAlpha(1)
        }
        let drawn = min(max((progress - Self.checkStartsAt) / (1 - Self.checkStartsAt), 0), 1)
        guard drawn > 0 else { return }
        let (a, b, c) = Self.checkPoints
        let first = hypot(b.x - a.x, b.y - a.y), second = hypot(c.x - b.x, c.y - b.y)
        let length = drawn * (first + second)
        let path = CGMutablePath()
        path.move(to: a)
        if length <= first {
            path.addLine(to: lerp(a, b, length / first))
        } else {
            path.addLine(to: b)
            path.addLine(to: lerp(b, c, (length - first) / second))
        }
        context.setLineWidth(checkLineWidth)
        context.addPath(path)
        context.strokePath()
    }

    /// Three text rows in the frame and, unless `phase` is nil, a scan line going down (phase < 0.5) and back
    /// up. Rows the scan line has passed on its current sweep are bright, the rest are faint. Only the rows'
    /// y is snapped; their ends stay where the design puts them.
    private func drawRecognizing(phase: CGFloat?) {
        let scanY: CGFloat?
        let goingDown: Bool
        if let phase {
            let sweep = phase < 0.5 ? phase * 2 : 2 - phase * 2 // 0 → 1 → 0
            scanY = Self.scanTop + (Self.scanBottom - Self.scanTop) * sweep
            goingDown = phase < 0.5
        } else {
            scanY = nil
            goingDown = true
        }
        context.setLineWidth(lineWidth)
        for row in Self.rows {
            let passed: Bool
            if let scanY {
                passed = goingDown ? row.y <= scanY : row.y >= scanY
            } else {
                passed = true
            }
            context.setAlpha(passed ? 1 : Self.faintRowAlpha)
            let y = snappedCoordinate(row.y)
            strokeLine(from: CGPoint(x: Self.rowStartX, y: y), to: CGPoint(x: row.endX, y: y))
        }
        context.setAlpha(1)
        if let scanY {
            context.setLineWidth(scanLineWidth)
            strokeLine(from: CGPoint(x: Self.scanStartX, y: scanY), to: CGPoint(x: Self.scanEndX, y: scanY))
        }
    }

    /// The pin dot in place of the top-right corner (the disc of radius 3.9 around (14, 4) that it sits in
    /// covers that whole corner, so the corner is simply not drawn), scaled by `progress` with a little
    /// overshoot (ease-out back); 1 is the resting dot.
    private func drawPinCorner(progress: CGFloat) {
        let x = progress - 1
        let pop = 1 + (Self.popOvershoot + 1) * x * x * x + Self.popOvershoot * x * x
        fillCircle(at: Self.pinDotCentre, radius: Self.pinDotRadius * pop)
    }

    /// A solid ⚠ in place of the bottom-right corner (the disc of radius 5 around (13.6, 13.6) that it sits
    /// in covers that whole corner, so the corner is simply not drawn), with the ! cut out of it.
    private func drawWarningCorner() {
        let (top, right, left) = Self.warningTriangle
        let triangle = CGMutablePath()
        triangle.move(to: top)
        triangle.addLine(to: right)
        triangle.addLine(to: left)
        triangle.closeSubpath()
        context.addPath(triangle)
        context.fillPath()
        context.setBlendMode(.clear)
        context.setLineWidth(warningBarWidth)
        strokeLine(from: Self.warningBar.0, to: Self.warningBar.1)
        fillCircle(at: Self.warningDotCentre, radius: warningDotRadius)
        context.setBlendMode(.normal)
    }

    // MARK: - Primitives

    private func fillCircle(at centre: CGPoint, radius: CGFloat) {
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }

    private func strokeCircle(at centre: CGPoint, radius: CGFloat, width: CGFloat, alpha: CGFloat) {
        context.setAlpha(alpha)
        context.setLineWidth(width)
        context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        context.setAlpha(1)
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    /// The nearest pixel centre, so a stroke of an odd number of pixels fills whole pixels.
    private func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snappedCoordinate(point.x), y: snappedCoordinate(point.y))
    }

    private func snappedCoordinate(_ value: CGFloat) -> CGFloat {
        (floor(value * scale) + 0.5) / scale
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
