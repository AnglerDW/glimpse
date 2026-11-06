import CoreGraphics

/// Turns a frozen screen image (plus annotations) into the final screenshot, at full pixel resolution.
public enum Renderer {
    /// `pixelRect` is in image pixels, top-left origin. Returns nil when nothing remains after clamping.
    public static func crop(_ image: CGImage, toPixelRect pixelRect: CGRect) -> CGImage? {
        composite(image, annotations: [], toPixelRect: pixelRect, pixelated: { _ in nil })
    }

    /// The frozen frame with `annotations` drawn over it, cut to `pixelRect` (image pixels, top-left origin).
    /// Same result as compositing the whole frame and cropping (design doc §5.2), but only the crop is
    /// allocated: the context is crop-sized and shifted, so annotations outside it are clipped away.
    /// The result is an independent, opaque bitmap in the frame's colour space (P3 stays P3): it holds no
    /// reference to the full frozen frame. Mosaic reads `pixelated`, which is built from the original frame;
    /// like `draw`, it has no default, so a caller cannot forget it and leave mosaicked areas unredacted.
    public static func composite(_ image: CGImage, annotations: [Annotation], toPixelRect pixelRect: CGRect,
                                 pixelated: (Int) -> CGImage?) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = pixelRect.integral.intersection(imageBounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        // Opaque, like the frozen frame: the PNG / TIFF then has no alpha channel (smaller, never read as transparent).
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in spaces {
            guard let context = CGContext(data: nil, width: Int(r.width), height: Int(r.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else { continue }
            context.interpolationQuality = .none
            // Image pixel space, y down, with the crop's top-left at the context's top-left.
            context.translateBy(x: 0, y: r.height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -r.minX, y: -r.minY)
            drawUpright(image, in: imageBounds, context: context)
            draw(annotations, in: context, pixelated: pixelated)
            if let result = context.makeImage() { return result }
        }
        return nil
    }
}
