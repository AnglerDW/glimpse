import AppKit
import GlimpseCore

/// Every pinned screenshot (design doc §3.6); any number at once. A pin lives until it is closed or
/// Glimpse quits.
@MainActor
final class PinWindowController {
    /// Shows a HUD message. The capture session sets it, so a message that arrives while a capture is on
    /// screen waits for it to close instead of being captured or covered.
    var onHUD: ((HUDMessage, NSScreen?) -> Void)?
    /// The number of pins on screen changed (a pin was added or closed). The menu bar icon and the
    /// 「关闭所有贴图 (N)」 menu item follow it (design doc §3.7).
    var onCountChange: ((Int) -> Void)?

    private let settings: SettingsStore
    private var pins: [PinWindow] = [] {
        didSet { if pins.count != oldValue.count { onCountChange?(pins.count) } }
    }
    private var screenObserver: NSObjectProtocol?

    init(settings: SettingsStore) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringBackStrandedPins() }
        }
    }

    /// Pins `image` at `frame` (AppKit global coordinates: where the selection was).
    func pin(_ image: CGImage, scale: CGFloat, at frame: CGRect) {
        let pin = PinWindow(image: image, scale: scale, frame: frame)
        pin.onCommand = { [weak self] pin, command in self?.perform(command, on: pin) }
        pins.append(pin)
        pin.orderFrontRegardless() // never key: the active app keeps the keyboard
        pin.refreshHover() // it appears under the mouse: show its ✕ at once
    }

    private func perform(_ command: PinWindow.Command, on pin: PinWindow) {
        switch command {
        case .copy:
            OutputService.copy(pin.image, scale: pin.scale)
            onHUD?(.copied, pin.screen)
        case .save:
            save(pin)
        case .close:
            // This runs inside the pin's sendEvent (double click or menu item): keep it alive until the next
            // runloop turn so AppKit never returns into a freed window.
            pin.close()
            pins.removeAll { $0 === pin }
            DispatchQueue.main.async { _ = pin }
        }
    }

    /// 「关闭所有贴图」 from the status menu (design doc §3.7).
    func closeAll() {
        let closing = pins
        for pin in closing { pin.close() }
        pins.removeAll()
        DispatchQueue.main.async { _ = closing } // same caution as a single close
    }

    /// A capture is starting (true) or over (false): hides every pin's ✕ so none is in the frozen screen, and
    /// afterwards shows it again on the pin under the mouse. Returns whether one was on screen.
    @discardableResult
    func setCloseButtonsSuppressed(_ suppressed: Bool) -> Bool {
        var wasVisible = false
        for pin in pins {
            if pin.setCloseButtonSuppressed(suppressed) { wasVisible = true }
            if !suppressed { pin.refreshHover() }
        }
        return wasVisible
    }

    /// A display was unplugged or rearranged: a pin that is now on no screen moves to the middle of the main
    /// screen (the top-left corner when it is larger), so it can be reached and closed again.
    private func bringBackStrandedPins() {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return } // the menu-bar screen
        for pin in pins where !NSScreen.screens.contains(where: { $0.frame.intersects(pin.frame) }) {
            let size = pin.frame.size
            let origin = CGPoint(x: max(visible.minX, visible.midX - size.width / 2).rounded(),
                                 y: min(visible.maxY - size.height, visible.midY - size.height / 2).rounded())
            pin.setFrameOrigin(origin)
            pin.refreshHover() // moved without the mouse: entered / exited events do not come
        }
    }

    /// Like ⌘S in the overlay: copies too, so a failed save still leaves the image on the clipboard.
    private func save(_ pin: PinWindow) {
        let image = pin.image, scale = pin.scale, screen = pin.screen
        OutputService.copy(image, scale: scale)
        let directory = settings.saveDirectory
        let folder = FileManager.default.displayName(atPath: directory.path)
        let date = Date()
        Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    _ = try OutputService.savePNG(image, scale: scale, to: directory, date: date)
                    return true
                } catch {
                    Log.app.error("saving a pin failed, image is on the clipboard: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }.value
            self?.onHUD?(saved ? .saved(folder: folder) : .saveFailed, screen)
        }
    }
}
