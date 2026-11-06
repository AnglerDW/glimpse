import CoreGraphics
import Testing
@testable import GlimpseCore

private let redPixel: [UInt8] = [255, 59, 48, 255]
private let white: [UInt8] = [255, 255, 255, 255]

/// Element kinds of a path, in order.
private func elements(_ path: CGPath) -> [CGPathElementType] {
    var kinds: [CGPathElementType] = []
    path.applyWithBlock { kinds.append($0.pointee.type) }
    return kinds
}

/// Pixels of `image` inside `rect` that satisfy `test`.
private func count(in image: CGImage, _ rect: CGRect, where test: ([UInt8]) -> Bool) -> Int {
    var n = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
        for x in Int(rect.minX)..<Int(rect.maxX) where test(TestImage.pixel(image, x: x, y: y)) { n += 1 }
    }
    return n
}

struct PenTests {
    @Test func smoothedPathCurvesThroughMidpointsAndEndsOnTheLastSample() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10)]
        let path = ShapeGeometry.smoothedPath(through: points)
        #expect(elements(path) == [.moveToPoint, .addQuadCurveToPoint, .addQuadCurveToPoint, .addLineToPoint])
        #expect(path.currentPoint == CGPoint(x: 20, y: 10))
    }

    @Test func twoSamplesAreAStraightLine() {
        let path = ShapeGeometry.smoothedPath(through: [.zero, CGPoint(x: 5, y: 5)])
        #expect(elements(path) == [.moveToPoint, .addLineToPoint])
    }

    @Test func penStrokeHasRoundEnds() {
        let image = TestImage.render([Annotation(shape: .pen([CGPoint(x: 5, y: 20), CGPoint(x: 35, y: 20)]),
                                                 color: RGBA(hex: 0xFF3B30), size: 4)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 4, y: 20) == redPixel)  // the round cap reaches past the first sample
        #expect(TestImage.pixel(image, x: 20, y: 24) == white)
    }

    @Test func aClickDrawsADot() {
        let image = TestImage.render([Annotation(shape: .pen([CGPoint(x: 20, y: 20)]), color: RGBA(hex: 0xFF3B30), size: 6)],
                                     width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 20, y: 25) == white)
    }

    @Test func dragRedrawsOnlyTheStrokeTail() throws {
        var pen = try #require(AnnotationDraft(tool: .pen, start: .zero, color: RGBA(hex: 0xFF3B30), size: 4))
        for x in stride(from: 10, through: 100, by: 10) {
            pen.extend(to: CGPoint(x: x, y: 0), constrained: false)
        }
        // The last three samples (x 80...100), widened by half the 4-pixel brush plus a pixel.
        #expect(pen.tailBounds == CGRect(x: 77, y: -3, width: 26, height: 6))
        #expect(pen.annotation?.bounds.minX == -3) // the whole stroke reaches back to the start
        var box = try #require(AnnotationDraft(tool: .rectangle, start: .zero, color: RGBA(hex: 0xFF3B30), size: 4))
        box.extend(to: CGPoint(x: 50, y: 30), constrained: false)
        #expect(box.tailBounds == box.annotation?.bounds) // shapes redraw whole
    }
}

struct CounterTests {
    @Test func badgeIsFilledWithAWhiteNumber() {
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 1),
                                                 color: RGBA(hex: 0xFF3B30), size: 30)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 20, y: 8) == redPixel)  // above the digit, inside the badge
        #expect(TestImage.pixel(image, x: 2, y: 2) == white)      // outside the badge
        let digit = count(in: image, CGRect(x: 14, y: 12, width: 12, height: 16)) { $0[1] > 200 && $0[2] > 200 }
        #expect(digit > 10)
    }

    @Test func lightBadgeGetsADarkNumber() {
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 7),
                                                 color: RGBA(hex: 0xFFCC00), size: 30)], width: 40, height: 40)
        let digit = count(in: image, CGRect(x: 14, y: 12, width: 12, height: 16)) { $0[0] < 80 }
        #expect(digit > 10)
    }

    @Test func threeDigitsFitInsideTheBadge() {
        // Dark digits on a yellow badge of radius 15: every dark pixel stays at least a pixel inside the edge.
        let image = TestImage.render([Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 100),
                                                 color: RGBA(hex: 0xFFCC00), size: 30)], width: 40, height: 40)
        var outside = 0
        for y in 0..<40 {
            for x in 0..<40 where hypot(CGFloat(x) + 0.5 - 20, CGFloat(y) + 0.5 - 20) > 14 {
                if TestImage.pixel(image, x: x, y: y)[0] < 128 { outside += 1 }
            }
        }
        #expect(outside == 0)
        let digits = count(in: image, CGRect(x: 6, y: 12, width: 28, height: 16)) { $0[0] < 80 }
        #expect(digits > 20)
    }
}
