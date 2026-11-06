import CoreGraphics
import Testing
@testable import GlimpseCore

struct OCRPanelLayoutTests {
    // A 1440 × 900 screen: Dock 60pt at the bottom, menu bar 25pt at the top (AppKit coordinates, y up).
    let visible = CGRect(x: 0, y: 60, width: 1440, height: 815)
    let size = CGSize(width: 440, height: 300)

    @Test func belowTheSelectionWithRightEdgesAligned() {
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 400, y: 400, width: 300, height: 200),
                                          visibleFrame: visible)
        #expect(placed.side == .below)
        #expect(placed.frame == CGRect(x: 260, y: 92, width: 440, height: 300)) // 400 − 8 − 300
    }

    @Test func aboveWhenThereIsNoRoomBelow() {
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 400, y: 100, width: 300, height: 200),
                                          visibleFrame: visible)
        #expect(placed.side == .above)
        #expect(placed.frame == CGRect(x: 260, y: 308, width: 440, height: 300)) // 300 + 8
    }

    @Test func overTheSelectionWhenNeitherSideFits() {
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          visibleFrame: visible)
        #expect(placed.side == .inside)
        // Bottom-right corner inset by the gap, then pushed above the Dock.
        #expect(placed.frame == CGRect(x: 992, y: 68, width: 440, height: 300))
        #expect(visible.insetBy(dx: 8, dy: 8).contains(placed.frame))
    }

    @Test func shiftedSidewaysToStayOnScreen() {
        let narrowAtLeftEdge = OCRPanelLayout.frame(size: size, selection: CGRect(x: 0, y: 400, width: 100, height: 200),
                                                    visibleFrame: visible)
        #expect(narrowAtLeftEdge.frame.minX == 8)
        let pastRightEdge = OCRPanelLayout.frame(size: size, selection: CGRect(x: 1300, y: 400, width: 200, height: 200),
                                                 visibleFrame: visible)
        #expect(pastRightEdge.frame.maxX == 1432)
    }

    @Test func selectionUnderTheDockStillOpensAboveIt() {
        // A selection reaching into the Dock: there is no room below inside the visible frame.
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 600, y: 20, width: 200, height: 100),
                                          visibleFrame: visible)
        #expect(placed.side == .above)
        #expect(placed.frame.minY == 128)
    }

    @Test func secondaryScreenWithNegativeCoordinatesAndWholePoints() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let placed = OCRPanelLayout.frame(size: CGSize(width: 440.5, height: 300),
                                          selection: CGRect(x: -1500.25, y: -500, width: 300, height: 200),
                                          visibleFrame: screen)
        #expect(placed.side == .below)
        #expect(placed.frame.origin == CGPoint(x: -1641, y: -808)) // −1200.25 − 440.5 = −1640.75; −500 − 8 − 300
    }

    @Test func panelLargerThanTheScreenKeepsItsTopOnScreen() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 200)
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 50, y: 50, width: 100, height: 100),
                                          visibleFrame: small)
        #expect(placed.frame.minX == 8)
        #expect(placed.frame.maxY == 192)
    }

    @Test func selectionReachingIntoTheMenuBarStillOpensBelow() {
        // Top edge at 900, past the visible frame's 875: only the room below counts.
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 400, y: 700, width: 300, height: 200),
                                          visibleFrame: visible)
        #expect(placed.side == .below)
        #expect(placed.frame == CGRect(x: 260, y: 392, width: 440, height: 300))
    }

    @Test func tallSelectionIntoTheMenuBarFallsBackInside() {
        // No room below (150 − 308 < 68), none above (908 > 867): over the selection's bottom-right corner.
        let placed = OCRPanelLayout.frame(size: size, selection: CGRect(x: 400, y: 150, width: 300, height: 750),
                                          visibleFrame: visible)
        #expect(placed.side == .inside)
        #expect(placed.frame == CGRect(x: 252, y: 158, width: 440, height: 300))
        #expect(visible.insetBy(dx: 8, dy: 8).contains(placed.frame))
    }
}
