import AppKit

/// A 30 × 30 icon button with an 8pt continuous corner (design doc §4.3). Selected: accent fill and
/// white icon, plus an accent glow (`.on` in the mockup) on macOS 14 / 15 only: on macOS 26 a coloured
/// shadow inside the Liquid Glass fights the system's own lighting, so the fill stands alone.
/// Never takes key focus, so keys keep going to the selection view.
/// Its tooltip is drawn by the overlay (see `onHover`), not by AppKit: AppKit's tooltip window sits
/// below the `.screenSaver` overlay and would be hidden behind it.
final class ToolbarButton: NSButton {
    static let side: CGFloat = 30
    /// The mockup's 17pt is the icon box: the glyphs drawn in it are about 8–11pt with 1.2pt strokes.
    /// SF Symbols regular strokes are about 0.09 × the point size, and 13pt gives both the glyph size
    /// (rectangle 18 × 14 image) and the stroke (about 1.17pt); 17pt is half as big again and heavier.
    static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    private static let cornerRadius: CGFloat = 8
    /// The selected glow belongs to the emulated macOS 14 / 15 material (see the type comment).
    private static let drawsGlow: Bool = {
        if #available(macOS 26, *) { return false }
        return true
    }()

    let item: ToolbarItem
    /// True once the mouse has rested on the button for `hoverDelay`; false when it leaves or presses.
    var onHover: ((ToolbarButton, Bool) -> Void)?
    private static let hoverDelay: TimeInterval = 0.6

    var isSelectedTool = false {
        didSet {
            if isSelectedTool != oldValue { refreshColors() }
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            alphaValue = isEnabled ? 1 : 0.35
            refreshColors()
        }
    }

    private var isHovered = false {
        didSet {
            if isHovered != oldValue { refreshColors() }
        }
    }

    /// Our own tracking area; NSButton keeps others that must not be removed.
    private var hoverArea: NSTrackingArea?
    /// Layer colours are CGColors: resolve them again when the accent changes.
    private var accentObservation: AccentObservation?

    init(item: ToolbarItem, target: AnyObject, action: Selector) {
        self.item = item
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        (cell as? NSButtonCell)?.imageDimsWhenDisabled = false // disabled look comes from alphaValue alone
        image = Self.image(for: item)
        if image == nil { title = item.title } // unknown symbol name: still a usable button
        setAccessibilityLabel(item.toolTip)
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        if Self.drawsGlow { // the glow is the rounded box's shadow, not the icon's
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius,
                                       cornerHeight: Self.cornerRadius, transform: nil)
        }
        self.target = target
        self.action = action
        refreshColors()
        accentObservation = AccentObservation { [weak self] in self?.refreshColors() }
    }

    /// The button's glyph: an SF Symbol, except the text tool, which is a plain "A" drawn from the
    /// system font. The `character` / `textformat` symbols are localised by the system (字 on a
    /// Chinese system, あ on Japanese), and the text tool must read as the same "A" everywhere
    /// (user feedback).
    private static func image(for item: ToolbarItem) -> NSImage? {
        if case .tool(.text) = item { return letterA }
        return NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)?
            .withSymbolConfiguration(symbolConfiguration)
    }

    /// "A" at the symbols' size, as a template image so it takes the same colour as the symbols.
    private static let letterA: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let font = NSFont.systemFont(ofSize: 14.5, weight: .medium)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: NSColor.black]))
            // Centre the ink, not the line box: the glyph's path bounds (relative to the baseline origin) say
            // exactly where the strokes are, so the A sits in the middle of the button like the symbols do.
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(x: (rect.width - ink.width) / 2 - ink.minX,
                                           y: (rect.height - ink.height) / 2 - ink.minY)
            CTLineDraw(line, context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "文字", comment: "Toolbar: tool name")
        return image
    }()

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
        // A new area sends neither an exit nor an enter event, so settle the hover by hand: the mouse is on
        // the button's new position (a nudge moved the toolbar by a point) -> keep hovering and show the
        // tooltip again at the new spot; the button moved away from the mouse -> end the hover.
        guard let window else { return }
        if bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            if !isHidden { beginHover() }
        } else {
            resetHover()
        }
    }

    /// Forgets any hover: clears the highlight and cancels a pending tooltip. Called when the toolbar moves
    /// or hides under a mouse that did not move, which produces no exit event.
    func resetHover() {
        isHovered = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
    }

    override func viewDidHide() {
        super.viewDidHide()
        resetHover()
    }

    override func mouseEntered(with event: NSEvent) {
        beginHover()
    }

    /// Highlights the button and starts the tooltip timer (restarting it if one is pending).
    private func beginHover() {
        isHovered = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
        perform(#selector(hoverDelayElapsed), with: nil, afterDelay: Self.hoverDelay)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        endHover()
    }

    override func mouseDown(with event: NSEvent) {
        endHover() // pressing hides the tooltip, as in AppKit
        super.mouseDown(with: event)
    }

    @objc private func hoverDelayElapsed() {
        onHover?(self, true)
    }

    private func endHover() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hoverDelayElapsed), object: nil)
        onHover?(self, false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    /// Layer colours are CGColors and do not follow appearance changes on their own; resolve them here.
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill: NSColor?
            if isSelectedTool {
                fill = .glimpseAccent
            } else if isHovered && isEnabled {
                fill = NSColor.labelColor.withAlphaComponent(0.12)
            } else {
                fill = nil
            }
            layer?.backgroundColor = fill?.cgColor
            // Glow under the selected button: 0 2px 8px at 45% in light, 0 2px 10px at 60% in dark.
            // AppKit gives a flipped view's layer a y-down space, so the offset's sign follows isFlipped.
            if Self.drawsGlow {
                let dark = effectiveAppearance.isDark
                layer?.shadowColor = NSColor.glimpseAccent.cgColor
                layer?.shadowOpacity = isSelectedTool ? (dark ? 0.6 : 0.45) : 0
                layer?.shadowRadius = dark ? 5 : 4
                layer?.shadowOffset = CGSize(width: 0, height: isFlipped ? 2 : -2)
            }
            if isSelectedTool {
                contentTintColor = .white
            } else {
                contentTintColor = item == .confirm ? .glimpseAccent : .materialText
            }
        }
    }
}
