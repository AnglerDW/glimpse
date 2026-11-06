import CoreGraphics

/// The frozen frame pixelated into blocks, built once per block size. Mosaic strokes show this image
/// through their brush shape, so pixels always come from the original frame (design doc §3.4), blocks
/// sit on one grid anchored at the image's top-left (overlapping strokes line up), and the overlay and
/// the export see identical blocks.
// Not Sendable: one per overlay, used on the main thread only.
public final class MosaicSource {
    public let image: CGImage
    /// A failed build is cached as nil too, so a redraw never retries it.
    private var cache: [Int: CGImage?] = [:]

    public init(image: CGImage) {
        self.image = image
    }

    /// One pixel per block, `ceil(width / blockSize)` × `ceil(height / blockSize)`.
    public func pixelated(blockSize: Int) -> CGImage? {
        if let cached = cache[blockSize] { return cached }
        let result = Self.pixelate(image, blockSize: blockSize)
        cache[blockSize] = .some(result)
        return result
    }

    static func pixelate(_ image: CGImage, blockSize: Int) -> CGImage? {
        guard blockSize > 0 else { return nil }
        let width = (image.width + blockSize - 1) / blockSize
        let height = (image.height + blockSize - 1) / blockSize
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        // The frame's own colour space first (P3 stays P3), sRGB if that cannot back a bitmap.
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        guard let context = spaces.lazy.compactMap({
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: $0, bitmapInfo: bitmapInfo)
        }).first else { return nil }
        context.interpolationQuality = .high // averages each block when shrinking
        // When the size is not a multiple of the block, the last row / column of blocks is only partly
        // covered. Stretching the image underneath first fills that remainder with nearby colours
        // instead of transparency; the exact-scale draw on top then keeps the grid anchored at the top-left.
        if image.width % blockSize != 0 || image.height % blockSize != 0 {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scaledWidth = CGFloat(image.width) / CGFloat(blockSize)
        let scaledHeight = CGFloat(image.height) / CGFloat(blockSize)
        context.draw(image, in: CGRect(x: 0, y: CGFloat(height) - scaledHeight, width: scaledWidth, height: scaledHeight))
        return context.makeImage()
    }
}
