import CoreGraphics
import Testing
@testable import GlimpseCore

struct MagnifierTests {
    @Test func pixelUnderTheCursorOnRetinaIsClamped() {
        #expect(Magnifier.pixel(at: CGPoint(x: 10.7, y: 3.2), scale: 2, imageWidth: 100, imageHeight: 50) == CGPoint(x: 21, y: 6))
        #expect(Magnifier.pixel(at: CGPoint(x: 2000, y: -5), scale: 2, imageWidth: 100, imageHeight: 50) == CGPoint(x: 99, y: 0))
    }

    @Test func sourceIsCentredOnThePixel() {
        #expect(Magnifier.sourceRect(around: CGPoint(x: 20, y: 30)) == CGRect(x: 12, y: 22, width: 17, height: 17))
    }

    @Test func panelIsAGridWithInfoAndHintRows() {
        #expect(Magnifier.gridSide == 119) // 17 pixels at 7×
        #expect(Magnifier.panelSize == CGSize(width: 135, height: 213))
        #expect(Magnifier.infoRowY(0) == 135) // 8 + 119 + 8
        #expect(Magnifier.infoRowY(1) == 153)
        #expect(Magnifier.hintRowY(0) == 177) // 135 + 2 × 18 + 6
        #expect(Magnifier.hintRowY(1) + Magnifier.hintRowHeight + Magnifier.panelInset == Magnifier.panelSize.height)
    }

    @Test func crosshairCrossesOnTheCentrePixelWithoutOverlapping() {
        let segments = Magnifier.crosshairSegments
        #expect(segments == [CGRect(x: 59, y: 0, width: 1, height: 119),
                             CGRect(x: 0, y: 59, width: 59, height: 1), CGRect(x: 60, y: 59, width: 59, height: 1)])
        // The centre cell is 56..<63: the 1pt line at 59 leaves 3pt of it on either side.
        let grid = CGRect(x: 0, y: 0, width: Magnifier.gridSide, height: Magnifier.gridSide)
        for segment in segments {
            #expect(segment == segment.integral)
            #expect(grid.contains(segment))
        }
        // Drawn once at 60%: no point is covered twice, and together they span the full row and column.
        for (index, a) in segments.enumerated() {
            for b in segments[(index + 1)...] { #expect(!a.intersects(b)) }
        }
        let area = segments.map { $0.width * $0.height }.reduce(0, +)
        #expect(area == Magnifier.gridSide * 2 - 1)
        #expect(segments[0].contains(CGPoint(x: 59.5, y: 59.5))) // the crossing is drawn
    }

    @Test func colourValueIsWrittenAsUppercaseHexOrRGB() throws {
        let image = TestImage.gradient(width: 32, height: 32) // pixel (x, y) = RGB(x, y, 0)
        let color = try #require(Magnifier.color(of: image, atPixel: CGPoint(x: 10, y: 20)))
        #expect(color.text(.hex) == "#0A1400")
        #expect(color.text(.rgb) == "10, 20, 0")
        #expect(Magnifier.color(of: image, atPixel: CGPoint(x: 31, y: 0))?.text(.hex) == "#1F0000")
        #expect(Magnifier.color(of: image, atPixel: CGPoint(x: 32, y: 0)) == nil)
    }

    @Test func panelSitsBelowRightOfTheCursor() {
        let frame = Magnifier.frame(size: Magnifier.panelSize, cursor: CGPoint(x: 100, y: 100),
                                    screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 120, y: 120, width: 135, height: 213))
    }

    @Test func panelTriesTheOtherSideWhenItWouldTouchTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = CGRect(x: 450, y: 0, width: 100, height: 40)
        let size = CGSize(width: 120, height: 150)
        // Below-right of a cursor at the left of the notch would sit under it; the left side is clear.
        #expect(Magnifier.frame(size: size, cursor: CGPoint(x: 440, y: 10), screen: screen, obstacle: notch)
                == CGRect(x: 300, y: 30, width: 120, height: 150))
        // No other side fits (above is off screen, left touches the notch): keep the first choice.
        #expect(Magnifier.frame(size: size, cursor: CGPoint(x: 500, y: 10), screen: screen, obstacle: notch)
                == CGRect(x: 520, y: 30, width: 120, height: 150))
    }

    @Test func panelFlipsAwayFromTheRightAndBottomEdges() {
        let frame = Magnifier.frame(size: Magnifier.panelSize, cursor: CGPoint(x: 950, y: 750),
                                    screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 795, y: 517, width: 135, height: 213))
    }

    @Test func panelOriginIsOnWholePointsForAFractionalCursor() {
        let frame = Magnifier.frame(size: Magnifier.panelSize, cursor: CGPoint(x: 100.4, y: 100.6),
                                    screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 120, y: 121, width: 135, height: 213))
    }
}
