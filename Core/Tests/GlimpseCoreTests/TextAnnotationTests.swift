import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import GlimpseCore

private let black = RGBA(hex: 0x000000)

/// Dark pixels of `image` in rows `rows`, across the whole width.
private func darkPixels(_ image: CGImage, rows: Range<Int>) -> Int {
    var n = 0
    for y in rows {
        for x in 0..<image.width where TestImage.pixel(image, x: x, y: y)[0] < 128 { n += 1 }
    }
    return n
}

private func bytes(_ image: CGImage) -> [UInt8] {
    Array(image.dataProvider!.data! as Data)
}

/// What the text box shows on a `scale` screen, built without TextLayout: the system font at the point
/// size, each baseline at the bottom of its fixed-height line minus the descent rounded to whole points
/// (the box tells TextKit to put it there), all scaled up to pixels.
private func boxEquivalent(_ string: String, origin: CGPoint, pointSize: CGFloat, scale: CGFloat,
                           width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    let font = CTFontCreateUIFontForLanguage(.system, pointSize, nil)!
    let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    for (index, line) in string.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !line.isEmpty {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: black.cgColor] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, String(line) as CFString, attributes)!
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(index + 1) * lineHeight - CTFontGetDescent(font).rounded())
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

struct TextAnnotationTests {
    @Test func blankTextBoxIsDropped() {
        #expect(Annotation.text(origin: .zero, string: "", color: black, size: 20, scale: 1) == nil)
        #expect(Annotation.text(origin: .zero, string: " \n\t", color: black, size: 20, scale: 1) == nil)
        #expect(Annotation.text(origin: .zero, string: "a\n", color: black, size: 40, scale: 2)?.shape
                == .text(origin: .zero, string: "a\n", scale: 2))
    }

    @Test func clickCentresTheFirstLine() {
        // 40 pixels on a 2x screen: a 20pt line, twice as tall in pixels.
        let origin = Annotation.textOrigin(forClickAt: CGPoint(x: 100, y: 100), fontSize: 40, scale: 2)
        #expect(origin == CGPoint(x: 100, y: 100 - TextLayout.lineHeight(fontSize: 20)))
    }

    @Test func textIsDrawnUpright() throws {
        // A "T": its bar (top of the capitals) is much wider than the foot of its stem (at the baseline).
        let annotation = try #require(Annotation.text(origin: .zero, string: "T", color: black, size: 40, scale: 1))
        let image = TestImage.render([annotation], width: 60, height: 60)
        let baseline = Int(TextLayout.baseline(line: 0, fontSize: 40))
        let capTop = baseline - Int(CTFontGetCapHeight(TextLayout.font(size: 40)).rounded())
        let bar = darkPixels(image, rows: capTop..<(capTop + 3))
        let foot = darkPixels(image, rows: (baseline - 3)..<baseline)
        #expect(bar > foot * 2)
    }

    @Test func secondLineStartsOneLineHeightLower() throws {
        let annotation = try #require(Annotation.text(origin: .zero, string: "\nT", color: black, size: 20, scale: 1))
        let image = TestImage.render([annotation], width: 40, height: 60)
        let lineHeight = Int(TextLayout.lineHeight(fontSize: 20))
        #expect(darkPixels(image, rows: 0..<lineHeight) == 0)
        #expect(darkPixels(image, rows: lineHeight..<(lineHeight * 2)) > 0)
    }

    @Test func baselineIsTheLineBottomMinusTheRoundedDescent() throws {
        let lineHeight = TextLayout.lineHeight(fontSize: 40)
        let descent = CTFontGetDescent(TextLayout.font(size: 40)).rounded()
        #expect(TextLayout.baseline(line: 1, fontSize: 40) == 2 * lineHeight - descent)
        // The renderer stands a "T" on that baseline.
        let annotation = try #require(Annotation.text(origin: .zero, string: "T", color: black, size: 40, scale: 1))
        let image = TestImage.render([annotation], width: 60, height: 60)
        let baseline = Int(TextLayout.baseline(line: 0, fontSize: 40))
        #expect(darkPixels(image, rows: (baseline - 2)..<baseline) > 0)
        #expect(darkPixels(image, rows: (baseline + 1)..<(baseline + 4)) == 0)
    }

    @Test func textIsLaidOutInPointsLikeTheTextBox() throws {
        // Fallback fonts (Chinese, Japanese, emoji) size themselves from the font size they are given, so
        // laying out at the pixel size would come out wider or narrower than the box on a Retina screen.
        let samples = ["中文标点，。！", "こんにちは", "😀👍", "Mixed 中英 text，ok！\nLine 2 第二行"]
        let origin = CGPoint(x: 3, y: 2.5)
        for scale in [1, 1.5, 2, 3] as [CGFloat] {
            for string in samples {
                let annotation = try #require(Annotation.text(origin: origin, string: string, color: black,
                                                              size: 20 * scale, scale: scale))
                let bounds = annotation.bounds
                let width = Int(bounds.maxX) + 20, height = Int(bounds.maxY) + 20
                let rendered = TestImage.render([annotation], width: width, height: height)
                #expect(bytes(rendered) == bytes(boxEquivalent(string, origin: origin, pointSize: 20, scale: scale,
                                                               width: width, height: height)))
                // The bounds cover every painted pixel, including fallback glyphs taller than the line.
                let pixels = bytes(rendered)
                var outside = 0
                for y in 0..<height {
                    for x in 0..<width where !bounds.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        let i = y * rendered.bytesPerRow + x * 4
                        if pixels[i..<(i + 3)].contains(where: { $0 < 250 }) { outside += 1 }
                    }
                }
                #expect(outside == 0, "\(string) at \(scale)x")
            }
        }
    }
}
