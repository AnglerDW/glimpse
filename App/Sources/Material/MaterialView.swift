import AppKit

/// The one material behind all Glimpse chrome (design doc §4.1): Liquid Glass (`NSGlassEffectView`)
/// on macOS 26+, frosted glass (`NSVisualEffectView`) on macOS 14 / 15, with the same continuous
/// corner radius on both. Callers add subviews to `contentView` and never see which one is in use.
/// Light / dark follows the window's effective appearance, which follows the system.
///
/// macOS 26: the native `NSGlassEffectView` (`.regular`, no tint) and nothing else. The system glass
/// draws its own edge highlight, refraction and shadow; any tint, rim, sheen or shadow of ours on top
/// muddied it, and the translucent middle let our drop shadow show through.
///
/// macOS 14 / 15: the blur cannot look like the mockup (`radius-v2.html`, `.glass`) on its own, so it
/// gets emulated decorations (`EmulatedGlass`, which exists only there): a light tint, a soft drop shadow,
/// a 1pt specular rim and a 0.5pt inner hairline, and a sheen across the top. None of them takes clicks.
/// Bottom to top:
/// - `shadowView`: the drop shadow, outside the shape only (see `EmulatedGlass.layout`)
/// - the effect view, clipped to the corner radius; it holds `tintView` under `contentView`
///   - `contentView`: `sheenView` first, so everything callers add draws above the sheen
/// - `rimView`: hairline and specular rim along the edge
///
/// Keep it that way: on macOS 26 neither this view nor any ancestor of the glass (the overlay content
/// view, the window) sets a layer mask, `masksToBounds`, a shadow or an alpha below 1. A group like that
/// can force the glass into an offscreen pass, where it loses its refraction and reads as a flat blur.
class MaterialView: NSView {
    /// Flipped, like the overlay: subviews are laid out from the top-left.
    let contentView: NSView = FlippedView()

    /// The continuous corner radius of the glass (and, on macOS 14 / 15, its rim and shadow). Labels set it
    /// as their height changes.
    var cornerRadius: CGFloat {
        didSet {
            if cornerRadius != oldValue { applyCornerRadius() }
        }
    }

    /// macOS 26+: the system glass, used as-is.
    private let systemGlass: NSView?
    /// macOS 14 / 15: the blur and its decorations.
    private let emulated: EmulatedGlass?

    /// `blendsBehindWindow`: for a window of its own (onboarding, OCR result), whose glass shows what is
    /// behind the window. The overlay's chrome blurs the frozen screen inside its window instead.
    /// `compactShadow`: a small control (the pin's 20pt ✕): on macOS 14 / 15 a tight 1pt shadow instead of
    /// the panels' soft 30px one, which would smear far past it. macOS 26's glass draws its own.
    init(cornerRadius: CGFloat, blendsBehindWindow: Bool = false, compactShadow: Bool = false) {
        self.cornerRadius = cornerRadius
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular  // the standard toolbar glass; .clear is for over rich media, needs a dimming layer
            glass.tintColor = nil   // the system's own adaptive glass
            glass.contentView = contentView
            systemGlass = glass
            emulated = nil
        } else {
            systemGlass = nil
            emulated = EmulatedGlass(contentView: contentView, blendsBehindWindow: blendsBehindWindow,
                                     compactShadow: compactShadow)
        }
        super.init(frame: .zero)
        if let systemGlass {
            systemGlass.autoresizingMask = [.width, .height]
            addSubview(systemGlass)
        }
        emulated?.install(in: self)
        applyCornerRadius()
        emulated?.refreshColors(for: effectiveAppearance)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Subclasses size themselves by setting `frame`; the macOS 14 / 15 decorations follow here.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        emulated?.layout(bounds: bounds, cornerRadius: cornerRadius)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        emulated?.refreshColors(for: effectiveAppearance)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The window's appearance may differ from the app's one seen in init.
        emulated?.refreshColors(for: effectiveAppearance)
    }

    private func applyCornerRadius() {
        if #available(macOS 26, *), let glass = systemGlass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
        // Also rounds the macOS 14 / 15 blur, whose mask is drawn at the exact size.
        emulated?.layout(bounds: bounds, cornerRadius: cornerRadius)
    }
}

/// The macOS 14 / 15 material: `NSVisualEffectView` plus the mockup's decorations. Never created on
/// macOS 26 (see `MaterialView`).
@MainActor
private final class EmulatedGlass {
    private let effect = NSVisualEffectView()
    private let shadowView = DecorationView()
    private let tintView = DecorationView()
    private let sheenView = DecorationView()
    private let rimView = DecorationView()

    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let hairlineLayer = CALayer()
    private let rimLayer = CAGradientLayer()
    private let rimMask = CALayer()
    /// Size and radius the blur mask was drawn for; it is redrawn only when one changes.
    private var maskedShape: (size: CGSize, radius: CGFloat)?

    /// How far the shadow reaches past the shape: blur radius plus offset, with room to spare.
    private static let shadowReach: CGFloat = 50

    /// A small control's tight shadow instead of the panels' soft one.
    private let compactShadow: Bool

    init(contentView: NSView, blendsBehindWindow: Bool, compactShadow: Bool) {
        self.compactShadow = compactShadow
        effect.material = .popover          // adapts to light / dark; .hudWindow is always dark
        // Overlay chrome blurs the frozen screen in its own window; a window of its own blurs what is behind it.
        effect.blendingMode = blendsBehindWindow ? .behindWindow : .withinWindow
        effect.state = .active              // the overlay is never in the active app, so never look inactive
        effect.addSubview(tintView)         // the blur has no tint of its own; a layer above it supplies one
        effect.addSubview(contentView)
        contentView.autoresizingMask = [.width, .height]
        contentView.addSubview(sheenView)

        shadowLayer.mask = shadowMask
        shadowMask.fillRule = .evenOdd
        shadowView.layer?.addSublayer(shadowLayer)
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.masksToBounds = true
        sheenLayer.cornerRadius = 6
        sheenLayer.cornerCurve = .continuous
        sheenView.layer?.addSublayer(sheenLayer)
        for layer in [hairlineLayer, rimMask] {
            layer.cornerCurve = .continuous
        }
        hairlineLayer.borderWidth = 0.5
        rimMask.borderWidth = 1
        rimMask.borderColor = NSColor.black.cgColor // a mask only uses alpha
        rimLayer.mask = rimMask
        rimLayer.locations = [0, 0.35, 0.6, 1]
        rimView.layer?.addSublayer(hairlineLayer)
        rimView.layer?.addSublayer(rimLayer)
    }

    /// Adds the shadow, the blur (holding the content view) and the rim to `host`, bottom to top.
    func install(in host: NSView) {
        for view in [shadowView, effect, rimView] {
            host.addSubview(view)
        }
    }

    /// Sizes every decoration layer to `bounds` and `cornerRadius`. Done without implicit animations:
    /// added CALayers would otherwise ease into a new size for 0.25s.
    func layout(bounds: CGRect, cornerRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        effect.frame = bounds
        let size = bounds.size
        if size.width > 0, size.height > 0,
           maskedShape?.size != size || maskedShape?.radius != cornerRadius {
            maskedShape = (size, cornerRadius)
            effect.maskImage = Self.maskImage(size: size, cornerRadius: cornerRadius) // Apple's way to round it
        }
        for view in [shadowView, rimView] {
            view.frame = bounds
        }
        tintView.frame = CGRect(origin: .zero, size: size)
        tintView.layer?.cornerRadius = cornerRadius

        // Shadow: the rounded rect casts it, and the mask cuts the shape itself out, so the shadow never
        // darkens the see-through glass from below (CSS box-shadow is outside-only too). CGPath only has
        // circular corners, which differ from the continuous ones by a fraction of a point, so the cut-out
        // is 1pt smaller: its edge then lies under the 1pt rim instead of leaving a hairline gap at the corners.
        let corner = min(cornerRadius, size.width / 2, size.height / 2) // CGPath traps on a larger radius
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let reach = Self.shadowReach
        shadowMask.frame = bounds.insetBy(dx: -reach, dy: -reach)
        let inner = bounds.insetBy(dx: 1, dy: 1).offsetBy(dx: reach, dy: reach)
        let innerCorner = max(0, min(corner - 1, inner.width / 2, inner.height / 2))
        let cutOut = CGMutablePath()
        cutOut.addRect(shadowMask.bounds)
        if inner.width > 0, inner.height > 0 {
            cutOut.addRoundedRect(in: inner, cornerWidth: innerCorner, cornerHeight: innerCorner)
        }
        shadowMask.path = cutOut

        // Sheen: inset 12% left and right, 1pt from the top, 45% of the height (`.glass::after`).
        sheenView.frame = CGRect(x: size.width * 0.12, y: 1, width: size.width * 0.76, height: size.height * 0.45)
        sheenLayer.frame = sheenView.bounds

        for layer in [hairlineLayer, rimMask] as [CALayer] {
            layer.frame = bounds
            layer.cornerRadius = cornerRadius
        }
        rimLayer.frame = bounds
        (rimLayer.startPoint, rimLayer.endPoint) = Self.cssGradientPoints(degrees: 160, size: size)
    }

    /// Start and end of CSS `linear-gradient(<degrees>deg, …)` in a box of `size`, as unit points.
    /// CSS angles run clockwise from "to top", and the line is long enough that the corners land exactly
    /// on the first and last stop. The decoration views are flipped, so their layers' y runs down as in CSS.
    private static func cssGradientPoints(degrees: CGFloat, size: CGSize) -> (CGPoint, CGPoint) {
        guard size.width > 0, size.height > 0 else { return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)) }
        let angle = degrees * .pi / 180
        let direction = CGPoint(x: sin(angle), y: -cos(angle))
        let half = (abs(size.width * sin(angle)) + abs(size.height * cos(angle))) / 2
        let dx = direction.x * half / size.width
        let dy = direction.y * half / size.height
        return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    // MARK: - Colours

    /// Light and dark values from the mockup (`.L .glass` / `.D .glass`). Layer colours are CGColors and
    /// do not follow appearance changes on their own, so they are resolved again on every change.
    func refreshColors(for appearance: NSAppearance) {
        let dark = appearance.isDark
        let tint = dark ? NSColor(srgbRed: 40 / 255, green: 40 / 255, blue: 48 / 255, alpha: 0.32)
                        : NSColor(white: 1, alpha: 0.28)
        tintView.layer?.backgroundColor = tint.cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Shadow: 0 10px 30px; a CSS blur of 30 is a Core Animation radius of about 15. +y is down: the
        // shadow view is flipped, and AppKit gives a flipped view's layer a y-down space.
        shadowLayer.shadowColor = NSColor.black.cgColor
        if compactShadow {
            shadowLayer.shadowOpacity = dark ? 0.5 : 0.25
            shadowLayer.shadowRadius = 1.5
            shadowLayer.shadowOffset = CGSize(width: 0, height: 1)
        } else {
            shadowLayer.shadowOpacity = dark ? 0.45 : 0.18
            shadowLayer.shadowRadius = 15
            shadowLayer.shadowOffset = CGSize(width: 0, height: 10)
        }

        hairlineLayer.borderColor = NSColor(white: 1, alpha: dark ? 0.18 : 0.5).cgColor
        let rim: [CGFloat] = dark ? [0.55, 0.08, 0, 0.30] : [0.95, 0.15, 0, 0.55]
        rimLayer.colors = rim.map { NSColor(white: 1, alpha: $0).cgColor }
        let sheen: CGFloat = dark ? 0.12 : 0.35
        sheenLayer.colors = [NSColor(white: 1, alpha: sheen).cgColor, NSColor(white: 1, alpha: 0).cgColor]
    }

    // MARK: - Mask

    /// The blur's shape at its exact size: a rounded rect with continuous corners, like the rim drawn over it.
    /// Drawn whole rather than as stretchable caps: a continuous corner bends over about 1.53 × the radius,
    /// which on a short label is more than half its height, so no cap insets would fit.
    private static func maskImage(size: CGSize, cornerRadius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shape = CALayer()
            shape.frame = rect
            shape.cornerRadius = cornerRadius
            shape.cornerCurve = .continuous
            shape.backgroundColor = NSColor.black.cgColor
            shape.render(in: context)
            return true
        }
    }
}

/// A plain container with a top-left origin.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A layer-backed view that only shows something and never takes a click: hit testing skips it, so clicks
/// and right clicks reach the buttons or the material underneath exactly as without it.
private final class DecorationView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The 1 × 16pt line between groups on the material (`.sep` in the mockup): 15% black in light,
/// 18% white in dark. Drawn, so AppKit resolves the colour again whenever the appearance changes.
final class MaterialSeparatorView: NSView {
    static let size = CGSize(width: 1, height: 16)
    private static let color = NSColor.adaptive(light: NSColor(white: 0, alpha: 0.15),
                                                dark: NSColor(white: 1, alpha: 0.18))

    init(origin: CGPoint) {
        super.init(frame: CGRect(origin: origin, size: Self.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        Self.color.setFill()
        bounds.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSTextField {
    /// A label draws its text this far in from each side (the line fragment padding), which
    /// `intrinsicContentSize` leaves out. Text meant to line up with an edge is placed this much past it.
    static let labelTextInset: CGFloat = 2
}

extension NSAppearance {
    /// True for the dark appearances, including their high-contrast variants.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// A colour that AppKit resolves for the current appearance each time it draws with it.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }

    /// Icons and text on the material, from the mockup: near-black in light, near-white in dark.
    static let materialText = adaptive(light: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1),
                                       dark: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1))

    /// Captions on the material (the magnifier's 「位置」 / 「颜色」): the text colour at 55%.
    static let materialSecondaryText = adaptive(
        light: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 0.55),
        dark: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 0.55))

    /// Hints on the material (the magnifier's 「按 C 复制颜色值」): a quieter gray, the text colour at 40%.
    static let materialTertiaryText = adaptive(
        light: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 0.4),
        dark: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 0.4))
}
