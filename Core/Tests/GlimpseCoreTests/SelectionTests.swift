import CoreGraphics
import Testing
@testable import GlimpseCore

struct SelectionTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func dragInAnyDirectionGivesStandardRect() {
        let s = Selection.fromDrag(start: CGPoint(x: 300, y: 200), end: CGPoint(x: 100, y: 50), bounds: bounds)
        #expect(s.rect == CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    @Test func dragIsClampedToScreen() {
        let s = Selection.fromDrag(start: CGPoint(x: 900, y: 700), end: CGPoint(x: 1200, y: 900), bounds: bounds)
        #expect(s.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func moveStopsAtScreenEdge() {
        var s = Selection(rect: CGRect(x: 10, y: 10, width: 100, height: 100), bounds: bounds)
        s.move(by: CGVector(dx: -50, dy: 20))
        #expect(s.rect == CGRect(x: 0, y: 30, width: 100, height: 100))
    }

    @Test func moveOriginKeepsSizeAndClamps() {
        var s = Selection(rect: CGRect(x: 10, y: 10, width: 100, height: 100), bounds: bounds)
        s.moveOrigin(to: CGPoint(x: 950, y: 750))
        #expect(s.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func nudgeByOneOrTenPoints() {
        var s = Selection(rect: CGRect(x: 100, y: 100, width: 50, height: 50), bounds: bounds)
        s.nudge(dx: 1, dy: 0, large: false)
        #expect(s.rect.origin == CGPoint(x: 101, y: 100))
        s.nudge(dx: 0, dy: -1, large: true)
        #expect(s.rect.origin == CGPoint(x: 101, y: 90))
    }

    @Test func resizeFromBottomRight() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.bottomRight, to: CGPoint(x: 400, y: 250), original: original)
        #expect(s.rect == CGRect(x: 100, y: 100, width: 300, height: 150))
    }

    @Test func resizePastOppositeEdgeFlips() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.left, to: CGPoint(x: 350, y: 999), original: original)
        #expect(s.rect == CGRect(x: 300, y: 100, width: 50, height: 100))
        s.resize(.left, to: CGPoint(x: 400, y: 0), original: original)
        #expect(s.rect == CGRect(x: 300, y: 100, width: 100, height: 100))
    }

    @Test func resizeIsClampedToScreen() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.topLeft, to: CGPoint(x: -50, y: -50), original: original)
        #expect(s.rect == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func handleHitTesting() {
        let s = Selection(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
        #expect(s.handle(at: CGPoint(x: 103, y: 98)) == .topLeft)
        #expect(s.handle(at: CGPoint(x: 200, y: 200)) == .bottom)
        #expect(s.handle(at: CGPoint(x: 300, y: 150)) == .right)
        #expect(s.handle(at: CGPoint(x: 200, y: 150)) == nil)
    }

    @Test func smallSelectionPicksNearestHandle() {
        let s = Selection(rect: CGRect(x: 100, y: 100, width: 8, height: 8), bounds: bounds)
        #expect(s.handle(at: CGPoint(x: 108, y: 108)) == .bottomRight)
        #expect(s.handle(at: CGPoint(x: 108, y: 100)) == .topRight)
        #expect(s.handle(at: CGPoint(x: 100, y: 108)) == .bottomLeft)
    }

    @Test func tinySelectionInteriorIsNotAHandle() {
        let s = Selection(rect: CGRect(x: 100, y: 100, width: 10, height: 10), bounds: bounds)
        #expect(s.handle(at: CGPoint(x: 105, y: 105)) == nil)       // inside: movable
        #expect(s.handle(at: CGPoint(x: 110, y: 110)) == .bottomRight) // on the edge: still a handle
        #expect(s.handle(at: CGPoint(x: 113, y: 105)) == .right)    // just outside: handle
    }

    @Test func thinStripAtScreenEdgeStillHasReachableHandles() {
        let s = Selection(rect: CGRect(x: 0, y: 0, width: 400, height: 10), bounds: bounds)
        #expect(s.handle(at: CGPoint(x: 200, y: 1)) == .top)   // inner side of the edge handle
        #expect(s.handle(at: CGPoint(x: 200, y: 5)) == nil)    // central core moves
        #expect(s.handle(at: CGPoint(x: 1, y: 5)) == .left)
    }

    @Test func resizeTopPastBottomEdgeFlipsVertically() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.top, to: CGPoint(x: 0, y: 250), original: original)
        #expect(s.rect == CGRect(x: 100, y: 200, width: 200, height: 50))
    }

    @Test func resizeOntoOppositeEdgeGivesUnusableZeroWidth() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = Selection(rect: original, bounds: bounds)
        s.resize(.right, to: CGPoint(x: 100, y: 150), original: original)
        #expect(s.rect.width == 0)
        #expect(!s.isUsable)
    }

    @Test func rectOutsideBoundsGivesZeroSizeAtBoundsOrigin() {
        let s = Selection(rect: CGRect(x: 2000, y: 2000, width: 50, height: 50), bounds: bounds)
        #expect(s.rect == CGRect(x: 0, y: 0, width: 0, height: 0))
    }

    @Test func rectLargerThanBoundsIsCropped() {
        let s = Selection(rect: CGRect(x: -100, y: -100, width: 5000, height: 5000), bounds: bounds)
        #expect(s.rect == bounds)
    }

    @Test func moveOriginToNegativeClampsToBoundsOrigin() {
        var s = Selection(rect: CGRect(x: 10, y: 10, width: 100, height: 100), bounds: bounds)
        s.moveOrigin(to: CGPoint(x: -20, y: -30))
        #expect(s.rect.origin == CGPoint(x: 0, y: 0))
    }

    @Test func tinySelectionIsNotUsable() {
        #expect(!Selection(rect: CGRect(x: 0, y: 0, width: 50, height: 1), bounds: bounds).isUsable)
        #expect(Selection(rect: CGRect(x: 0, y: 0, width: 2, height: 2), bounds: bounds).isUsable)
    }
}
