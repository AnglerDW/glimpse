import CoreGraphics
import Testing
@testable import GlimpseCore

struct PointerGestureTests {
    @Test func movementWithinThreePointsIsAClick() {
        #expect(!PointerGesture.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        #expect(!PointerGesture.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
    }

    @Test func movementBeyondThreePointsIsADrag() {
        #expect(PointerGesture.isDrag(from: .zero, to: CGPoint(x: 3, y: 1)))
    }
}
