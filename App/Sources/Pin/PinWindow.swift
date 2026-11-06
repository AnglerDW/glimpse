import AppKit
import GlimpseCore

/// One pinned screenshot (design doc §3.6): always on top, borderless, with a shadow. Drag to move,
/// scroll (or pinch) to zoom about the mouse; close with the round ✕ shown at the top-left corner while the
/// mouse is over the pin, or by double click; the right-click menu copies, saves, sets the opacity or closes. Holds only the composed image, in memory (§1: nothing is written to disk).
/// A non-activating panel that never takes the keyboard, so pinning leaves the active app alone.
final class PinWindow: NSPanel {
    enum Command {
        case copy, save, close
    }

    let image: CGImage
    let scale: CGFloat
    /// What the controller does for a menu item or a double click.
    var onCommand: ((PinWindow, Command) -> Void)?

    /// The image's size at 100%, in points.
    private var imageSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
    private var zoomFactor: CGFloat = 1

    /// `frame` is where the selection was, in AppKit global coordinates: the pin appears right on top of it.
    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(contentRect: CGRect(origin: frame.origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // The floating level: above normal windows, below the overlay (.screenSaver), so a capture covers it.
        // It is also below the Dock and the menu bar; accepted, a pin dragged there just slides under them.
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinImageView(image: image)
        view.attach(to: self)
        contentView = view
    }

    /// Shows the ✕ if the mouse is already over the pin (it appears under the mouse, where no "entered"
    /// event comes).
    func refreshHover() {
        (contentView as? PinImageView)?.refreshHover()
    }

    /// While a capture freezes the screen the ✕ stays hidden, so it never ends up in the screenshot.
    /// Returns whether it was on screen (the capture then waits for the window server to drop it).
    func setCloseButtonSuppressed(_ suppressed: Bool) -> Bool {
        (contentView as? PinImageView)?.setCloseButtonSuppressed(suppressed) ?? false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Scroll wheel or two-finger scroll: zoom about the mouse.
    func zoom(by event: NSEvent) {
        // Wheel away from the user zooms in, whatever the natural-scrolling setting.
        // Momentum after a flick would keep zooming once the fingers are off the trackpad.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard delta != 0 else { return }
        setZoomFactor(PinZoom.zoom(zoomFactor, scrolledBy: delta, precise: event.hasPreciseScrollingDeltas,
                                   imageSize: imageSize))
    }

    /// Trackpad pinch: zoom about the mouse too.
    func zoom(byMagnification event: NSEvent) {
        setZoomFactor(PinZoom.zoom(zoomFactor, magnifiedBy: event.magnification, imageSize: imageSize))
    }

    private func setZoomFactor(_ next: CGFloat) {
        guard next != zoomFactor else { return }
        zoomFactor = next
        setFrame(PinZoom.frame(frame, zoomedTo: zoomFactor, imageSize: imageSize, anchor: NSEvent.mouseLocation,
                               backingScale: backingScaleFactor), display: true)
    }
}

/// Shows the image scaled to the window and turns mouse input into window commands. Shows the ✕ while the
/// mouse is over it.
private final class PinImageView: NSView {
    private weak var pin: PinWindow?
    private let closeButton = PinCloseButton()
    /// Ours, kept so updateTrackingAreas replaces only this one.
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    /// A capture is starting or on screen: no ✕ (PinWindow.setCloseButtonSuppressed).
    private var isCloseButtonSuppressed = false

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        closeButton.isHidden = true
        closeButton.onClick = { [weak self] in
            guard let pin = self?.pin else { return }
            pin.onCommand?(pin, .close) // the same path as a double click
        }
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func attach(to pin: PinWindow) {
        self.pin = pin
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The pin never becomes key and Glimpse is usually not active: the tracking area must work regardless.
    /// `.inVisibleRect` follows the view's size by itself, so the area is added once.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// Zooming moves the top edge: the ✕ follows, and goes away on a pin too small for it.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCloseButton()
    }

    func refreshHover() {
        guard let window else { return }
        setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    func setCloseButtonSuppressed(_ suppressed: Bool) -> Bool {
        let wasVisible = !closeButton.isHidden
        isCloseButtonSuppressed = suppressed
        layoutCloseButton()
        return wasVisible
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        layoutCloseButton()
    }

    private func layoutCloseButton() {
        guard isHovered, !isCloseButtonSuppressed, let frame = PinCloseButtonLayout.frame(in: bounds.size) else {
            closeButton.isHidden = true
            return
        }
        closeButton.frame = frame
        closeButton.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        guard let pin else { return }
        if event.clickCount == 2 {
            pin.onCommand?(pin, .close)
        } else {
            pin.performDrag(with: event) // the system moves the window until the mouse is released
        }
    }

    override func scrollWheel(with event: NSEvent) {
        pin?.zoom(by: event)
    }

    override func magnify(with event: NSEvent) {
        pin?.zoom(byMagnification: event)
    }

    /// AppKit's own right-click path (rightMouseDown, or a control-click, → NSMenu.popUpContextMenu(_:with:for:))
    /// asks for this menu: it opens on the first click even while another app is active, with no
    /// popUp(positioning:at:in:) of our own.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pin else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(String(localized: "拷贝", comment: "Copy (menu item / button)"), .copy))
        menu.addItem(item(String(localized: "保存", comment: "Save (toolbar button / pin menu item)"), .save))
        let opacity = NSMenuItem(title: String(localized: "透明度", comment: "Pin context menu: opacity submenu"), action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for percent in [100, 75, 50] {
            // Formatted per locale (fr / de put a no-break space before the sign).
            let level = NSMenuItem(title: (Double(percent) / 100).formatted(.percent), action: #selector(opacityPicked(_:)), keyEquivalent: "")
            level.target = self
            level.tag = percent
            level.state = Int((pin.alphaValue * 100).rounded()) == percent ? .on : .off
            levels.addItem(level)
        }
        opacity.submenu = levels
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "关闭", comment: "Close (menu item / button)"), .close))
        return menu
    }

    private func item(_ title: String, _ command: PinWindow.Command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(commandPicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        return item
    }

    @objc private func commandPicked(_ sender: NSMenuItem) {
        guard let pin, let command = sender.representedObject as? PinWindow.Command else { return }
        pin.onCommand?(pin, command)
    }

    @objc private func opacityPicked(_ sender: NSMenuItem) {
        pin?.alphaValue = CGFloat(sender.tag) / 100
    }
}

/// The round ✕ at a pin's top-left corner (design doc §3.6): the glass material with an xmark in the
/// material's text colour, legible on light and dark images. Works on the first click without activating
/// Glimpse or the pin.
private final class PinCloseButton: NSView {
    var onClick: (() -> Void)?

    private let material = MaterialView(cornerRadius: PinCloseButtonLayout.diameter / 2, compactShadow: true)
    private let symbol = NSImageView()
    private var isPressed = false {
        didSet { symbol.alphaValue = isPressed ? 0.5 : 1 }
    }

    init() {
        let side = PinCloseButtonLayout.diameter
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        material.frame = bounds
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        symbol.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        symbol.contentTintColor = .materialText
        symbol.imageScaling = .scaleNone
        symbol.frame = bounds
        symbol.autoresizingMask = [.width, .height]
        material.contentView.addSubview(symbol)
        toolTip = String(localized: "关闭", comment: "Close (menu item / button)")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "关闭贴图", comment: "Accessibility: the pin's close button"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The whole circle, and only the circle, takes the click (not the glass or the symbol inside it); the
    /// corners outside it belong to the image, which drags the pin.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let radius = frame.width / 2
        let (dx, dy) = (point.x - frame.midX, point.y - frame.midY)
        return dx * dx + dy * dy <= radius * radius ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Tracks the press like a button: it closes only when released over the ✕.
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                isPressed = false
                if inside { onClick?() }
                return
            }
            isPressed = inside
        }
        isPressed = false
    }

    /// No menu on the ✕ itself: the pin's menu belongs to the image.
    override func menu(for event: NSEvent) -> NSMenu? {
        superview?.menu(for: event)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
