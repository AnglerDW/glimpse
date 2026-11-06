import CoreGraphics
import Testing
@testable import GlimpseCore

struct PinZoomTests {
    let image = CGSize(width: 400, height: 200)

    @Test func wheelAwayZoomsInAndTowardsZoomsOut() {
        #expect(PinZoom.zoom(1, scrolledBy: 1, precise: false, imageSize: image) > 1)
        #expect(PinZoom.zoom(1, scrolledBy: -1, precise: false, imageSize: image) < 1)
        // A trackpad's point deltas are ten times finer than wheel lines.
        let wheel = PinZoom.zoom(1, scrolledBy: 1, precise: false, imageSize: image)
        let trackpad = PinZoom.zoom(1, scrolledBy: 10, precise: true, imageSize: image)
        #expect(abs(wheel - trackpad) < 1e-9)
    }

    @Test func zoomIsClamped() {
        #expect(PinZoom.zoom(4.9, scrolledBy: 100, precise: false, imageSize: image) == PinZoom.maximumZoom)
        #expect(PinZoom.zoom(1, scrolledBy: -100, precise: false, imageSize: image) == 0.12) // 24 / 200
        #expect(PinZoom.minimum(imageSize: CGSize(width: 4000, height: 3000)) == 0.1)
        #expect(PinZoom.minimum(imageSize: CGSize(width: 300, height: 16)) == 1) // already smaller than 24pt
    }

    @Test func bigImagesStopAtTenThousandPoints() {
        let big = CGSize(width: 4000, height: 1000)
        #expect(PinZoom.maximum(imageSize: big) == 2.5)
        #expect(PinZoom.zoom(2, scrolledBy: 100, precise: false, imageSize: big) == 2.5)
    }

    @Test func pinchZoomsByTheMagnification() {
        #expect(abs(PinZoom.zoom(1, magnifiedBy: 0.25, imageSize: image) - 1.25) < 1e-9)
        #expect(abs(PinZoom.zoom(1, magnifiedBy: -0.5, imageSize: image) - 0.5) < 1e-9)
        #expect(PinZoom.zoom(1, magnifiedBy: -5, imageSize: image) == 0.12) // clamped to the 24pt minimum
    }

    @Test func zoomStopsAtActualSizeOnTheWayThrough() {
        // Crossing 100% stops there, by wheel or by pinch.
        #expect(PinZoom.zoom(0.9, scrolledBy: 2, precise: false, imageSize: image) == 1)
        #expect(PinZoom.zoom(1.1, scrolledBy: -2, precise: false, imageSize: image) == 1)
        #expect(PinZoom.zoom(0.9, magnifiedBy: 0.2, imageSize: image) == 1)
        // Heading towards 100% and within 3% of it: snaps.
        #expect(PinZoom.zoom(0.95, scrolledBy: 3, precise: true, imageSize: image) == 1)
        // Leaving 100%, however finely, is not held back.
        #expect(PinZoom.zoom(1, scrolledBy: 1, precise: true, imageSize: image) > 1)
        #expect(PinZoom.zoom(1.01, scrolledBy: 1, precise: true, imageSize: image) > 1.01)
        #expect(PinZoom.zoom(1, scrolledBy: -1, precise: true, imageSize: image) < 1)
    }

    @Test func zoomKeepsThePointUnderTheMouse() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 200)
        let zoomed = PinZoom.frame(frame, zoomedTo: 2, imageSize: image, anchor: CGPoint(x: 200, y: 150), backingScale: 2)
        #expect(zoomed == CGRect(x: 0, y: 50, width: 800, height: 400))
    }

    @Test func zoomedFramesLandOnThePixelGrid() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let zoomed = PinZoom.frame(frame, zoomedTo: 1.013, imageSize: image, anchor: CGPoint(x: 133, y: 77), backingScale: 2)
        #expect(zoomed.origin.x * 2 == (zoomed.origin.x * 2).rounded())
        #expect(zoomed.origin.y * 2 == (zoomed.origin.y * 2).rounded())
        #expect(zoomed.size == CGSize(width: 405, height: 202.5)) // 405.2 × 202.6 to half points
        let onePoint = PinZoom.frame(frame, zoomedTo: 1.013, imageSize: image, anchor: CGPoint(x: 133, y: 77), backingScale: 1)
        #expect(onePoint.size == CGSize(width: 405, height: 203))
    }

    @Test func actualSizeIsTheImageSizeExactly() {
        // A capture from a 1.5× screen is not whole points; at 100% it must still map 1:1 to its pixels.
        let odd = CGSize(width: 200.5, height: 100.5)
        let frame = CGRect(x: 10, y: 20, width: 220, height: 110)
        let zoomed = PinZoom.frame(frame, zoomedTo: 1, imageSize: odd, anchor: CGPoint(x: 60, y: 50), backingScale: 2)
        #expect(zoomed.size == odd)
    }
}
