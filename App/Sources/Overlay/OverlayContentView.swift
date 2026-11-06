import AppKit
import GlimpseCore

/// One screen's overlay, bottom to top:
/// - a plain layer-backed view whose layer shows the frozen CGImage directly (no NSImage redraws)
/// - AnnotationCanvasView: the annotations, under the dim so parts outside the selection look dimmed
/// - SelectionView: dim, selection, handles, and all mouse / keyboard input
/// - the text box while typing (AnnotationTextView, added by the canvas just below the chrome)
/// - the chrome on the shared material: size label, toolbar, style palette, toolbar tooltip, magnifier
/// Flipped, so every frame here is screen-local points like the selection.
final class OverlayContentView: NSView {
    let selectionView: SelectionView

    private let captured: CapturedScreen
    private let canvas: AnnotationCanvasView
    private let toolbar = ToolbarView()
    private let palette = StylePaletteView()
    private let sizeLabel = GlassLabelView(font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
    /// Toolbar tooltips are drawn here: AppKit's tooltip window would sit behind the `.screenSaver` overlay.
    private let toolTipLabel = GlassLabelView(font: .systemFont(ofSize: 11, weight: .medium))
    private var toolbarSide: OverlayLayout.ToolbarPosition.Side = .below
    private let magnifier: MagnifierView
    /// The tool the palette last showed; it is only refreshed when the tool changes (see layoutChrome).
    private var paletteTool: Tool?

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat, styleStore: AnnotationStyleStore) {
        self.captured = captured
        let frame = CGRect(origin: .zero, size: captured.info.frame.size)
        magnifier = MagnifierView(image: captured.image)
        canvas = AnnotationCanvasView(frame: frame, scale: captured.info.scale, image: captured.image, styleStore: styleStore)
        selectionView = SelectionView(frame: frame, captured: captured, windows: windows,
                                      primaryScreenHeight: primaryScreenHeight, canvas: canvas)
        super.init(frame: frame)

        let imageView = NSView(frame: frame)
        imageView.wantsLayer = true
        imageView.layer?.contents = captured.image
        imageView.layer?.contentsGravity = .resize
        for view in [imageView, canvas, selectionView] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        for chrome in [sizeLabel, toolbar, palette, toolTipLabel, magnifier] as [NSView] {
            chrome.isHidden = true
            addSubview(chrome)
        }
        toolbar.delegate = self
        palette.delegate = self
        selectionView.chromeDelegate = self
        canvas.onDocumentChange = { [weak self] in self?.refreshToolbarState() }
        canvas.lowestChromeView = sizeLabel // text boxes go under the chrome
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// A right click on the toolbar's padding or buttons bubbles up to here, not to the sibling selection
    /// view: forward it so it still means "start over" (design doc §3.2).
    override func rightMouseDown(with event: NSEvent) {
        selectionView.rightMouseDown(with: event)
    }

    /// The tool whose button is highlighted and whose style the palette shows; typing belongs to the text tool.
    private var selectedTool: Tool? {
        switch selectionView.phase {
        case .selecting: nil
        case .editing(let tool): tool
        case .typing: .text
        }
    }

    private func refreshToolbarState() {
        // While typing, undo / redo belong to the text box (design doc §3.2.1).
        if let typing = canvas.textUndoManager {
            toolbar.update(selectedTool: selectedTool, canUndo: typing.canUndo, canRedo: typing.canRedo)
        } else {
            toolbar.update(selectedTool: selectedTool, canUndo: canvas.document.canUndo, canRedo: canvas.document.canRedo)
        }
    }

    // MARK: - Chrome layout

    /// Puts the size label, toolbar and palette around the current selection (design doc §3.2, §3.3).
    private func layoutChrome() {
        guard let rect = selectionView.selectionRect else {
            hideToolbar()
            sizeLabel.isHidden = true
            return
        }
        let screen = chromeArea
        var toolbarFrame: CGRect?
        if case .selecting = selectionView.phase {
            hideToolbar() // still dragging out the selection
        } else {
            let position = OverlayLayout.toolbar(size: toolbar.frame.size, selection: rect, screen: screen,
                                                     obstacle: notchObstacle)
            if toolbar.isHidden || toolbar.frame != position.frame {
                // Moving under a stationary mouse sends no exit event: drop stale hover and tooltip by hand.
                toolbar.resetHover()
                toolTipLabel.isHidden = true
            }
            show(toolbar, at: position.frame)
            toolbarFrame = position.frame
            toolbarSide = position.side
            if let tool = selectedTool {
                // Not on every move or resize: reading the style decodes it from UserDefaults. A pick in
                // the palette updates the palette itself.
                if palette.isHidden || tool != paletteTool {
                    palette.show(canvas.style, colorsEnabled: tool != .mosaic)
                    paletteTool = tool
                }
                show(palette, at: OverlayLayout.palette(size: palette.frame.size, toolbar: position, screen: screen,
                                                        obstacle: notchObstacle))
            } else {
                palette.isHidden = true
            }
        }
        let pixels = CoordinateSpace.pixelRect(fromLocal: rect, scale: captured.info.scale)
        sizeLabel.setText("\(Int(pixels.width)) × \(Int(pixels.height))")
        sizeLabel.frame = OverlayLayout.sizeLabel(size: sizeLabel.frame.size, selection: rect, screen: screen,
                                                  avoiding: toolbarFrame, obstacle: notchObstacle)
        sizeLabel.isHidden = false
    }

    /// Chrome may use the whole screen except the camera housing (`notchObstacle`).
    private var chromeArea: CGRect { CGRect(origin: .zero, size: bounds.size) }

    /// The camera housing in this view's flipped local coordinates: the gap between the two top areas the
    /// system leaves usable, as tall as the top safe-area inset. nil on screens without a notch.
    private var notchObstacle: CGRect? {
        let screen = captured.nsScreen
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        // The areas are in global screen coordinates; subtract the screen's origin (they are already local
        // when that origin is 0, or when a system reports them relative to the screen).
        let originX = abs(left.minX - screen.frame.minX) < 1 ? screen.frame.minX : 0
        return CGRect(x: left.maxX - originX, y: 0, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private func hideToolbar() {
        toolbar.isHidden = true
        palette.isHidden = true
        toolbar.resetHover()
        toolTipLabel.isHidden = true
    }

    /// Puts a chrome view at `frame` and shows it at once: the toolbar is there the moment the selection is
    /// made, with no fade or slide (design doc §4.3).
    private func show(_ view: NSView, at frame: CGRect) {
        view.frame = frame
        view.isHidden = false
    }
}

extension OverlayContentView: SelectionViewChromeDelegate {
    func selectionViewDidChangeLayout(_ view: SelectionView) {
        if view.phase != .selecting { magnifier.isHidden = true }
        layoutChrome()
        refreshToolbarState()
    }

    func selectionView(_ view: SelectionView, moveMagnifierTo point: CGPoint?) {
        guard let point else {
            magnifier.isHidden = true
            return
        }
        magnifier.show(pixel: Magnifier.pixel(at: point, scale: captured.info.scale,
                                              imageWidth: captured.image.width, imageHeight: captured.image.height))
        magnifier.frame = Magnifier.frame(size: magnifier.frame.size, cursor: point,
                                          screen: chromeArea, obstacle: notchObstacle)
        magnifier.isHidden = false
    }

    func selectionView(_ view: SelectionView, isChromeAt point: CGPoint) -> Bool {
        [toolbar, palette].contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

extension OverlayContentView: ToolbarViewDelegate {
    /// Name and shortcut after a short hover (design doc §3.3), on the material like the rest of the chrome.
    func toolbarView(_ view: ToolbarView, showToolTipFor item: ToolbarItem?, buttonFrame: CGRect) {
        guard let item, !toolbar.isHidden else {
            toolTipLabel.isHidden = true
            return
        }
        toolTipLabel.setText(item.toolTip)
        toolTipLabel.frame = OverlayLayout.toolTip(size: toolTipLabel.frame.size, button: convert(buttonFrame, from: toolbar),
                                                   toolbarSide: toolbarSide, screen: chromeArea,
                                                   obstacle: notchObstacle)
        toolTipLabel.isHidden = false
    }

    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem) {
        if let typing = canvas.textUndoManager, item == .undo || item == .redo {
            // Inside the text box, like ⌘Z / ⇧⌘Z; typing goes on (design doc §3.2.1).
            if item == .undo { typing.undo() } else { typing.redo() }
            refreshToolbarState()
            return
        }
        selectionView.endTyping() // any other button first ends typing, keeping the text (✓ then copies it)
        switch item {
        case .tool(let tool):
            selectionView.perform(tool == selectedTool ? .deselectTool : .selectTool(tool))
        case .undo:
            selectionView.perform(.undo)
        case .redo:
            selectionView.perform(.redo)
        case .recognizeText:
            selectionView.finish(.recognizeText)
        case .pin:
            selectionView.finish(.pin)
        case .save:
            selectionView.perform(.save)
        case .cancel:
            selectionView.perform(.exit)
        case .confirm:
            selectionView.perform(.finishCopy)
        }
    }
}

extension OverlayContentView: StylePaletteViewDelegate {
    func stylePaletteView(_ view: StylePaletteView, didPick style: AnnotationStyle) {
        canvas.style = style
    }
}
