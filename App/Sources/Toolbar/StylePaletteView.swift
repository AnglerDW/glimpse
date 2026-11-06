import AppKit
import GlimpseCore

@MainActor
protocol StylePaletteViewDelegate: AnyObject {
    func stylePaletteView(_ view: StylePaletteView, didPick style: AnnotationStyle)
}

/// The secondary bar under the toolbar (design doc §3.3): 6 preset colours | 3 widths. Shown only while
/// a tool is selected. Laid out like the mockup's `.sub` row: 14pt colour dots and 5 / 8 / 11pt width dots,
/// 8pt apart, 7pt above and below, 12pt at the ends, 2pt more on each side of the separator.
/// The dots are small, so each button is as tall as the bar and reaches half a gap past its dot on each
/// side: the click targets touch, with no dead space between neighbours.
final class StylePaletteView: MaterialView {
    weak var delegate: StylePaletteViewDelegate?

    private static let verticalPadding: CGFloat = 7
    private static let horizontalPadding: CGFloat = 12
    private static let spacing: CGFloat = 8
    private static let separatorMargin: CGFloat = 2
    /// The separator is the tallest item.
    private static let height = MaterialSeparatorView.size.height + verticalPadding * 2
    private var buttons: [PaletteButton] = []
    private var style = AnnotationStyle.standard
    private var colorsEnabled = true

    init() {
        super.init(cornerRadius: 12)
        // x is where the next dot starts, already past the gap after the previous one.
        var x = Self.horizontalPadding
        for color in PaletteColor.allCases {
            add(.color(color), x: &x)
        }
        contentView.addSubview(MaterialSeparatorView(origin: CGPoint(
            x: x + Self.separatorMargin, y: (Self.height - MaterialSeparatorView.size.height) / 2)))
        x += Self.separatorMargin * 2 + MaterialSeparatorView.size.width + Self.spacing
        for width in StrokeWidth.allCases {
            add(.width(width), x: &x)
        }
        frame.size = CGSize(width: x - Self.spacing + Self.horizontalPadding, height: Self.height)
    }

    private func add(_ choice: PaletteButton.Choice, x: inout CGFloat) {
        let dot = PaletteButton.dotDiameter(for: choice)
        let target = CGRect(x: x - Self.spacing / 2, y: 0, width: dot + Self.spacing, height: Self.height)
        let button = PaletteButton(choice: choice, frame: target, target: self, action: #selector(pressed(_:)))
        contentView.addSubview(button)
        buttons.append(button)
        x += dot + Self.spacing
    }

    /// Marks the shared colour and width. Mosaic has no colour, so its swatches are disabled.
    func show(_ style: AnnotationStyle, colorsEnabled: Bool = true) {
        self.style = style
        self.colorsEnabled = colorsEnabled
        for button in buttons {
            switch button.choice {
            case .color(let color):
                button.isChosen = colorsEnabled && color == style.color
                button.isEnabled = colorsEnabled
                button.alphaValue = colorsEnabled ? 1 : 0.35
                button.setAccessibilityHelp(colorsEnabled ? nil : String(localized: "马赛克不使用颜色", comment: "Accessibility: colour swatches disabled"))
            case .width(let width):
                button.isChosen = width == style.width
            }
        }
    }

    @objc private func pressed(_ sender: PaletteButton) {
        var picked = style
        switch sender.choice {
        case .color(let color): picked.color = color
        case .width(let width): picked.width = width
        }
        show(picked, colorsEnabled: colorsEnabled)
        delegate?.stylePaletteView(self, didPick: picked)
    }
}

/// A colour swatch or a width dot, centred in a larger click target. Draws itself so the swatch follows
/// light / dark (black ↔ white).
final class PaletteButton: NSButton {
    enum Choice {
        case color(PaletteColor)
        case width(StrokeWidth)
    }

    let choice: Choice

    var isChosen = false {
        didSet { if isChosen != oldValue { needsDisplay = true } }
    }
    /// Redraws the chosen swatch's accent ring when the accent changes.
    private var accentObservation: AccentObservation?

    /// Drawn sizes from the mockup: 14pt colour dots; 5, 8 and 11pt width dots.
    static func dotDiameter(for choice: Choice) -> CGFloat {
        switch choice {
        case .color: 14
        case .width(let width): [5, 8, 11][width.index]
        }
    }

    init(choice: Choice, frame: CGRect, target: AnyObject, action: Selector) {
        self.choice = choice
        super.init(frame: frame)
        title = ""
        isBordered = false
        refusesFirstResponder = true
        focusRingType = .none
        self.target = target
        self.action = action
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
        // VoiceOver names only: AppKit tooltips would sit behind the overlay (see ToolbarButton).
        switch choice {
        case .color(let color): setAccessibilityLabel(Self.colorNames[color])
        case .width(let width): setAccessibilityLabel(Self.widthNames[width.index])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let widthNames = [
        String(localized: "细", comment: "Accessibility: stroke width"),
        String(localized: "中", comment: "Accessibility: stroke width"),
        String(localized: "粗", comment: "Accessibility: stroke width"),
    ]

    private static let colorNames: [PaletteColor: String] = [
        .red: String(localized: "红", comment: "Accessibility: annotation colour"),
        .orange: String(localized: "橙", comment: "Accessibility: annotation colour"),
        .yellow: String(localized: "黄", comment: "Accessibility: annotation colour"),
        .green: String(localized: "绿", comment: "Accessibility: annotation colour"),
        .blue: String(localized: "蓝", comment: "Accessibility: annotation colour"),
        .black: String(localized: "黑（夜间为白）", comment: "Accessibility: annotation colour"),
    ]

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = Self.dotDiameter(for: choice) / 2
        func circle(_ r: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        switch choice {
        case .color(let color):
            if isChosen {
                // `.dot.cur`: a 2pt white ring, then 1.5pt of accent
                // (box-shadow: 0 0 0 2px white, 0 0 0 3.5px accent).
                NSColor.glimpseAccent.setFill()
                circle(radius + 3.5).fill()
                NSColor(white: 1, alpha: 0.95).setFill()
                circle(radius + 2).fill()
            }
            color.rgba(darkAppearance: effectiveAppearance.isDark).nsColor.setFill()
            circle(radius).fill()
            // A 1pt inner hairline (inset 0 0 0 1px, 12% black) keeps the white and black swatches visible.
            let edge = circle(radius - 0.5)
            edge.lineWidth = 1
            NSColor(white: 0, alpha: 0.12).setStroke()
            edge.stroke()
        case .width:
            // `.w`: the text colour, full strength for the current width and 75% for the others.
            NSColor.materialText.withAlphaComponent(isChosen ? 1 : 0.75).setFill()
            circle(radius).fill()
        }
    }
}

extension RGBA {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
