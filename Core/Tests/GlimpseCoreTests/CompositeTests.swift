import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import GlimpseCore

private let red = RGBA(hex: 0xFF3B30)
private let redPixel: [UInt8] = [255, 59, 48, 255]

/// Rectangle stroke on the frame from (10, 10) to (30, 30), 2 pixels wide: its left edge covers x 9...11.
private let box = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: red, size: 2)

/// `Renderer.composite` the way the overlay calls it: mosaic blocks come from the same frame.
private func composite(_ frame: CGImage, _ annotations: [Annotation], cropTo rect: CGRect) throws -> CGImage {
    let source = MosaicSource(image: frame)
    return try #require(Renderer.composite(frame, annotations: annotations, toPixelRect: rect) {
        source.pixelated(blockSize: $0)
    })
}

struct CompositeTests {
    @Test func annotationsAreDrawnAtFullResolutionInsideTheCrop() throws {
        let frame = TestImage.gradient(width: 40, height: 40)
        let shot = try composite(frame, [box], cropTo: CGRect(x: 5, y: 5, width: 30, height: 30))
        #expect(shot.width == 30 && shot.height == 30)
        #expect(TestImage.pixel(shot, x: 5, y: 15) == redPixel)          // frame (10, 20): the left edge
        #expect(TestImage.pixel(shot, x: 15, y: 15) == [20, 20, 0, 255]) // frame (20, 20): untouched gradient
    }

    @Test func annotationsStayOnThePictureWhenTheSelectionMoves() throws {
        // Design doc §5.2 / §8: moving the selection does not move annotations relative to the picture.
        let frame = TestImage.gradient(width: 40, height: 40)
        let before = try composite(frame, [box], cropTo: CGRect(x: 0, y: 0, width: 40, height: 40))
        let after = try composite(frame, [box], cropTo: CGRect(x: 8, y: 8, width: 30, height: 30))
        #expect(TestImage.pixel(before, x: 10, y: 20) == redPixel)
        #expect(TestImage.pixel(after, x: 2, y: 12) == redPixel) // the same frame pixel (10, 20)
    }

    @Test func partsOutsideTheSelectionAreCropped() throws {
        let frame = TestImage.gradient(width: 40, height: 40)
        let shot = try composite(frame, [box], cropTo: CGRect(x: 20, y: 0, width: 20, height: 20))
        #expect(shot.width == 20 && shot.height == 20)
        #expect(TestImage.pixel(shot, x: 10, y: 15) == redPixel) // right edge, frame (30, 15)
        #expect(TestImage.pixel(shot, x: 5, y: 5) == [25, 5, 0, 255])
    }

    @Test func resultIsIndependentOpaqueAndKeepsTheFrameColourSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: p3, components: [0.2, 0.4, 0.6, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let frame = try #require(context.makeImage())
        let shot = try composite(frame, [box], cropTo: CGRect(x: 2, y: 2, width: 8, height: 8))
        #expect(shot.colorSpace?.name == CGColorSpace.displayP3)
        // Its own crop-sized buffer, not a window onto the 64 × 64 frame (which `CGImage.cropping` would keep).
        let shotBytes = try #require(shot.dataProvider?.data as Data?).count
        let frameBytes = try #require(frame.dataProvider?.data as Data?).count
        #expect(shotBytes == shot.bytesPerRow * shot.height)
        #expect(shotBytes * 8 <= frameBytes)
        // No alpha channel: the exported PNG / TIFF is opaque, like the screen it came from.
        #expect(shot.alphaInfo == .noneSkipFirst)
    }

    @Test func textLandsUprightAtItsPlaceInTheCrop() throws {
        // End to end on a 2x screen: a 20pt "T" at frame pixel (13, 11), cropped from (10, 8). The top of the
        // capital sits 2 × (baseline − cap height) pixels below the origin; a flipped or shifted text would
        // put ink in the rows above it, or the wide bar at the bottom instead of the top.
        let frame = TestImage.render([], width: 80, height: 80) // white
        let text = try #require(Annotation.text(origin: CGPoint(x: 13, y: 11), string: "T",
                                                color: RGBA(hex: 0x000000), size: 40, scale: 2))
        let shot = try composite(frame, [text], cropTo: CGRect(x: 10, y: 8, width: 60, height: 60))
        let font = TextLayout.font(size: 20)
        let baseline = 3 + Int(2 * TextLayout.baseline(line: 0, fontSize: 20))
        let capTop = 3 + Int((2 * (TextLayout.baseline(line: 0, fontSize: 20) - CTFontGetCapHeight(font))).rounded(.down))
        let ink = { (rows: Range<Int>) in
            rows.reduce(0) { n, y in n + (0..<shot.width).filter { TestImage.pixel(shot, x: $0, y: y)[0] < 128 }.count }
        }
        #expect(ink(0..<capTop) == 0)
        let bar = ink(capTop..<(capTop + 3))
        #expect(bar > 0)
        #expect(bar > ink((baseline - 3)..<baseline) * 2)
    }

    @Test func mosaicTakesPixelsFromTheOriginalNotFromAnnotationsBelowIt() throws {
        // A thick red box, then a mosaic over everything: no red survives, because mosaic samples the
        // original frame (design doc §3.4), whose blue channel is 0 everywhere.
        let frame = TestImage.gradient(width: 16, height: 16)
        let thick = Annotation(shape: .rectangle(CGRect(x: 4, y: 4, width: 8, height: 8)), color: red, size: 6)
        let mosaic = Annotation(shape: .mosaic([CGPoint(x: 0, y: 8), CGPoint(x: 16, y: 8)], blockSize: 4),
                                color: red, size: 40)
        let shot = try composite(frame, [thick, mosaic], cropTo: CGRect(x: 0, y: 0, width: 16, height: 16))
        for (x, y) in [(4, 4), (8, 4), (12, 12), (4, 10)] {
            #expect(TestImage.pixel(shot, x: x, y: y)[2] == 0)
        }
    }

    @Test func mosaicBlocksStayOnTheFrameGridWhenTheCropDoesNot() throws {
        // 8-pixel blocks are anchored at the frame's top-left, not the crop's. Cropping 17 × 13 from (3, 5)
        // puts the block edge at frame x = 8 on crop x = 5, frame x = 16 on crop x = 13, frame y = 8 on crop y = 3.
        let frame = TestImage.gradient(width: 24, height: 24)
        let mosaic = Annotation(shape: .mosaic([CGPoint(x: 0, y: 12), CGPoint(x: 24, y: 12)], blockSize: 8),
                                color: red, size: 60)
        let shot = try composite(frame, [mosaic], cropTo: CGRect(x: 3, y: 5, width: 17, height: 13))
        let pixel = { (x: Int, y: Int) in TestImage.pixel(shot, x: x, y: y) }
        #expect(pixel(0, 0) == pixel(4, 0))
        #expect(pixel(4, 0) != pixel(5, 0))
        #expect(pixel(5, 0) == pixel(12, 0))
        #expect(pixel(12, 0) != pixel(13, 0))
        #expect(pixel(0, 0) == pixel(0, 2))
        #expect(pixel(0, 2) != pixel(0, 3))
    }
}
