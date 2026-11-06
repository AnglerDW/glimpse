import CoreGraphics
import Foundation

/// The selecting-phase magnifier (design doc §3.2): zoomed pixels around the cursor with a "+" crosshair
/// crossing on the picked pixel, its pixel coordinate and colour value, and how to copy the colour.
/// Pixel coordinates are the frozen image's (top-left origin).
public enum Magnifier {
    /// Pixels shown per side; odd, so the cursor's pixel sits in the middle.
    public static let gridSize = 17
    /// Points per shown pixel. Odd, so a 1pt line splits a cell 3 + 1 + 3 and sits on its exact middle.
    public static let zoom: CGFloat = 7
    /// Side of the zoomed grid: 17 × 7 = 119pt.
    public static var gridSide: CGFloat { CGFloat(gridSize) * zoom }
    /// Padding between the panel's edge and the grid, and below the last hint row.
    public static let panelInset: CGFloat = 8
    /// Gap between the grid and the first info row.
    public static let infoGap: CGFloat = 8
    /// Height of one info row (位置, 颜色).
    public static let infoRowHeight: CGFloat = 18
    /// Info rows under the grid: the pixel coordinate and the colour (swatch + hex value).
    public static let infoRowCount = 2
    /// Gap between the last info row and the first hint row: the hints are their own, quieter group.
    public static let hintGap: CGFloat = 6
    /// Height of one hint row (10pt gray text).
    public static let hintRowHeight: CGFloat = 14
    /// Hint rows under the info rows: 「按 C 复制颜色值」 and 「按 ⇧C 复制 RGB」 (one line would need ~134pt).
    public static let hintRowCount = 2
    /// The whole panel: grid, info rows and hint rows, padded on every side (135 × 213pt).
    public static var panelSize: CGSize {
        CGSize(width: gridSide + panelInset * 2,
               height: panelInset + gridSide + infoGap + infoRowHeight * CGFloat(infoRowCount)
                   + hintGap + hintRowHeight * CGFloat(hintRowCount) + panelInset)
    }
    /// Top of info row `index` (0 = 位置) in the panel's flipped (top-left origin) coordinates.
    public static func infoRowY(_ index: Int) -> CGFloat {
        panelInset + gridSide + infoGap + infoRowHeight * CGFloat(index)
    }
    /// Top of hint row `index` in the panel's flipped coordinates.
    public static func hintRowY(_ index: Int) -> CGFloat {
        infoRowY(infoRowCount) + hintGap + hintRowHeight * CGFloat(index)
    }
    /// The "+" crosshair in the grid's own coordinates (a square, symmetric, so y-up and y-down agree):
    /// a 1pt line along the middle of the centre column and one along the centre row, both across the whole
    /// grid, crossing on the picked pixel. The horizontal line leaves out the 1pt where they cross, so a
    /// translucent fill does not darken the crossing twice: the rects never overlap. The centre cell starts
    /// on a whole point (8 × 7 = 56) and 7 = 3 + 1 + 3, so the lines sit on its exact middle and on whole
    /// points (crisp on 1× and 2×).
    public static var crosshairSegments: [CGRect] {
        let line = CGFloat(gridSize / 2) * zoom + ((zoom - 1) / 2).rounded() // 56 + 3 = 59
        let side = gridSide
        return [CGRect(x: line, y: 0, width: 1, height: side),                    // vertical, whole length
                CGRect(x: 0, y: line, width: line, height: 1),                    // horizontal, before the crossing
                CGRect(x: line + 1, y: line, width: side - line - 1, height: 1)]  // horizontal, after it
    }
    /// Gap between the cursor and the panel.
    public static let cursorOffset: CGFloat = 20
    /// Colour values are reported in sRGB; made once, not on every mouse move.
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The pixel under a screen-local point, clamped into the image (the mouse can rest on the last row).
    public static func pixel(at point: CGPoint, scale: CGFloat, imageWidth: Int, imageHeight: Int) -> CGPoint {
        let x = min(max(Int((point.x * scale).rounded(.down)), 0), imageWidth - 1)
        let y = min(max(Int((point.y * scale).rounded(.down)), 0), imageHeight - 1)
        return CGPoint(x: x, y: y)
    }

    /// The `gridSize` square of pixels centred on `pixel`. It may reach past the image near an edge;
    /// that part is shown empty.
    public static func sourceRect(around pixel: CGPoint) -> CGRect {
        let half = CGFloat(gridSize / 2)
        return CGRect(x: pixel.x - half, y: pixel.y - half, width: CGFloat(gridSize), height: CGFloat(gridSize))
    }

    /// One pixel's colour in 8-bit sRGB.
    public struct PixelColor: Equatable, Sendable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        /// `#0A1400` (uppercase hex) or `10, 20, 0`.
        public func text(_ format: ColorFormat) -> String {
            switch format {
            case .hex: String(format: "#%02X%02X%02X", red, green, blue)
            case .rgb: "\(red), \(green), \(blue)"
            }
        }
    }

    /// One pixel's colour, converted to sRGB (what design tools and CSS expect); nil outside the image.
    /// The pixel is cut out first, so the colour conversion covers one pixel, not the whole frozen frame
    /// (this runs on every mouse move).
    public static func color(of image: CGImage, atPixel pixel: CGPoint) -> PixelColor? {
        let x = Int(pixel.x), y = Int(pixel.y)
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let single = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(single, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return PixelColor(red: rgba[0], green: rgba[1], blue: rgba[2])
    }

    /// Below-right of the cursor; flips to the left / above where it would leave the screen. When that
    /// would touch `obstacle` (the camera housing on a notch screen), the other flips are tried before
    /// giving up and keeping the first choice.
    /// The cursor is rounded to whole points first (trackpads report fractional positions): an origin off
    /// the point grid would blur the zoomed cells, the crosshair and the text.
    public static func frame(size: CGSize, cursor rawCursor: CGPoint, screen: CGRect, obstacle: CGRect? = nil) -> CGRect {
        let cursor = CGPoint(x: rawCursor.x.rounded(), y: rawCursor.y.rounded())
        let right = cursor.x + cursorOffset, left = cursor.x - cursorOffset - size.width
        let below = cursor.y + cursorOffset, above = cursor.y - cursorOffset - size.height
        let x = right + size.width > screen.maxX - OverlayLayout.screenMargin ? left : right
        let y = below + size.height > screen.maxY - OverlayLayout.screenMargin ? above : below
        let first = CGRect(origin: CGPoint(x: x, y: y), size: size)
        guard !OverlayLayout.isClear(first, of: obstacle) else { return first }
        let others = [CGRect(origin: CGPoint(x: x, y: y == below ? above : below), size: size),
                      CGRect(origin: CGPoint(x: x == right ? left : right, y: y), size: size),
                      CGRect(origin: CGPoint(x: x == right ? left : right, y: y == below ? above : below), size: size)]
        let fits = others.first { $0.minX >= screen.minX && $0.minY >= screen.minY
            && $0.maxX <= screen.maxX && $0.maxY <= screen.maxY && OverlayLayout.isClear($0, of: obstacle) }
        return fits ?? first
    }
}
