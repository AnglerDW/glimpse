import AppKit
import GlimpseCore

/// The selecting-phase magnifier next to the cursor (design doc §3.2): 17 × 17 frozen pixels at 7× with a
/// "+" crosshair crossing on the picked (centre) pixel; then two justified rows, 「位置」 with the pixel
/// coordinate and 「颜色」 with a swatch and the hex value (labels on the grid's left edge, values on its right
/// edge), and two quieter gray hint rows saying which key copies the colour. Clicks pass through.
/// Light / dark: every text colour is a dynamic NSColor, which labels resolve again on their own when the
/// appearance changes; the drawn parts (swatch edge, crosshair) redraw in `viewDidChangeEffectiveAppearance`.
final class MagnifierView: MaterialView {
    /// The rows reach this far past the grid so the label text itself lines up with the grid's edges.
    private static let textInset = NSTextField.labelTextInset
    private static let panelCornerRadius: CGFloat = 12
    /// Fully monospaced, not just monospaced digits: the hex letters A–F are proportional in the system
    /// font, so a right-aligned `#A1F00B` would jitter as the cursor moves.
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let captionFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// Regular weight and the tertiary gray: the hints sit below the values, not beside them.
    private static let hintFont = NSFont.systemFont(ofSize: 10)
    private static let hints = [String(localized: "按 C 拷贝颜色值", comment: "Magnifier hint"),
                                String(localized: "按 ⇧C 拷贝 RGB", comment: "Magnifier hint")]
    private static let swatchSide: CGFloat = 12
    /// Between the swatch and the hex value.
    private static let swatchGap: CGFloat = 6

    private let pixels: ZoomedPixelsView
    private let coordinateValue = NSTextField(labelWithString: "")
    private let hexValue = NSTextField(labelWithString: "")
    private let swatch = ColorSwatchView()
    private var shownPixel: CGPoint?

    init(image: CGImage) {
        let inset = Magnifier.panelInset, side = Magnifier.gridSide
        pixels = ZoomedPixelsView(image: image, frame: CGRect(x: inset, y: inset, width: side, height: side))
        super.init(cornerRadius: Self.panelCornerRadius)
        // Concentric with the panel's corner: outer radius minus the inset.
        pixels.layer?.cornerRadius = Self.panelCornerRadius - inset
        contentView.addSubview(pixels)
        let textX = inset - Self.textInset, textWidth = side + Self.textInset * 2
        // The value's line, centred in its taller row; the caption shares its baseline.
        let valueFont = Self.valueFont
        let valueHeight = ceil(valueFont.ascender - valueFont.descender + valueFont.leading)
        let valueTop = ((Magnifier.infoRowHeight - valueHeight) / 2).rounded()
        for (index, (caption, value)) in [(String(localized: "位置", comment: "Magnifier: pixel position caption"), coordinateValue),
                                           (String(localized: "颜色", comment: "Magnifier: colour caption"), hexValue)].enumerated() {
            let row = CGRect(x: textX, y: Magnifier.infoRowY(index) + valueTop, width: textWidth, height: valueHeight)
            let captionLabel = NSTextField(labelWithString: caption)
            captionLabel.font = Self.captionFont
            captionLabel.textColor = .materialSecondaryText
            // Labels draw top-aligned; drop the smaller caption so both texts share one baseline.
            captionLabel.frame = row.offsetBy(dx: 0, dy: (Self.valueFont.ascender - Self.captionFont.ascender).rounded())
            value.font = Self.valueFont
            value.textColor = .materialText
            value.alignment = .right
            value.frame = row
            contentView.addSubview(captionLabel)
            contentView.addSubview(value)
        }
        // The swatch sits left of the hex value, centred on its capitals. Every hex value is seven monospaced
        // characters wide, so the swatch never moves.
        let hexWidth = ("#000000" as NSString).size(withAttributes: [.font: Self.valueFont]).width
        let capMiddle = Magnifier.infoRowY(1) + valueTop + valueFont.ascender - valueFont.capHeight / 2
        swatch.frame = CGRect(x: (inset + side - hexWidth - Self.swatchGap - Self.swatchSide).rounded(),
                              y: (capMiddle - Self.swatchSide / 2).rounded(),
                              width: Self.swatchSide, height: Self.swatchSide)
        contentView.addSubview(swatch)
        for (index, hint) in Self.hints.enumerated() {
            let label = NSTextField(labelWithString: hint)
            label.font = Self.hintFont
            label.textColor = .materialTertiaryText
            label.frame = CGRect(x: textX, y: Magnifier.hintRowY(index), width: textWidth, height: Magnifier.hintRowHeight)
            contentView.addSubview(label)
        }
        frame.size = Magnifier.panelSize
    }

    /// Shows the pixel at `pixel` (frozen-image coordinates). Moves within one pixel change nothing.
    /// ⇧C copies the RGB value (SelectionView); only the hint mentions it.
    func show(pixel: CGPoint) {
        guard pixel != shownPixel else { return }
        shownPixel = pixel
        pixels.center = pixel
        coordinateValue.stringValue = "\(Int(pixel.x)), \(Int(pixel.y))"
        let color = Magnifier.color(of: pixels.image, atPixel: pixel)
        hexValue.stringValue = color?.text(.hex) ?? ""
        swatch.color = color.map {
            NSColor(srgbRed: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The picked colour as a small rounded square, with a hairline edge so white on light glass and black on
/// dark glass still read as a square. Drawn, so the edge colour follows the appearance.
private final class ColorSwatchView: NSView {
    private static let edge = NSColor.adaptive(light: NSColor(white: 0, alpha: 0.2), dark: NSColor(white: 1, alpha: 0.3))
    var color: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        let shape = bounds.insetBy(dx: 0.25, dy: 0.25)
        let path = NSBezierPath(roundedRect: shape, xRadius: 3, yRadius: 3)
        color.setFill()
        path.fill()
        path.lineWidth = 0.5
        Self.edge.setStroke()
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true // the edge colour is resolved per appearance
    }
}

/// Draws the zoomed pixels. Not flipped: CGImage drawing is y-up, so the maths stays plain.
private final class ZoomedPixelsView: NSView {
    let image: CGImage
    var center: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    /// Redraws the crosshair when the accent changes.
    private var accentObservation: AccentObservation?

    init(image: CGImage, frame: CGRect) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        bounds.fill() // past the image edge: "no pixels", the same black in light and dark (design doc §3.2)
        let source = Magnifier.sourceRect(around: center)
        let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // cropping(to:) shares the frame's pixels; this small view never outlives the overlay.
        if !visible.isNull, let piece = image.cropping(to: visible) {
            let zoom = Magnifier.zoom
            context.interpolationQuality = .none
            context.draw(piece, in: CGRect(x: (visible.minX - source.minX) * zoom,
                                           y: (source.maxY - visible.maxY) * zoom,
                                           width: visible.width * zoom, height: visible.height * zoom))
        }
        // The "+" crosshair: 1pt accent lines along the middle of the centre column and row, at 60% so the
        // pixels under them still read, crossing on the picked pixel. The rects never overlap
        // (Magnifier.crosshairSegments), so the crossing is not darkened twice, and they sit on whole
        // points, so crisp on 1× and 2×. AppKit draws with this view's appearance current, so the accent
        // colour resolves for it here.
        NSColor.glimpseAccent.withAlphaComponent(0.6).setFill()
        Magnifier.crosshairSegments.forEach { $0.fill(using: .sourceOver) } // fill() alone copies, not blends
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true // the accent crosshair is resolved per appearance
    }
}
