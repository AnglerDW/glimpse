import AppKit
import GlimpseCore

enum OverlayFinishAction {
    case copy
    case save
    /// The selection's frozen pixels, without annotations, go to text recognition (design doc §3.5).
    case recognizeText
    /// The composed image is pinned where the selection was (design doc §3.6).
    case pin
}

@MainActor
protocol SelectionViewDelegate: AnyObject {
    func selectionViewDidBeginSelection(_ view: SelectionView)
    func selectionViewDidCancel(_ view: SelectionView)
    /// `frame` is where the image was on screen, in AppKit global coordinates (a pin appears right there).
    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, frame: CGRect,
                       action: OverlayFinishAction)
    /// C / ⇧C put `text` (the colour under the cursor) on the clipboard; the capture ends.
    func selectionView(_ view: SelectionView, didCopyColor text: String)
    /// Whether this screen may show the hover highlight: false while any screen holds a selection,
    /// so a second highlight cannot look like a second selection.
    func selectionViewShouldShowHover(_ view: SelectionView) -> Bool
    /// The mouse entered this screen or moved on it — called on every move, not only on entry
    /// (mouseEntered / mouseExited are unreliable across screens for these panels). The receiver dedupes.
    func selectionViewMouseDidMove(_ view: SelectionView)
    /// A press-and-release on this screen produced no selection (empty click or a too-small drag).
    /// The controller hands key focus back to whichever overlay still has one.
    func selectionViewDidEndWithoutSelection(_ view: SelectionView)
    /// Right click. Whether it exits or clears the selection depends on all screens, so the controller decides.
    func selectionViewDidRightClick(_ view: SelectionView)
    /// A press is about to start a selection on this screen. False swallows it: while another screen is typing,
    /// the click only ends typing there (design doc §3.2.1) instead of clearing that screen's text and selection.
    func selectionViewShouldBeginPress(_ view: SelectionView) -> Bool
}

/// The overlay's chrome (toolbar, size label) follows the selection through this delegate.
@MainActor
protocol SelectionViewChromeDelegate: AnyObject {
    /// The selection rect or the phase changed: reposition the chrome.
    func selectionViewDidChangeLayout(_ view: SelectionView)
    /// True over the toolbar, where the cursor is the arrow.
    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool
    /// Shows the magnifier for a screen-local point, or hides it (nil).
    func selectionView(_ view: SelectionView, moveMagnifierTo point: CGPoint?)
}

/// Draws the dim, window highlight, selection and handles for one screen,
/// and turns mouse/keyboard input into selection changes. All geometry is screen-local
/// (top-left origin, points) — this view is flipped.
final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?
    weak var chromeDelegate: SelectionViewChromeDelegate?
    /// Text recognition from the menu or its shortcut (design doc §3.5): the selection is recognised as soon
    /// as it is made, with no editing phase. Set by the session before the overlay shows.
    var recognizesTextOnSelection = false

    private let captured: CapturedScreen
    private let windows: [WindowInfo]
    private let primaryScreenHeight: CGFloat
    /// Annotations live in their own view; tool gestures are forwarded to it.
    private let canvas: AnnotationCanvasView

    private(set) var phase: EditorPhase = .selecting {
        didSet {
            guard phase != oldValue else { return }
            // Handles are drawn in every phase but selecting; the selection itself has not moved, so
            // refreshDisplay would not cover them.
            if let selection { invalidateHandles(of: selection.rect) }
            chromeDelegate?.selectionViewDidChangeLayout(self)
        }
    }
    private var selection: Selection?
    private var hoveredRect: CGRect?

    private enum Drag {
        case none
        case pending(start: CGPoint, target: CGRect)   // mouse down, not yet past the drag threshold; target = what a click takes
        case creating(start: CGPoint, notified: Bool)   // notified: other screens were told once the rect became usable
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, original: CGRect)
        case annotating                                 // a drag tool is drawing; points go to the canvas
    }
    private var drag: Drag = .none

    var hasSelection: Bool { selection != nil }
    var selectionRect: CGRect? { selection?.rect }
    /// What was last drawn outside the dim (border, handles); the next redraw covers old ∪ new.
    private var displayedExtent: CGRect = .null
    /// Redraws the border and handles when the accent changes.
    private var accentObservation: AccentObservation?
    private var screenBounds: CGRect { CGRect(origin: .zero, size: bounds.size) }

    init(frame: CGRect, captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat,
         canvas: AnnotationCanvasView) {
        self.captured = captured
        self.windows = windows
        self.primaryScreenHeight = primaryScreenHeight
        self.canvas = canvas
        super.init(frame: frame)
        accentObservation = AccentObservation { [weak self] in self?.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - State changes

    func resetSelection() {
        selection = nil
        hoveredRect = nil
        phase = .selecting
        drag = .none
        canvas.removeAll() // annotations belong to the selection (design doc §3.2: right click clears both)
        refreshDisplay()
        // Callers that want the hover back call refreshHoverAtMouse() once every screen is reset.
    }

    private func enterEditing(with newSelection: Selection) {
        selection = newSelection
        hoveredRect = nil
        // Space mid-press or mid-drag (selecting phase) enters editing here; the press must not go on to
        // replace the new selection on mouseDragged / mouseUp.
        drag = .none
        if recognizesTextOnSelection {
            // Straight to recognition, without the toolbar. On the next turn of the run loop, so the caller's
            // own callbacks (other screens reset, focus) still run against a live session.
            refreshDisplay()
            let chosen = newSelection.rect
            DispatchQueue.main.async { [weak self] in
                // Cancelled (window closed) or selection cleared or replaced meanwhile: nothing to recognise.
                guard let self, self.window?.isVisible == true, self.selection?.rect == chosen else { return }
                self.finish(.recognizeText)
            }
            return
        }
        phase = .editing(tool: nil)
        refreshDisplay()
        refreshHoverAtMouse()
    }

    /// Invalidates only the area that changed: the previous and the new extent of the clear rect,
    /// border and handles. `draw` still fills the whole dim; AppKit clips it to the dirty rect.
    private func refreshDisplay() {
        let new = currentExtent()
        let dirty = displayedExtent.union(new)
        displayedExtent = new
        if !dirty.isNull { setNeedsDisplay(dirty.intersection(bounds)) }
        chromeDelegate?.selectionViewDidChangeLayout(self)
    }

    private func currentExtent() -> CGRect {
        guard let clear = selection?.rect ?? hoveredRect else { return .null }
        return clear.insetBy(dx: -10, dy: -10)
    }

    /// What a click or Enter would take: the selection when editing, otherwise the hover target
    /// (window, or the whole screen when no window is under the mouse). Nil if missing or too thin.
    private var captureTarget: Selection? {
        if let selection { return selection.isUsable ? selection : nil } // e.g. Enter mid-drag
        guard phase == .selecting, let hoveredRect else { return nil }
        return usableTarget(hoveredRect)
    }

    private func usableTarget(_ rect: CGRect) -> Selection? {
        let target = Selection(rect: rect, bounds: screenBounds)
        return target.isUsable ? target : nil
    }

    /// Ends the capture with the selection, or while selecting with the hover target. Keys, double click
    /// and the toolbar's buttons all end up here.
    func finish(_ action: OverlayFinishAction) {
        endTyping() // an open text box is committed first, whichever path finishes (no-op when not typing)
        guard let selection = captureTarget else {
            Log.app.debug("finish(\(String(describing: action), privacy: .public)) ignored: no selection or hover target")
            NSSound.beep()
            return
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: selection.rect, scale: captured.info.scale)
        // Crop + annotations at full pixel resolution (design doc §3.2 step 4, §5.2). Runs on the main
        // thread before the overlay closes: a full 6K screen is a ~80MB bitmap and tens of ms. Accepted;
        // only PNG encoding and the disk write are moved off the main thread (by the session controller).
        let rendered = action == .recognizeText
            // Text is read from the frozen pixels alone, without the annotations (design doc §3.2 step 4).
            ? Renderer.crop(captured.image, toPixelRect: pixels)
            : Renderer.composite(captured.image, annotations: canvas.document.annotations, toPixelRect: pixels,
                                 pixelated: { [canvas] in canvas.mosaicSource.pixelated(blockSize: $0) })
        guard let image = rendered else {
            // When recognising text from the menu or its shortcut, the overlay stays up without a toolbar:
            // dragging or clicking again makes a new selection (and recognises it), Esc leaves.
            Log.app.error("finish(\(String(describing: action), privacy: .public)) failed: could not composite \(String(describing: pixels), privacy: .public)")
            NSSound.beep()
            return
        }
        // The image covers the whole pixels around the selection, so its frame is taken from those pixels,
        // not from the selection: a pin then sits exactly on the pixels it shows.
        let scale = captured.info.scale
        let local = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                           width: pixels.width / scale, height: pixels.height / scale)
        delegate?.selectionView(self, didFinishWith: image, scale: scale,
                                frame: CoordinateSpace.appKitRect(fromLocal: local, in: captured.info), action: action)
    }

    // MARK: - Hover

    func refreshHoverAtMouse() {
        guard let point = mouseLocation else {
            updateMagnifier(at: nil) // the mouse is on another screen
            return
        }
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
    }

    /// The mouse in this view's coordinates, or nil when it is on another screen.
    private var mouseLocation: CGPoint? {
        guard let window else { return nil }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // Inclusive: the mouse can sit exactly on the last row/column of the screen.
        guard bounds.containsInclusive(point) else { return nil }
        return point
    }

    /// The magnifier follows the mouse only while selecting (design doc §3.2), and not while another
    /// screen holds the selection. A selection on this screen while still selecting is the one being
    /// dragged out, which keeps the magnifier.
    private func updateMagnifier(at point: CGPoint?) {
        let visible = phase == .selecting && (hasSelection || (delegate?.selectionViewShouldShowHover(self) ?? true))
        chromeDelegate?.selectionView(self, moveMagnifierTo: visible ? point : nil)
    }

    /// What a click at `point` would take: the window under it, or the whole screen when there is none
    /// (desktop, an occluder in front, or a window with only a sliver on this screen).
    private func hoverTarget(at point: CGPoint) -> CGRect {
        let global = CoordinateSpace.cgGlobalPoint(fromLocal: point, in: captured.info,
                                                   primaryScreenHeight: primaryScreenHeight)
        let windowRect = WindowHitTester.topmostWindow(at: global, in: windows).map {
            CoordinateSpace.localRect(fromCG: $0.frame, in: captured.info,
                                      primaryScreenHeight: primaryScreenHeight).intersection(screenBounds)
        }.flatMap { $0.isNull || usableTarget($0) == nil ? nil : $0 }
        return windowRect ?? screenBounds
    }

    private func updateHover(at point: CGPoint) {
        guard phase == .selecting else { return }
        let rect = (delegate?.selectionViewShouldShowHover(self) ?? true) ? hoverTarget(at: point) : nil
        if rect != hoveredRect {
            hoveredRect = rect
            refreshDisplay()
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            // .assumeInside: the session starts with the mouse already on one screen, which never gets
            // mouseEntered; without it AppKit would also skip mouseExited and leave that screen's highlight on.
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate, .assumeInside],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
        delegate?.selectionViewMouseDidMove(self)
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    /// Drops the hover highlight (selecting phase only). Also called by the controller when the mouse
    /// enters another screen, in case this screen missed its mouseExited.
    func clearHover() {
        updateMagnifier(at: nil)
        guard phase == .selecting, hoveredRect != nil else { return }
        hoveredRect = nil
        refreshDisplay()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updateCursor(at: point)
        updateMagnifier(at: point)
        // mouseEntered/mouseExited are unreliable across screens for these non-activating panels,
        // so every move also tells the controller which screen the mouse is on (it dedupes).
        delegate?.selectionViewMouseDidMove(self)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        // Key focus is not taken here: a click that ends without a selection must not steal it from
        // another screen that has one (see selectionViewDidEndWithoutSelection).
        let point = convert(event.locationInWindow, from: nil)
        switch phase {
        case .selecting:
            guard delegate?.selectionViewShouldBeginPress(self) ?? true else { return }
            // Computed here, not taken from the hover: the hover is hidden while another screen has a
            // selection, but a click may still pick this screen's target.
            updateHover(at: point)
            drag = .pending(start: point, target: hoverTarget(at: point))
        case .typing:
            endTyping() // a click outside the text box only ends typing; another click starts a new one (§3.2.1)
            return
        case .editing(let tool):
            guard let selection else { return }
            if event.clickCount == 2, KeyRouter.doubleClickFinishes(phase: phase), selection.rect.contains(point) {
                finish(.copy)
                return
            }
            if let handle = selection.handle(at: point) {
                drag = .resizing(handle, original: selection.rect) // handles work with a tool too (§3.2)
            } else if let tool, selection.rect.contains(point) {
                switch tool {
                case .counter:
                    canvas.placeCounter(at: point) // placed on press, so fast clicking never misses one
                    drag = .none
                case .text:
                    beginTyping(at: point)
                    drag = .none
                default:
                    drag = canvas.beginDraft(tool: tool, at: point) ? .annotating : .none
                }
            } else if tool == nil, selection.rect.contains(point) {
                drag = .moving(start: point, original: selection.rect)
                NSCursor.closedHand.set()
            } else {
                drag = .none
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Still selecting while dragging out a selection; a drag can leave the screen, the magnifier cannot.
        updateMagnifier(at: CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                                    y: min(max(point.y, bounds.minY), bounds.maxY)))
        switch drag {
        case .none:
            return
        case .pending(let start, _):
            guard PointerGesture.isDrag(from: start, to: point) else { return }
            hoveredRect = nil
            drag = .creating(start: start, notified: false)
            updateCreating(start: start, to: point, notified: false)
        case .creating(let start, let notified):
            updateCreating(start: start, to: point, notified: notified)
        case .moving(let start, let original):
            selection?.moveOrigin(to: CGPoint(x: original.minX + point.x - start.x,
                                              y: original.minY + point.y - start.y))
            NSCursor.closedHand.set()
        case .resizing(let handle, let original):
            selection?.resize(handle, to: point, original: original)
        case .annotating:
            canvas.extendDraft(to: point, constrained: event.modifierFlags.contains(.shift))
            return
        }
        refreshDisplay()
    }

    /// ⇧ pressed or released mid-drag re-shapes the draft without waiting for the mouse to move.
    override func flagsChanged(with event: NSEvent) {
        if case .annotating = drag {
            canvas.setDraftConstrained(event.modifierFlags.contains(.shift))
        }
        super.flagsChanged(with: event)
    }

    private func updateCreating(start: CGPoint, to point: CGPoint, notified: Bool) {
        let rect = Selection.fromDrag(start: start, end: point, bounds: screenBounds)
        selection = rect
        // Other screens are cleared only once this selection is real, not for a stray swipe.
        if !notified, rect.isUsable {
            drag = .creating(start: start, notified: true)
            delegate?.selectionViewDidBeginSelection(self)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let finished = drag
        drag = .none
        switch finished {
        case .pending(_, let clicked):
            // A click (no drag): take the target under the click (window or whole screen).
            if let target = usableTarget(clicked) {
                enterEditing(with: target)
                delegate?.selectionViewDidBeginSelection(self) // after the selection exists, so other screens stay unhighlighted
            } else {
                delegate?.selectionViewDidEndWithoutSelection(self)
            }
        case .creating:
            if let selection, selection.isUsable {
                // Other screens were already cleared by updateCreating when the rect first became usable.
                enterEditing(with: selection)
            } else {
                resetSelection()
                refreshHoverAtMouse()
                delegate?.selectionViewDidEndWithoutSelection(self)
            }
        case .resizing(_, let original):
            // Squashed to a sliver: undo the resize instead of throwing the selection away.
            if let selection, !selection.isUsable {
                self.selection = Selection(rect: original, bounds: screenBounds)
            }
        case .annotating:
            canvas.commitDraft()
        case .moving, .none:
            break
        }
        refreshDisplay()
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.selectionViewDidRightClick(self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let input = KeyInput(event: event)
        if case .annotating = drag {
            // Mid-drag (design doc §3.2.1): Esc drops the shape being drawn and keeps the tool;
            // every other key waits for mouse-up.
            if input.key == .escape {
                canvas.cancelDraft()
                drag = .none
            }
            return
        }
        perform(KeyRouter.route(input, phase: phase))
    }

    /// Keys and toolbar buttons both end up here.
    func perform(_ action: EditorAction) {
        switch action {
        case .exit:
            delegate?.selectionViewDidCancel(self)
        case .selectFullScreen:
            enterEditing(with: Selection(rect: screenBounds, bounds: screenBounds))
            delegate?.selectionViewDidBeginSelection(self)
        case .finishCopy:
            finish(recognizesTextOnSelection ? .recognizeText : .copy) // Enter on a window while recognising text
        case .save:
            finish(recognizesTextOnSelection ? .recognizeText : .save)
        case .nudge(let dx, let dy, let large):
            selection?.nudge(dx: dx, dy: dy, large: large)
            refreshDisplay()
            refreshHoverAtMouse()
        case .selectTool(let tool):
            guard case .editing = phase else { return }
            phase = .editing(tool: tool)
            if tool == .mosaic { canvas.prepareMosaic() }
            refreshHoverAtMouse() // cursor
        case .deselectTool:
            guard case .editing(.some) = phase else { return }
            phase = .editing(tool: nil)
            refreshHoverAtMouse()
        case .undo:
            canvas.undo()
        case .redo:
            canvas.redo()
        case .endTyping:
            endTyping()
        case .copyColor(let format):
            copyColorUnderMouse(as: format)
        case .reselect, .passToTextField, .ignore:
            break // reselect is decided by the controller; while typing the text box gets the keys
        }
    }

    /// C / ⇧C while selecting: the magnifier's colour value goes to the clipboard as text (`#FF3B30` /
    /// `255, 59, 48`) and the capture ends, as Enter does with the image.
    private func copyColorUnderMouse(as format: ColorFormat) {
        guard let point = mouseLocation else {
            NSSound.beep()
            return
        }
        let pixel = Magnifier.pixel(at: point, scale: captured.info.scale,
                                    imageWidth: captured.image.width, imageHeight: captured.image.height)
        guard let color = Magnifier.color(of: captured.image, atPixel: pixel) else {
            NSSound.beep()
            return
        }
        let text = color.text(format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        delegate?.selectionView(self, didCopyColor: text)
    }

    // MARK: - Typing

    private func beginTyping(at point: CGPoint) {
        guard let box = canvas.beginText(at: point) else { return }
        box.onEndTyping = { [weak self] in self?.endTyping() }
        box.onRightClick = { [weak self] in
            guard let self else { return }
            self.delegate?.selectionViewDidRightClick(self)
        }
        phase = .typing
        window?.makeFirstResponder(box)
    }

    /// Commits the text box (a blank one is dropped; the box gives up the keyboard first, dropping an
    /// unfinished input-method composition) and gives the keyboard back to the selection.
    /// The text tool stays selected, as after any other annotation. No-op when not typing.
    func endTyping() {
        guard case .typing = phase else { return }
        canvas.commitText()
        phase = .editing(tool: .text)
        window?.makeFirstResponder(self)
    }

    /// Drops the open text box without adding it, for a session closing without output. The box gives up
    /// the keyboard first, so an input method discards its composition and closes its candidate window.
    /// No-op when not typing.
    func discardTyping() {
        guard case .typing = phase else { return }
        canvas.discardText()
        phase = .editing(tool: .text)
        window?.makeFirstResponder(self)
    }

    // MARK: - Cursor

    private func updateCursor(at point: CGPoint) {
        if chromeDelegate?.selectionView(self, isChromeAt: point) == true {
            NSCursor.arrow.set()
            return
        }
        if case .typing = phase {
            // Over the text box its own I-beam wins; anywhere else a click only ends typing (handles too).
            if canvas.textBoxFrame?.containsInclusive(point) != true { NSCursor.arrow.set() }
            return
        }
        guard case .editing(let tool) = phase, let selection else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = selection.handle(at: point) {
            resizeCursor(for: handle).set()
        } else if tool == nil, selection.rect.contains(point) {
            NSCursor.openHand.set()
        } else if let tool, selection.rect.contains(point) {
            (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resizeCursor(for handle: Handle) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch handle {
            case .topLeft: .topLeft
            case .top: .top
            case .topRight: .topRight
            case .right: .right
            case .bottomRight: .bottomRight
            case .bottom: .bottom
            case .bottomLeft: .bottomLeft
            case .left: .left
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let clearRect = selection?.rect ?? hoveredRect

        let dim = NSBezierPath(rect: bounds)
        if let clearRect {
            dim.append(NSBezierPath(rect: clearRect))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.55).setFill()
        dim.fill()

        guard let clearRect else { return }
        let accent = NSColor.glimpseAccent
        // Drawn just outside the selection, but kept on screen where the selection touches an edge.
        let borderRect = clearRect.insetBy(dx: -0.75, dy: -0.75).intersection(bounds.insetBy(dx: 0.75, dy: 0.75))
        let border = NSBezierPath(rect: borderRect.isNull ? clearRect : borderRect)
        border.lineWidth = 1.5
        accent.setStroke()
        border.stroke()

        // Shown while typing too (inert then: a click only ends typing), so they do not blink in and out.
        guard let selection, phase != .selecting else { return }
        drawHandles(for: selection.rect, accent: accent)
    }

    /// The dot of `handle`, kept wholly on screen.
    private func handleDot(_ handle: Handle, of rect: CGRect) -> CGRect {
        var c = Selection.handlePoint(handle, of: rect)
        c.x = min(max(c.x, bounds.minX + 5), bounds.maxX - 5)
        c.y = min(max(c.y, bounds.minY + 5), bounds.maxY - 5)
        return CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)
    }

    private func invalidateHandles(of rect: CGRect) {
        for handle in Handle.allCases {
            setNeedsDisplay(handleDot(handle, of: rect).insetBy(dx: -1, dy: -1)) // + half the 1.5pt stroke
        }
    }

    private func drawHandles(for rect: CGRect, accent: NSColor) {
        for handle in Handle.allCases {
            let dot = NSBezierPath(ovalIn: handleDot(handle, of: rect))
            NSColor.white.setFill()
            dot.fill()
            dot.lineWidth = 1.5
            accent.setStroke()
            dot.stroke()
        }
    }
}
