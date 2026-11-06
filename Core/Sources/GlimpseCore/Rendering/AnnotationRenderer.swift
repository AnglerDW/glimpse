import CoreGraphics
import CoreText

extension Renderer {
    /// Draws `annotations` in order. The context's CTM must map frozen-image pixels (top-left origin,
    /// y down) onto the target: the overlay view scales points to pixels, the export translates to the crop.
    /// Both call this, so what is on screen is what gets copied (design doc §5.2).
    /// `pixelated(blockSize)` returns the frozen frame pixelated in blocks of that size, for mosaic.
    /// It has no default: a caller that forgot it would leave mosaicked areas unredacted.
    public static func draw(_ annotations: [Annotation], in context: CGContext,
                            pixelated: (Int) -> CGImage?) {
        for annotation in annotations {
            context.saveGState()
            draw(annotation, in: context, pixelated: pixelated)
            context.restoreGState()
        }
    }

    private static func draw(_ annotation: Annotation, in context: CGContext, pixelated: (Int) -> CGImage?) {
        let color = annotation.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.size)
        switch annotation.shape {
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .arrow(let from, let to):
            context.addPath(ShapeGeometry.arrowPath(from: from, to: to, lineWidth: annotation.size))
            context.fillPath()
        case .pen(let points):
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(ShapeGeometry.smoothedPath(through: points))
            context.strokePath()
        case .counter(let center, let number):
            drawCounter(number, center: center, diameter: annotation.size, color: annotation.color, in: context)
        case .mosaic(let points, let blockSize):
            guard let blocks = pixelated(blockSize) else {
                assertionFailure("mosaic drawn without a pixelated source")
                break
            }
            // Clip to the brush stroke, then show the pixelated frame through it.
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(ShapeGeometry.smoothedPath(through: points))
            context.replacePathWithStrokedPath()
            context.clip()
            context.interpolationQuality = .none // hard block edges
            drawUpright(blocks, in: CGRect(x: 0, y: 0, width: blocks.width * blockSize,
                                           height: blocks.height * blockSize), context: context)
        case .text(let origin, let string, let scale):
            // Laid out in points and scaled up, exactly like the text box on screen (see Annotation.Shape.text).
            let pointSize = annotation.size / scale
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            for (index, text) in TextLayout.lines(of: string).enumerated() where !text.isEmpty {
                let baseline = CGPoint(x: 0, y: TextLayout.baseline(line: index, fontSize: pointSize))
                TextLayout.draw(TextLayout.line(text, fontSize: pointSize, color: color), baselineOrigin: baseline, in: context)
            }
        }
    }

    /// `CGContext.draw(_:in:)` assumes y-up; in a y-down context it would draw the image upside down.
    static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// A filled badge with a bold number; dark digits on light fills (yellow, white), white digits otherwise.
    private static func drawCounter(_ number: Int, center: CGPoint, diameter: CGFloat, color: RGBA, in context: CGContext) {
        context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                       width: diameter, height: diameter))
        let digits = String(number)
        let fontSize = diameter * (digits.count == 1 ? 0.6 : digits.count == 2 ? 0.5 : 0.38)
        let textColor = color.prefersDarkText ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                                              : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let line = TextLayout.line(digits, fontSize: fontSize, color: textColor, bold: true)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let capHeight = CTFontGetCapHeight(TextLayout.font(size: fontSize, bold: true))
        TextLayout.draw(line, baselineOrigin: CGPoint(x: center.x - width / 2, y: center.y + capHeight / 2), in: context)
    }
}
