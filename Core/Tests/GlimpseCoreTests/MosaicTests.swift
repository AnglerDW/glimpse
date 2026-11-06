import CoreGraphics
import Testing
@testable import GlimpseCore

private let white: [UInt8] = [255, 255, 255, 255]

struct MosaicTests {
    /// A mosaic stroke over the whole 16 × 16 gradient, in 8-pixel blocks.
    private func mosaicOverGradient() -> CGImage {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        let stroke = Annotation(shape: .mosaic([CGPoint(x: 0, y: 8), CGPoint(x: 16, y: 8)], blockSize: 8),
                                color: RGBA(hex: 0), size: 40)
        return TestImage.render([stroke], width: 16, height: 16) { source.pixelated(blockSize: $0) }
    }

    @Test func eachBlockIsOneColour() {
        let image = mosaicOverGradient()
        let corner = TestImage.pixel(image, x: 0, y: 0)
        for (x, y) in [(7, 0), (0, 7), (7, 7), (3, 4)] {
            #expect(TestImage.pixel(image, x: x, y: y) == corner)
        }
        #expect(TestImage.pixel(image, x: 8, y: 0) != corner)
    }

    @Test func blocksAverageTheOriginalPixels() {
        // Source red = x, green = y: block (0, 0) averages 0...7, block (1, 1) averages 8...15.
        let image = mosaicOverGradient()
        let first = TestImage.pixel(image, x: 0, y: 0)
        let last = TestImage.pixel(image, x: 15, y: 15)
        #expect((2...5).contains(first[0]) && (2...5).contains(first[1]))
        #expect((10...13).contains(last[0]) && (10...13).contains(last[1]))
        #expect(first[3] == 255)
    }

    @Test func onlyTheBrushAreaChanges() {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        let dab = Annotation(shape: .mosaic([CGPoint(x: 3, y: 3)], blockSize: 4), color: RGBA(hex: 0), size: 4)
        let image = TestImage.render([dab], width: 16, height: 16) { source.pixelated(blockSize: $0) }
        #expect(TestImage.pixel(image, x: 3, y: 3) != white)
        #expect(TestImage.pixel(image, x: 12, y: 12) == white)
    }

    @Test func partialEdgeBlocksStayOpaque() throws {
        // 10 × 6 in 4-pixel blocks: 3 × 2 blocks, the last column and row only partly covered.
        let solid = TestImage.render([], width: 10, height: 6)
        let blocks = try #require(MosaicSource.pixelate(solid, blockSize: 4))
        #expect(blocks.width == 3 && blocks.height == 2)
        #expect(TestImage.pixel(blocks, x: 2, y: 1) == white)
    }

    @Test func pixelatedImageIsCachedPerBlockSize() {
        let source = MosaicSource(image: TestImage.gradient(width: 16, height: 16))
        #expect(source.pixelated(blockSize: 4) === source.pixelated(blockSize: 4))
        #expect(source.pixelated(blockSize: 4) !== source.pixelated(blockSize: 8))
    }
}
