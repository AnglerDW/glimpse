import AppKit
import GlimpseCore

/// One screen's annotations: the document (with undo / redo), the shape being dragged out, and the
/// colour and width all tools share. Draws through `Renderer.draw`, the same code the export uses.
///
/// Sits between the frozen image and SelectionView, so the dim also covers the parts of annotations
/// that stick out of the selection (they are cropped on export). It takes no mouse input itself:
/// SelectionView forwards tool gestures in screen-local points, and they are stored in image pixels.
final class AnnotationCanvasView: NSView {
    /// Undo / redo availability may have changed.
    var onDocumentChange: (() -> Void)?

    private(set) var document = AnnotationDocument()
    private var draft: AnnotationDraft?
    /// The open text box while typing, and where its text goes in image pixels.
    private var textBox: AnnotationTextView?
    private var textOrigin: CGPoint = .zero
    /// The bottom-most chrome view in the overlay; text boxes are inserted just below it.
    weak var lowestChromeView: NSView?
    private let scale: CGFloat
    private let styleStore: AnnotationStyleStore
    /// Pixelated copies of this screen's frozen frame; mosaic shows them through the brush.
    let mosaicSource: MosaicSource
    /// Mosaic blocks are 8pt, in this screen's pixels.
    private var mosaicBlockSize: Int { max(1, Int((8 * scale).rounded())) }

    init(frame: CGRect, scale: CGFloat, image: CGImage, styleStore: AnnotationStyleStore) {
        self.scale = scale
        self.styleStore = styleStore
        mosaicSource = MosaicSource(image: image)
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Styles

    /// The colour and width level all tools share (design doc §3.3).
    var style: AnnotationStyle {
        get { styleStore.style }
        set {
            styleStore.style = newValue
            restyleTextBox() // while typing, the open text box follows the palette
        }
    }

    /// Colour and size (in pixels) a new annotation of `tool` gets: the shared style, sized for the tool.
    private func resolvedStyle(for tool: Tool) -> (color: RGBA, size: CGFloat) {
        let style = styleStore.style
        return (style.color.rgba(darkAppearance: effectiveAppearance.isDark), tool.size(for: style.width) * scale)
    }

    private func pixels(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    // MARK: - Drag tools (rectangle, ellipse, arrow, pen, mosaic)

    /// Starts a drag-drawn annotation at `point` (screen-local). False for click tools.
    func beginDraft(tool: Tool, at point: CGPoint) -> Bool {
        let (color, size) = resolvedStyle(for: tool)
        draft = AnnotationDraft(tool: tool, start: pixels(point), color: color, size: size,
                                mosaicBlockSize: mosaicBlockSize)
        if let bounds = draft?.annotation?.bounds { invalidate(pixelRect: bounds) }
        return draft != nil
    }

    func extendDraft(to point: CGPoint, constrained: Bool) {
        updateDraft { $0.extend(to: pixels(point), constrained: constrained) }
    }

    /// ⇧ pressed or released mid-drag. Pen and mosaic ignore ⇧, so nothing needs redrawing for them.
    func setDraftConstrained(_ constrained: Bool) {
        guard let tool = draft?.tool, tool != .pen, tool != .mosaic else { return }
        updateDraft { $0.setConstrained(constrained) }
    }

    /// Adds the draft to the document; a click without a drag adds nothing for shapes and arrows.
    func commitDraft() {
        guard let annotation = draft?.annotation else {
            draft = nil
            return
        }
        draft = nil
        add(annotation)
    }

    /// Esc mid-drag: drops the shape being drawn; the tool stays selected.
    func cancelDraft() {
        guard let pending = draft else { return }
        draft = nil
        if let bounds = pending.annotation?.bounds { invalidate(pixelRect: bounds) }
    }

    private func updateDraft(_ change: (inout AnnotationDraft) -> Void) {
        guard var current = draft else { return }
        // Only the part that can change: the stroke's tail for pen and mosaic, so a long stroke does not
        // redraw its whole bounding box on every mouse event; the whole shape for the others.
        let before = current.tailBounds
        change(&current)
        draft = current
        invalidate(pixelRect: before.union(current.tailBounds))
    }

    /// Builds the pixelated frame before the first mosaic stroke, which would otherwise stall on 5K / 6K frames.
    func prepareMosaic() {
        _ = mosaicSource.pixelated(blockSize: mosaicBlockSize)
    }

    // MARK: - Click tools

    /// Places the next number (design doc §3.4); undoing it hands the number back.
    func placeCounter(at point: CGPoint) {
        let (color, size) = resolvedStyle(for: .counter)
        add(Annotation(shape: .counter(center: pixels(point), number: document.nextCounterNumber),
                       color: color, size: size))
    }

    // MARK: - Text (typing layer, design doc §3.2.1)

    /// Opens a text box at a click and returns it so the caller can give it the keyboard and wire its
    /// callbacks. The box goes in the overlay just below `lowestChromeView` (the canvas itself takes no
    /// input), so it receives clicks but the toolbar, palette and size label stay on top of it.
    func beginText(at point: CGPoint) -> AnnotationTextView? {
        guard let host = superview, let lowestChromeView, lowestChromeView.superview === host else {
            assertionFailure("text box needs the overlay's chrome to sit under")
            return nil
        }
        let (color, pixelSize) = resolvedStyle(for: .text)
        textOrigin = Annotation.textOrigin(forClickAt: pixels(point), fontSize: pixelSize, scale: scale)
        let box = AnnotationTextView(fontSize: pixelSize / scale, color: color.nsColor)
        box.frame.origin = CGPoint(x: textOrigin.x / scale, y: textOrigin.y / scale)
        box.onTextChange = { [weak self] in self?.onDocumentChange?() } // while typing, the toolbar's undo / redo follow the box
        textBox = box
        host.addSubview(box, positioned: .below, relativeTo: lowestChromeView)
        return box
    }

    /// The open text box in the overlay's (screen-local) points; nil when not typing.
    var textBoxFrame: CGRect? { textBox?.frame }

    /// While typing, undo / redo act on the text box only (design doc §3.2.1); nil when not typing.
    var textUndoManager: UndoManager? { textBox?.undoManager }

    /// Ends typing: adds the text as one annotation (one undo step), or drops a blank box.
    func commitText() {
        guard let box = textBox else { return }
        let string = box.committedString // read before the box resigns: an input method may still change it then
        closeTextBox()
        let (color, size) = resolvedStyle(for: .text)
        if let annotation = Annotation.text(origin: textOrigin, string: string, color: color, size: size, scale: scale) {
            add(annotation)
        }
    }

    /// Drops the open text box without adding anything (the session is closing without output).
    func discardText() {
        closeTextBox()
    }

    private func closeTextBox() {
        guard let box = textBox else { return }
        textBox = nil
        // Give up the keyboard while the box is still in the window, so an input method ends its session and
        // closes its candidate window; an unfinished composition is dropped (see committedString).
        if box.window?.firstResponder === box { box.window?.makeFirstResponder(nil) }
        box.undoManager?.removeAllActions() // typing undo steps die with the box
        box.removeFromSuperview()
    }

    /// While typing, the open text box follows the palette. Its top-left stays put.
    private func restyleTextBox() {
        guard let box = textBox else { return }
        let (color, pixelSize) = resolvedStyle(for: .text)
        box.apply(fontSize: pixelSize / scale, color: color.nsColor)
    }

    // MARK: - Document

    private func add(_ annotation: Annotation) {
        document.add(annotation)
        invalidate(pixelRect: annotation.bounds)
        onDocumentChange?()
    }

    func undo() {
        guard let removed = document.undo() else { return }
        invalidate(pixelRect: removed.bounds)
        onDocumentChange?()
    }

    func redo() {
        guard let restored = document.redo() else { return }
        invalidate(pixelRect: restored.bounds)
        onDocumentChange?()
    }

    /// Right click / a new selection on another screen: annotations go with the selection (design doc §3.2).
    func removeAll() {
        closeTextBox() // right click while typing drops the text too
        draft = nil
        document.removeAll()
        needsDisplay = true
        onDocumentChange?()
    }

    // MARK: - Drawing

    private func invalidate(pixelRect: CGRect) {
        guard !pixelRect.isNull else { return }
        let points = CGRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                            width: pixelRect.width / scale, height: pixelRect.height / scale)
        setNeedsDisplay(points.insetBy(dx: -2, dy: -2).intersection(bounds))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The view is flipped, so the CTM is already y-down; scaling makes one unit one image pixel.
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        let dirtyPixels = CGRect(x: dirtyRect.minX * scale, y: dirtyRect.minY * scale,
                                 width: dirtyRect.width * scale, height: dirtyRect.height * scale)
        var visible = document.annotations
        if let pending = draft?.annotation { visible.append(pending) }
        Renderer.draw(visible.filter { $0.bounds.intersects(dirtyPixels) }, in: context) { [mosaicSource] in
            mosaicSource.pixelated(blockSize: $0)
        }
    }
}
