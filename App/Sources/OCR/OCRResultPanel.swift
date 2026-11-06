import AppKit
import GlimpseCore

/// The 提取文字 result (design doc §3.5): a glass panel next to the selection with the text, editable, a 「复制」
/// button in the interface accent, and 「已复制」 next to the title once the text is on the clipboard. Esc, ⌘W
/// or ✕ closes it.
/// A non-activating panel that still takes the keyboard, like the overlay: the app the user was in stays
/// active, and closing the panel hands the keyboard straight back to it.
final class OCRResultPanel: NSPanel {
    enum State: Equatable {
        case recognizing
        case copied(String)
        case noText
        case failed
    }

    private static let size = CGSize(width: 440, height: 300)
    private static let inset: CGFloat = 16

    private let material = MaterialView(cornerRadius: 12, blendsBehindWindow: true)
    private let status = NSTextField(labelWithString: "")
    private let textView = OCRTextView(frame: .zero)
    private let scrollView = NSScrollView()
    private let copyButton = NSButton(title: String(localized: "拷贝", comment: "Copy (menu item / button)"), target: nil, action: nil)
    /// Called whenever the panel closes (Esc, ⌘W, ✕, or a new capture starting).
    var onDismiss: (() -> Void)?
    /// Repaints the 「复制」 button when the interface accent changes.
    private var accentObservation: AccentObservation?

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let size = Self.size, inset = Self.inset
        material.frame = CGRect(origin: .zero, size: size)
        material.autoresizingMask = [.width, .height]
        contentView = material
        let content = material.contentView

        let title = NSTextField(labelWithString: String(localized: "提取文字", comment: "Shortcut row / menu item / toolbar button / panel title: extract text (OCR)"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .materialText
        title.sizeToFit()
        title.frame.origin = CGPoint(x: inset, y: inset)
        content.addSubview(title)

        status.font = .systemFont(ofSize: 12)
        status.textColor = .materialSecondaryText
        status.frame = CGRect(x: title.frame.maxX + 8, y: inset + 1, width: 200, height: title.frame.height)
        content.addSubview(status)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "关闭", comment: "Close (menu item / button)"))!,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = .materialSecondaryText
        close.frame = CGRect(x: size.width - inset - 20, y: inset - 2, width: 20, height: 20)
        content.addSubview(close)

        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.bezelStyle = .push
        copyButton.sizeToFit()
        copyButton.frame.origin = CGPoint(x: size.width - inset - copyButton.frame.width,
                                          y: size.height - inset - copyButton.frame.height)
        content.addSubview(copyButton)

        let textTop = title.frame.maxY + 10
        scrollView.frame = CGRect(x: inset, y: textTop, width: size.width - inset * 2,
                                  height: copyButton.frame.minY - 10 - textTop)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        textView.configure()
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.onEscape = { [weak self] in self?.dismiss() }
        textView.onEdit = { [weak self] in
            guard let self else { return }
            status.stringValue = "" // edited: the clipboard has the old text
            refreshCopyButton()
        }
        scrollView.documentView = textView
        content.addSubview(scrollView)
        refreshCopyButton()
        accentObservation = AccentObservation { [weak self] in self?.refreshCopyButton() }
    }

    override var canBecomeKey: Bool { true }

    /// Opens next to `selection` (AppKit global coordinates) on `screen`, the one the selection was on, like
    /// the overlay toolbar (OCRPanelLayout), and takes the keyboard. Every extraction opens at its own
    /// selection; a panel dragged elsewhere stays there only until the next one.
    func show(_ state: State, nextTo selection: CGRect, on screen: NSScreen?) {
        update(state)
        let target = screen ?? NSScreen.screens.first(where: { $0.frame.intersects(selection) }) ?? NSScreen.main
        if let visible = target?.visibleFrame {
            setFrameOrigin(OCRPanelLayout.frame(size: frame.size, selection: selection, visibleFrame: visible).frame.origin)
        }
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(textView)
    }

    /// Replaces the text; only an extracted text can be edited.
    func update(_ state: State) {
        textView.isEditable = false // before replacing the text: setting it is not an edit
        switch state {
        case .recognizing:
            status.stringValue = String(localized: "正在提取…", comment: "OCR panel status")
            textView.string = ""
        case .copied(let text):
            status.stringValue = String(localized: "已拷贝", comment: "OCR panel status")
            textView.string = text
        case .noText:
            status.stringValue = String(localized: "未提取到文字", comment: "OCR panel status")
            textView.string = ""
        case .failed:
            status.stringValue = String(localized: "提取失败", comment: "OCR panel status")
            textView.string = ""
        }
        if case .copied = state { textView.isEditable = true }
        // The undo stack points into the text just replaced: ⌘Z there would raise an out-of-range exception.
        textView.undoManager?.removeAllActions()
        refreshCopyButton()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        // Only these four count: Caps Lock or fn must not stop ⌘W.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command, Self.isW(event) else { return false }
        dismiss()
        return true
    }

    /// The W key: by character, or by key code (13) when the layout types no Latin letters (Russian, Greek…).
    private static func isW(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return key == "w" || (!key.unicodeScalars.allSatisfy(\.isASCII) && event.keyCode == 13)
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }

    /// Enabled while there is text; filled with the interface accent only then (a disabled accent fill reads
    /// as pressable).
    private func refreshCopyButton() {
        copyButton.isEnabled = !textView.string.isEmpty
        copyButton.applyAccentFill(copyButton.isEnabled)
    }

    @objc private func closeClicked() {
        dismiss()
    }

    @objc private func copyClicked() {
        guard !textView.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        status.stringValue = String(localized: "已拷贝", comment: "OCR panel status")
    }
}

/// The editable result. A menu-bar app has no Edit menu, so the usual editing shortcuts are mapped here
/// (as in the annotation text box); Esc closes the panel unless an input method is composing.
private final class OCRTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onEdit: (() -> Void)?

    /// Plain text in the material's text colour, no smart substitutions: what was recognised stays as it is.
    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = .systemFont(ofSize: 13)
        textColor = .materialText
        insertionPointColor = .materialText
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { return super.cancelOperation(sender) }
        onEscape?()
    }

    override func didChangeText() {
        super.didChangeText()
        onEdit?()
    }

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
