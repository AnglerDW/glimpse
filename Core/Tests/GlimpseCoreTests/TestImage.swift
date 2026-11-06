import CoreGraphics
import Foundation
@testable import GlimpseCore

/// Bitmap helpers for pixel-exact tests. Coordinates are top-left origin, like CGImage rows.
enum TestImage {
    /// Pixel (x, y) has RGBA = (x, y, 0, 255).
    static func gradient(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(x)
                bytes[i + 1] = UInt8(y)
                bytes[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// A white `width` × `height` sRGB image with `annotations` drawn on it, through the same
    /// y-down pixel transform the export uses.
    static func render(_ annotations: [Annotation], width: Int, height: Int,
                       pixelated: (Int) -> CGImage? = { _ in nil }) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        Renderer.draw(annotations, in: ctx, pixelated: pixelated)
        return ctx.makeImage()!
    }

    /// RGBA of pixel (x, y).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 4)
        out.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            // CGContext is bottom-left origin: shift so that image row `y` (from top) lands on row 0.
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return out
    }
}
