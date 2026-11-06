import AppKit
import GlimpseCore

/// A push button that records a global shortcut (design doc §3.9). Click it, then press the shortcut:
/// Esc cancels, Delete clears, anything else goes through `HotkeyRecording`. While recording it holds the
/// keyboard and shows the modifiers being held; clicking anywhere else (even on something that never takes
/// the keyboard, like the form's background or the clear button), leaving the window or closing it cancels.
/// While recording, the bezel takes the interface accent (design doc §3.9), like the settings switch.
final class HotkeyRecorderButton: NSButton {
    var combo: KeyCombo? {
        didSet { if combo != oldValue { refreshTitle() } }
    }
    /// The other action's shortcut, which this one may not repeat.
    var otherCombo: KeyCombo?
    /// Recording started (true) or ended (false). The owner suspends the global shortcuts meanwhile.
    var onRecordingChange: ((Bool) -> Void)?
    var onOutcome: ((HotkeyRecording.Outcome) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            isRecording ? watchClicks() : stopWatchingClicks()
            refreshTitle()
            onRecordingChange?(isRecording)
        }
    }
    private var heldModifiers: UInt32 = 0
    /// While recording: clicks anywhere in Glimpse, so one outside the button ends the recording. A click on
    /// a view that never becomes first responder would not take the keyboard away, so resigning alone
    /// does not cover it.
    private var clickMonitor: Any?
    /// Repaints the recording bezel when the interface accent changes.
    private var accentObservation: AccentObservation?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 140, height: 24))
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        refreshTitle()
        accentObservation = AccentObservation { [weak self] in
            guard let self else { return }
            applyAccentFill(isRecording)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isRecording }

    @objc private func clicked() {
        if isRecording {
            stopRecording()
        } else {
            heldModifiers = 0
            isRecording = true
            window?.makeFirstResponder(self)
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    private func watchClicks() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let inside = event.window === self.window
                    && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                if !inside { self.stopRecording() } // a click on the button itself toggles it in clicked()
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false // clicking elsewhere cancels
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { isRecording = false }
        super.viewWillMove(toWindow: newWindow)
    }

    /// ⌘ combos arrive here, before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        heldModifiers = Self.carbonModifiers(event.modifierFlags)
        refreshTitle()
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return } // a key held since before recording began
        let outcome = HotkeyRecording.interpret(keyCode: UInt32(event.keyCode),
                                                modifiers: Self.carbonModifiers(event.modifierFlags),
                                                other: otherCombo)
        stopRecording() // first, so the shortcuts are back before the new one is applied
        onOutcome?(outcome)
    }

    private func refreshTitle() {
        if isRecording {
            let held = KeyCombo.symbols(forModifiers: heldModifiers)
            title = held.isEmpty ? String(localized: "请按快捷键…", comment: "Shortcut recorder while recording") : held
        } else {
            title = combo?.displayString ?? String(localized: "点击录制", comment: "Shortcut recorder with no shortcut")
        }
        applyAccentFill(isRecording) // after the title: setting it drops the accent title colour
        setAccessibilityLabel(isRecording
                              ? String(localized: "正在录制快捷键", comment: "Accessibility: shortcut recorder")
                              : (combo.map { String(localized: "快捷键 \($0.displayString)", comment: "Accessibility: shortcut recorder; %@ is the shortcut") }
                                 ?? String(localized: "未设置快捷键", comment: "Accessibility: shortcut recorder")))
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        return modifiers
    }
}
