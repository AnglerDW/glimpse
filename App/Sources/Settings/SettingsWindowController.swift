import AppKit
import SwiftUI

/// The settings window, opened from the menu bar's 「设置…」 (design doc §3.7, §3.9). One window, created
/// on first use and kept; Glimpse is activated so the window comes to the front, and has a Dock icon
/// while it is open (DockPresence).
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        model.reload()
        let window = self.window ?? makeWindow()
        self.window = window
        model.sheetParent = window
        DockPresence.bringToFront(window)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = String(localized: "Glimpse 设置", comment: "Settings window title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let window { DockPresence.remove(window) }
            }
        }
        // Back from System Settings (login items): show what changed there. Only the login item: a
        // shortcut's red line must survive switching apps.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isVisible == true else { return }
                self.model.reloadLoginItem()
            }
        }
        return window
    }
}

/// A menu-bar app has no main menu, so ⌘W and ⌘Q are handled here. Offered to the views first, so the
/// shortcut recorder can take them while it records.
private final class SettingsWindow: NSWindow {
    /// The recorder keeps the global shortcuts off while it records: closing the window or leaving it
    /// for another one ends the recording, which puts them back.
    override func close() {
        endRecording()
        super.close()
    }

    override func resignKey() {
        super.resignKey()
        endRecording()
    }

    private func endRecording() {
        if firstResponder is HotkeyRecorderButton { makeFirstResponder(nil) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        // Only these four count: Caps Lock or fn must not stop ⌘W.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command else { return false }
        var key = event.charactersIgnoringModifiers?.lowercased()
        if let typed = key, !typed.unicodeScalars.allSatisfy(\.isASCII) {
            key = [13: "w", 12: "q"][event.keyCode] // a layout without Latin letters (Russian, Greek…): by key code
        }
        switch key {
        case "w":
            // A ⌘W still held after the recorder rejected it repeats here: it must not close the window.
            if !event.isARepeat { performClose(nil) }
            return true
        case "q":
            if !event.isARepeat { NSApp.terminate(nil) }
            return true
        default:
            return false
        }
    }

    /// A key still held after the recorder took it repeats with nobody to take it: swallow the repeats
    /// instead of beeping at each one.
    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        super.keyDown(with: event)
    }
}
