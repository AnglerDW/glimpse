import CoreGraphics
import Testing
@testable import GlimpseCore

struct PinCloseButtonLayoutTests {
    @Test func sitsInTheTopLeftCornerInsetALittle() {
        // AppKit coordinates: the top edge is at maxY.
        #expect(PinCloseButtonLayout.frame(in: CGSize(width: 300, height: 200))
            == CGRect(x: 6, y: 174, width: 20, height: 20))
    }

    @Test func followsTheTopEdgeWhenThePinIsZoomed() {
        let frame = PinCloseButtonLayout.frame(in: CGSize(width: 600, height: 400))
        #expect(frame?.maxY == 394)
        #expect(frame?.minX == 6)
    }

    @Test func tinyPinsShowNoButton() {
        #expect(PinCloseButtonLayout.frame(in: CGSize(width: 43, height: 300)) == nil)
        #expect(PinCloseButtonLayout.frame(in: CGSize(width: 300, height: 43)) == nil)
        #expect(PinCloseButtonLayout.frame(in: CGSize(width: 44, height: 44)) != nil)
    }
}
