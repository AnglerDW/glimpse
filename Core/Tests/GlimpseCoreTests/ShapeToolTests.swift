import CoreGraphics
import Testing
@testable import GlimpseCore

private let red = RGBA(hex: 0xFF3B30)
private let redPixel: [UInt8] = [255, 59, 48, 255]
private let white: [UInt8] = [255, 255, 255, 255]

private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
    abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
}

struct ShapeGeometryTests {
    @Test func dragRectIsStandardized() {
        #expect(ShapeGeometry.rect(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 10), square: false)
                == CGRect(x: 10, y: 10, width: 30, height: 10))
    }

    @Test func shiftMakesASquareInTheDragDirection() {
        #expect(ShapeGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 20), square: true)
                == CGRect(x: 10, y: 10, width: 30, height: 30))
        #expect(ShapeGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: -20, y: 15), square: true)
                == CGRect(x: -20, y: 10, width: 30, height: 30))
    }

    @Test func shiftSnapsArrowsTo45DegreesKeepingLength() {
        let diagonal = ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: 30, y: 40))
        let side = 50 / CGFloat(2).squareRoot()
        #expect(close(diagonal, CGPoint(x: side, y: side)))
        let flat = ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: 100, y: -10))
        #expect(flat == CGPoint(x: CGFloat(10100).squareRoot(), y: 0)) // exactly level
    }

    @Test func snappingWorksInEveryDirection() {
        let side = 50 / CGFloat(2).squareRoot()
        #expect(close(ShapeGeometry.snapped45(from: .zero, to: CGPoint(x: -30, y: -40)), CGPoint(x: -side, y: -side)))
        #expect(ShapeGeometry.snapped45(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: -90))
                == CGPoint(x: 10, y: 10 - CGFloat(10004).squareRoot())) // exactly vertical
    }

    @Test func arrowShaftTapersTowardsAWiderHead() {
        // Width 4: the shaft widens from half-width 0.6 at the tail to 3.2 where the head starts (x = 82);
        // the head is 18 long, half-width 8.8 at its base, 0 at the tip.
        let path = ShapeGeometry.arrowPath(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(path.contains(CGPoint(x: 5, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 5, y: 1)))     // thin tail
        #expect(path.contains(CGPoint(x: 80, y: 3)))
        #expect(!path.contains(CGPoint(x: 80, y: 3.4)))  // the shaft's wide end
        #expect(path.contains(CGPoint(x: 83, y: 8)))     // the head is much wider than the shaft's end
        #expect(path.contains(CGPoint(x: 91, y: 4.2)))   // half-width 4.4 halfway along the head
        #expect(!path.contains(CGPoint(x: 91, y: 4.7)))
        let annotation = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: red, size: 4)
        #expect(annotation.bounds.contains(path.boundingBoxOfPath))
    }

    @Test func shortArrowShrinksButKeepsAShaft() {
        // 10 long at width 4: the head may take only 60% (6 of its full 18), so the outline scales by
        // 1 / 3 and a tapering shaft still runs from x = 0 to the head's base at x = 4.
        let path = ShapeGeometry.arrowPath(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 4)
        let box = path.boundingBoxOfPath
        #expect(box.minX == 0 && box.maxX == 10)
        #expect(abs(box.height - 2 * 8.8 / 3) < 1e-9)
        #expect(path.contains(CGPoint(x: 3, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 3, y: 1.2)))  // the shaft, narrower than the head
        #expect(path.contains(CGPoint(x: 5, y: 2.2)))   // the head, just past its base
    }
}

struct AnnotationDraftTests {
    @Test func rectangleFollowsTheDragAndShiftSquaresIt() throws {
        var draft = try #require(AnnotationDraft(tool: .rectangle, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        draft.extend(to: CGPoint(x: 50, y: 30), constrained: false)
        #expect(draft.annotation == Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 40, height: 20)),
                                               color: red, size: 4))
        draft.setConstrained(true) // ⇧ pressed without moving
        #expect(draft.annotation?.shape == .rectangle(CGRect(x: 10, y: 10, width: 40, height: 40)))
    }

    @Test func shiftMakesTheEllipseACircle() throws {
        var draft = try #require(AnnotationDraft(tool: .ellipse, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        draft.extend(to: CGPoint(x: 0, y: 40), constrained: true)
        #expect(draft.annotation?.shape == .ellipse(CGRect(x: -20, y: 10, width: 30, height: 30)))
    }

    @Test func clickWithoutDragDrawsNoShape() throws {
        var rect = try #require(AnnotationDraft(tool: .ellipse, start: CGPoint(x: 10, y: 10), color: red, size: 4))
        #expect(rect.annotation == nil)
        rect.extend(to: CGPoint(x: 10, y: 10), constrained: false)
        #expect(rect.annotation == nil)
        var arrow = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        arrow.extend(to: CGPoint(x: 1, y: 0), constrained: false)
        #expect(arrow.annotation == nil)
    }

    @Test func arrowSnapsWithShift() throws {
        var draft = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        draft.extend(to: CGPoint(x: 100, y: -10), constrained: true)
        guard case .arrow(_, let end)? = draft.annotation?.shape else {
            Issue.record("expected an arrow")
            return
        }
        #expect(close(end, CGPoint(x: CGFloat(10100).squareRoot(), y: 0)))
    }

    @Test func shiftSnapsTheArrowWithoutMovingTheMouse() throws {
        var draft = try #require(AnnotationDraft(tool: .arrow, start: .zero, color: red, size: 4))
        draft.extend(to: CGPoint(x: 100, y: -10), constrained: false)
        draft.setConstrained(true)
        #expect(draft.annotation?.shape == .arrow(from: .zero, to: CGPoint(x: CGFloat(10100).squareRoot(), y: 0)))
        draft.setConstrained(false)
        #expect(draft.annotation?.shape == .arrow(from: .zero, to: CGPoint(x: 100, y: -10)))
    }

    @Test func mosaicCarriesItsBlockSize() throws {
        var draft = try #require(AnnotationDraft(tool: .mosaic, start: .zero, color: red, size: 24, mosaicBlockSize: 16))
        draft.extend(to: CGPoint(x: 10, y: 0), constrained: false)
        #expect(draft.annotation?.shape == .mosaic([.zero, CGPoint(x: 10, y: 0)], blockSize: 16))
    }

    @Test func penKeepsSamplesAtLeastAPixelApart() throws {
        var draft = try #require(AnnotationDraft(tool: .pen, start: .zero, color: red, size: 4))
        #expect(draft.annotation?.shape == .pen([.zero])) // a click draws a dot
        draft.extend(to: CGPoint(x: 0.5, y: 0), constrained: false)
        draft.extend(to: CGPoint(x: 5, y: 0), constrained: false)
        draft.extend(to: CGPoint(x: 10, y: 0), constrained: true)
        #expect(draft.annotation?.shape == .pen([.zero, CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)]))
    }

    @Test func clickToolsHaveNoDraft() {
        #expect(AnnotationDraft(tool: .counter, start: .zero, color: red, size: 4) == nil)
        #expect(AnnotationDraft(tool: .text, start: .zero, color: red, size: 4) == nil)
    }
}

struct AnnotationRendererTests {
    @Test func rectangleStrokeIsCentredOnTheEdge() {
        let image = TestImage.render([Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 10, y: 20) == redPixel) // left edge, stroke covers x 9...11
        #expect(TestImage.pixel(image, x: 20, y: 10) == redPixel) // top edge
        #expect(TestImage.pixel(image, x: 20, y: 20) == white)    // inside stays clear
        #expect(TestImage.pixel(image, x: 5, y: 20) == white)
    }

    @Test func ellipseIsStrokedNotFilled() {
        let image = TestImage.render([Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        let top = TestImage.pixel(image, x: 20, y: 10)
        #expect(top[0] > 200 && top[1] < 120)
        #expect(TestImage.pixel(image, x: 20, y: 20) == white)
        #expect(TestImage.pixel(image, x: 11, y: 11) == white) // the corner of the box is outside the ellipse
    }

    @Test func arrowIsFilledShaftAndHead() {
        // Width 2: the shaft widens from half-width 0.5 at x = 5 to 1.6 at x = 26; the head runs from
        // there to the tip at 35, half-width 4.4 at its base.
        let image = TestImage.render([Annotation(shape: .arrow(from: CGPoint(x: 5, y: 20), to: CGPoint(x: 35, y: 20)),
                                                 color: red, size: 2)], width: 40, height: 40)
        #expect(TestImage.pixel(image, x: 15, y: 20) == redPixel)
        #expect(TestImage.pixel(image, x: 6, y: 21) == white)     // thin near the tail
        #expect(TestImage.pixel(image, x: 24, y: 21) != white)    // wider near the head
        #expect(TestImage.pixel(image, x: 15, y: 23) == white)
        #expect(TestImage.pixel(image, x: 26, y: 22) == redPixel) // head is wider than the shaft
    }
}
