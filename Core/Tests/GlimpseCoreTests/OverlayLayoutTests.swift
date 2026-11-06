import CoreGraphics
import Testing
@testable import GlimpseCore

struct OverlayLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let toolbarSize = CGSize(width: 300, height: 40)
    let paletteSize = CGSize(width: 200, height: 30)
    let labelSize = CGSize(width: 80, height: 20)

    @Test func toolbarGoesBelowRightAligned() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 100, width: 400, height: 300), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 408, width: 300, height: 40), side: .below))
    }

    @Test func toolbarGoesAboveWhenNoRoomBelow() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 500, width: 400, height: 280), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 452, width: 300, height: 40), side: .above))
    }

    @Test func toolbarGoesInsideWhenNoRoomEitherSide() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: screen, screen: screen)
        #expect(p == .init(frame: CGRect(x: 692, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarStaysOnScreenHorizontally() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 0, y: 100, width: 100, height: 100), screen: screen)
        #expect(p.frame == CGRect(x: 4, y: 208, width: 300, height: 40))
    }

    @Test func paletteGoesAwayFromSelection() {
        let below = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 408, width: 300, height: 40), side: .below)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: below, screen: screen)
                == CGRect(x: 300, y: 456, width: 200, height: 30))
        let above = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 452, width: 300, height: 40), side: .above)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: above, screen: screen)
                == CGRect(x: 300, y: 414, width: 200, height: 30))
    }

    @Test func paletteFlipsWhenNoRoom() {
        let toolbar = OverlayLayout.ToolbarPosition(frame: CGRect(x: 300, y: 750, width: 300, height: 40), side: .below)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen)
                == CGRect(x: 300, y: 712, width: 200, height: 30))
    }

    @Test func toolTipFacesTheSelection() {
        let button = CGRect(x: 400, y: 413, width: 30, height: 30)
        // Toolbar below the selection: the tooltip goes above the button, centred on it.
        #expect(OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: button, toolbarSide: .below, screen: screen)
                == CGRect(x: 380, y: 385, width: 70, height: 22))
        // Toolbar above the selection: below the button.
        #expect(OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: button, toolbarSide: .above, screen: screen)
                == CGRect(x: 380, y: 449, width: 70, height: 22))
    }

    @Test func toolTipFlipsAndStaysOnScreen() {
        // Button at the top-left corner: no room above, so below; shifted right to stay on screen.
        let r = OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: CGRect(x: 4, y: 4, width: 30, height: 30),
                                      toolbarSide: .inside, screen: screen)
        #expect(r == CGRect(x: 4, y: 40, width: 70, height: 22))
    }

    @Test func sizeLabelSitsAboveTopLeft() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 200, y: 100, width: 400, height: 300),
                                        screen: screen, avoiding: nil)
        #expect(r == CGRect(x: 200, y: 74, width: 80, height: 20))
    }

    @Test func sizeLabelMovesInsideAtTopEdge() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 200, y: 10, width: 400, height: 300),
                                        screen: screen, avoiding: nil)
        #expect(r == CGRect(x: 206, y: 16, width: 80, height: 20))
    }

    @Test func sizeLabelMovesInsideWhenToolbarCoversIt() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: CGRect(x: 500, y: 500, width: 100, height: 280),
                                        screen: screen, avoiding: CGRect(x: 300, y: 452, width: 300, height: 40))
        #expect(r == CGRect(x: 506, y: 506, width: 80, height: 20))
    }

    // A camera housing 100pt wide and 40pt tall, centred at the top of the screen.
    let notch = CGRect(x: 450, y: 0, width: 100, height: 40)

    @Test func toolbarFallsInsideWhenAboveWouldTouchTheNotch() {
        let selection = CGRect(x: 200, y: 60, width: 400, height: 740)
        #expect(OverlayLayout.toolbar(size: toolbarSize, selection: selection, screen: screen).side == .above)
        #expect(OverlayLayout.toolbar(size: toolbarSize, selection: selection, screen: screen, obstacle: notch)
                == .init(frame: CGRect(x: 292, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarStaysAboveWhenBesideTheNotch() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 700, y: 60, width: 200, height: 740),
                                      screen: screen, obstacle: notch)
        #expect(p == .init(frame: CGRect(x: 600, y: 12, width: 300, height: 40), side: .above))
    }

    @Test func paletteSkipsASideThatTouchesTheNotch() {
        let toolbar = OverlayLayout.ToolbarPosition(frame: CGRect(x: 440, y: 70, width: 300, height: 40), side: .above)
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen)
                == CGRect(x: 440, y: 32, width: 200, height: 30))
        #expect(OverlayLayout.palette(size: paletteSize, toolbar: toolbar, screen: screen, obstacle: notch)
                == CGRect(x: 440, y: 118, width: 200, height: 30))
    }

    @Test func sizeLabelMovesInsideWhenAboveWouldTouchTheNotch() {
        let selection = CGRect(x: 440, y: 50, width: 300, height: 300)
        #expect(OverlayLayout.sizeLabel(size: labelSize, selection: selection, screen: screen, avoiding: nil, obstacle: notch)
                == CGRect(x: 446, y: 56, width: 80, height: 20))
    }

    @Test func toolTipFlipsAwayFromTheNotch() {
        let button = CGRect(x: 460, y: 60, width: 30, height: 30)
        let size = CGSize(width: 70, height: 22)
        #expect(OverlayLayout.toolTip(size: size, button: button, toolbarSide: .below, screen: screen).origin
                == CGPoint(x: 440, y: 32))
        #expect(OverlayLayout.toolTip(size: size, button: button, toolbarSide: .below, screen: screen, obstacle: notch).origin
                == CGPoint(x: 440, y: 96))
    }

    @Test func toolbarInsideIsAlsoClampedHorizontally() {
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 0, y: 0, width: 100, height: 800), screen: screen)
        #expect(p == .init(frame: CGRect(x: 4, y: 752, width: 300, height: 40), side: .inside))
    }

    @Test func toolbarExactFitBelow() {
        // below = 748 + 8 = 756 and 756 + 40 == 796 == screen.maxY - margin
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 448, width: 400, height: 300), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 756, width: 300, height: 40), side: .below))
    }

    @Test func toolbarExactFitAbove() {
        // above = 52 - 8 - 40 = 4 == screen.minY + margin
        let p = OverlayLayout.toolbar(size: toolbarSize, selection: CGRect(x: 200, y: 52, width: 400, height: 748), screen: screen)
        #expect(p == .init(frame: CGRect(x: 300, y: 4, width: 300, height: 40), side: .above))
    }

    @Test func toolTipStaysOnScreenAtTheRightEdge() {
        let r = OverlayLayout.toolTip(size: CGSize(width: 70, height: 22), button: CGRect(x: 960, y: 413, width: 30, height: 30),
                                      toolbarSide: .below, screen: screen)
        #expect(r == CGRect(x: 926, y: 385, width: 70, height: 22))
    }

    @Test func toolTipLandsOnWholePoints() {
        // Centred on x = 415 with an odd width: 415 - 35.5 = 379.5 rounds to 380.
        let r = OverlayLayout.toolTip(size: CGSize(width: 71, height: 22), button: CGRect(x: 400, y: 413, width: 30, height: 30),
                                      toolbarSide: .below, screen: screen)
        #expect(r.origin == CGPoint(x: 380, y: 385))
    }

    @Test func sizeLabelWithToolbarInsideGoesInsideTopLeft() {
        let r = OverlayLayout.sizeLabel(size: labelSize, selection: screen, screen: screen,
                                        avoiding: CGRect(x: 692, y: 752, width: 300, height: 40))
        #expect(r == CGRect(x: 6, y: 6, width: 80, height: 20))
    }
}
