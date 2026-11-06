import AppKit
import GlimpseCore

/// The text box of the typing layer (design doc §3.2.1). While it is first responder every key goes
/// to it: letters type (R / T / … do not switch tools), Enter inserts a newline, ⌘C / ⌘V / ⌘X / ⌘A /
/// ⌘Z / ⇧⌘Z edit the text. Esc ends typing, unless an input method is composing, where Esc cancels
/// the composition first. Grows to fit its text; never wraps.
///
/// Pinned to TextKit 1 and laid out in points with the plain system font, like the committed annotation
/// (Core lays it out in points and scales it up). Every line's baseline is pinned to `TextLayout.baseline`:
/// TextKit would otherwise move it on lines where a fallback font (Chinese, emoji, …) appears.
final class AnnotationTextView: NSTextView, NSLayoutManagerDelegate {
    var onEndTyping: (() -> Void)?
    /// Right click on the box: same as anywhere else in the editing phase, clear and reselect (§3.2).
    var onRightClick: (() -> Void)?
    /// The text changed (typing, ⌘Z, …), so undo / redo availability may have too.
    var onTextChange: (() -> Void)?

    /// A text view built on a given text container does not own the text storage; this keeps it alive.
    private var ownedStorage: NSTextStorage?
    /// Font, colour and line height of all the text. Reapplied after every change, so undoing an edit made
    /// before a palette pick cannot bring the old style back.
    private var styleAttributes: [NSAttributedString.Key: Any] = [:]
    /// Distance from the top of each line to its baseline, in points.
    private var lineBaseline: CGFloat = 0

    /// `fontSize` is in points; line height and baselines are the committed annotation's,
    /// so the text does not move when typing ends.
    init(fontSize: CGFloat, color: NSColor) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: CGRect(x: 0, y: 0, width: 2, height: TextLayout.lineHeight(fontSize: fontSize)),
                   textContainer: container)
        ownedStorage = storage
        layoutManager.delegate = self
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isHorizontallyResizable = true
        isVerticallyResizable = true
        textContainerInset = .zero
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        apply(fontSize: fontSize, color: color)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // TextKit wants this initializer to exist on subclasses.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    /// Font size (points), colour and fixed line height, for the existing text and whatever is typed next.
    /// Also used when the palette changes the text tool's style mid-typing.
    func apply(fontSize: CGFloat, color: NSColor) {
        let lineHeight = TextLayout.lineHeight(fontSize: fontSize)
        lineBaseline = TextLayout.baseline(line: 0, fontSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        styleAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color, .paragraphStyle: paragraph]
        typingAttributes = styleAttributes
        // Not over a composition, which carries the input method's marking; didChangeText restyles after it.
        if !hasMarkedText() { restyleText() }
        insertionPointColor = color
        minSize = CGSize(width: 2, height: lineHeight)
        sizeToFit()
    }

    private func restyleText() {
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.setAttributes(styleAttributes, range: NSRange(location: 0, length: storage.length))
    }

    /// Pins every line's baseline where Core draws it (see the type's comment).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        baselineOffset.pointee = lineBaseline
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        if !hasMarkedText() { restyleText() }
        typingAttributes = styleAttributes
        sizeToFit()
        onTextChange?()
    }

    /// The text without what an input method is still composing. Ending typing drops an unfinished
    /// composition, as Esc does (design doc §3.2.1), so the result does not depend on the input method.
    var committedString: String {
        guard hasMarkedText() else { return string }
        return (string as NSString).replacingCharacters(in: markedRange(), with: "")
    }

    override func resignFirstResponder() -> Bool {
        if hasMarkedText() {
            // Dropped (see committedString); tell the input method too, so its candidate window closes.
            inputContext?.discardMarkedText()
            unmarkText()
        }
        return super.resignFirstResponder()
    }

    /// Enter is the only line break (design doc §3.4) and there are no tab stops: Tab and ⇧Tab type nothing.
    override func insertTab(_ sender: Any?) {}
    override func insertBacktab(_ sender: Any?) {}

    /// No context menu: a right click must reach the session's "clear selection and annotations".
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func keyDown(with event: NSEvent) {
        // While an input method composes, every key is its own: Esc cancels the composition, Enter confirms it.
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        let input = KeyInput(event: event)
        if KeyRouter.route(input, phase: .typing) == .endTyping {
            onEndTyping?()
            return
        }
        // ⌘ + a key that performKeyEquivalent does not map would only beep: nothing else acts on it while
        // typing. ⌘ with an arrow or Delete still moves and deletes.
        if input.command, case .character(let c) = input.key, c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol {
            return
        }
        super.keyDown(with: event)
    }

    /// A menu-bar app has no Edit menu, so the usual editing shortcuts are mapped here.
    /// The window offers key equivalents to every view, so only act while this view has the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, flags.contains(.command),
              !flags.contains(.option), !flags.contains(.control),
              case .character(let c) = KeyInput(event: event).key else {
            return super.performKeyEquivalent(with: event)
        }
        switch (c.lowercased(), flags.contains(.shift)) {
        case ("x", false): cut(nil)
        case ("c", false): copy(nil)
        case ("v", false): paste(nil)
        case ("a", false): selectAll(nil)
        case ("z", false): undoManager?.undo()
        case ("z", true): undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
