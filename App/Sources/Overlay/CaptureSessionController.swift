import AppKit
import GlimpseCore

/// One screenshot session: capture → one overlay per screen → finish or cancel → tear down.
@MainActor
final class CaptureSessionController {
    private let settings: SettingsStore
    private let ocr: OCRController
    private let pins: PinWindowController
    private let capture = CaptureService()
    /// This session recognises text instead of editing (the menu's or the shortcut's 提取文字).
    private var recognizingText = false
    /// The colour and width all tools share, on every screen and across captures.
    private let styleStore = AnnotationStyleStore()
    /// Tells the user what happened once the overlay is gone (design doc §3.8.1).
    private let hud = HUDController()
    /// A save that finished while a newer session was running: its HUD waits for that session's close(),
    /// so it can neither be captured nor covered by the overlay.
    private var pendingHUD: (message: HUDMessage, screen: NSScreen?)?
    private var overlays: [OverlayWindow] = []
    private var isRunning = false
    /// Capture time of the session on screen (names the saved file); nil outside a session.
    private var capturedAt: Date?
    private var screenObserver: NSObjectProtocol?
    /// The overlay the mouse was last seen on; drives hover clearing and keyboard focus across screens.
    private weak var mouseScreenView: SelectionView?
    /// Set when the display layout changes while capturing; the in-flight result is then discarded.
    private var screensChangedDuringCapture = false

    /// The Screen Recording permission is missing (never granted, or revoked), or ScreenCaptureKit refused
    /// the capture anyway: the app delegate opens the onboarding window instead of an overlay (design doc
    /// §3.8 step 4, §6).
    var onPermissionMissing: ((PermissionService.Problem) -> Void)?
    /// Called before capturing; returns whether it hid one of Glimpse's windows (the onboarding window),
    /// which must not end up in the frozen screen.
    var onCaptureWillStart: (() -> Bool)?
    /// A capture worked (the permission is there): the app delegate refreshes the menu bar mark at once.
    var onCaptureSucceeded: (() -> Void)?
    /// The session is over: true once the overlay of a capture that worked is gone, false right after a
    /// capture that failed for another reason than the permission. The app delegate closes, or shows
    /// again, the onboarding window it hid; closing it hands the keyboard back to the previous app, which
    /// must not happen while the overlay is up.
    var onCaptureFinished: ((Bool) -> Void)?
    /// Set when the capture worked; close() then reports `onCaptureFinished(true)`.
    private var captureSucceeded = false
    /// The image was copied, saved or pinned (the HUD says 「已复制到剪贴板」 / 「已保存到…」, or a pin appeared):
    /// the menu bar icon flashes ✓ (design doc §3.7). Failures and the colour picker do not count.
    var onSuccess: (() -> Void)?

    init(settings: SettingsStore, ocr: OCRController, pins: PinWindowController) {
        self.settings = settings
        self.ocr = ocr
        self.pins = pins
        pins.onHUD = { [weak self] message, screen in self?.showHUD(message, on: screen) }
    }

    /// A HUD message from outside the overlay (the pins' copy and save): shown now, or, while a capture is on
    /// screen, once it closes (pendingHUD), so it is neither captured nor covered by the overlay.
    func showHUD(_ message: HUDMessage, on screen: NSScreen?) {
        if isRunning {
            pendingHUD = (message, screen)
        } else {
            present(message, on: screen)
        }
    }

    /// Shows the HUD and, for the messages that mean the image went somewhere, flashes the menu bar ✓ at the
    /// same moment (a deferred message flashes when it finally shows, not while the overlay covers the icon).
    private func present(_ message: HUDMessage, on screen: NSScreen?) {
        hud.show(message, on: screen)
        switch message {
        case .copied, .saved: onSuccess?()
        case .saveFailed, .colorCopied, .captureFailed, .screensChanged: break
        }
    }

    /// `recognizingText`: 提取文字 from the menu or its shortcut (design doc §3.5): the selection is recognised
    /// as soon as it is made, without the editing phase.
    func start(recognizingText: Bool = false) {
        guard !isRunning else { return } // hotkey pressed again while overlay is up: ignore
        // Only the preflight is checked: after a refused capture the user can still try again.
        guard PermissionService.isGranted else {
            onPermissionMissing?(.missing)
            return
        }
        isRunning = true
        self.recognizingText = recognizingText
        screensChangedDuringCapture = false
        // Before capturing: a HUD, the text recognition result, a pin's ✕ or the onboarding window still on screen
        // would be in the screenshot. A recognition still running is dropped with its panel.
        let hudWasVisible = hud.dismiss()
        let ocrPanelWasVisible = ocr.dismissPanel()
        let pinCloseWasVisible = pins.setCloseButtonsSuppressed(true) // a pin's hover ✕ (design doc §3.6)
        let windowWasHidden = onCaptureWillStart?() ?? false
        observeScreenChanges()
        Task { @MainActor in
            if hudWasVisible || ocrPanelWasVisible || pinCloseWasVisible || windowWasHidden {
                // Let one run loop turn pass so the orderOut reaches the window server before the capture.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            do {
                let result = try await capture.captureAll()
                PermissionService.captureRefused = false
                captureSucceeded = true
                onCaptureSucceeded?()
                guard !screensChangedDuringCapture else {
                    Log.app.info("screen parameters changed during capture; discarding")
                    close()
                    hud.show(.screensChanged, on: nil)
                    return
                }
                present(result)
            } catch where PermissionService.isPermissionDenial(error) {
                Log.app.error("capture refused, screen recording permission is missing: \(error.localizedDescription, privacy: .public)")
                PermissionService.captureRefused = true
                close()
                onPermissionMissing?(.captureRefused)
            } catch {
                Log.app.error("capture failed: \(error.localizedDescription, privacy: .public)")
                close()
                onCaptureFinished?(false)
                hud.show(.captureFailed, on: nil)
            }
        }
    }

    private func present(_ result: CaptureResult) {
        capturedAt = result.capturedAt
        overlays = result.screens.map { screen in
            let window = OverlayWindow(captured: screen, windows: result.windows,
                                       primaryScreenHeight: result.primaryScreenHeight, styleStore: styleStore)
            window.selectionView.delegate = self
            window.selectionView.recognizesTextOnSelection = recognizingText
            return window
        }
        // No NSApp.activate(): the overlays are non-activating panels (see OverlayWindow),
        // so they take key focus while the previously active app stays active.
        let mouse = NSEvent.mouseLocation
        guard let target = overlays.first(where: { $0.frame.containsInclusive(mouse) }) ?? overlays.first else { return }
        overlays.filter { $0 !== target }.forEach { $0.orderFrontRegardless() }
        target.makeKeyAndOrderFront(nil)
        focus(target)
        mouseScreenView = target.selectionView
        overlays.forEach { $0.selectionView.refreshHoverAtMouse() }
    }

    /// Registered as soon as a session starts (not after capture), so a layout change during
    /// the capture itself is not missed: frozen images no longer match the screens after one.
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
    }

    private func screenParametersChanged() {
        guard isRunning else { return }
        guard !overlays.isEmpty else {
            screensChangedDuringCapture = true // still capturing; start() discards the result
            return
        }
        Log.app.info("screen parameters changed; closing capture session")
        close()
        hud.show(.screensChanged, on: nil) // the screens just changed: the one under the mouse
    }

    /// Gives `window` key focus with its selection view taking the keyboard.
    private func focus(_ window: NSWindow?) {
        guard let window = window as? OverlayWindow else { return }
        window.makeKey()
        window.makeFirstResponder(window.selectionView)
    }

    /// The overlay holding the selection (at most one screen has one).
    private var selectionOwner: OverlayWindow? {
        overlays.first { $0.selectionView.hasSelection }
    }

    private func close() {
        // A text box may still hold the keyboard with an input-method composition: drop it while the
        // windows are still up, so the candidate window closes with them. No output, so nothing is committed.
        overlays.forEach { $0.selectionView.discardTyping() }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        // Nothing was activated, so focus simply returns to the previously active app.
        // close() can run from inside a window's sendEvent (keyDown/mouseDown -> finish -> delegate).
        // Keep the windows alive until the next runloop turn so AppKit never returns into a freed window.
        let closing = overlays
        overlays.forEach { $0.close() }
        overlays = []
        DispatchQueue.main.async { _ = closing }
        isRunning = false
        capturedAt = nil
        pins.setCloseButtonsSuppressed(false) // the ✕ comes back on the pin under the mouse
        mouseScreenView = nil
        if captureSucceeded {
            captureSucceeded = false
            onCaptureFinished?(true)
        }
        // The windows are ordered out above. Callers that show their own HUD next replace this one.
        if let pending = pendingHUD {
            pendingHUD = nil
            present(pending.message, on: pending.screen)
        }
    }
}

extension CaptureSessionController: SelectionViewDelegate {
    func selectionViewDidBeginSelection(_ view: SelectionView) {
        // Selection is limited to one screen: starting one clears the others.
        for window in overlays where window.selectionView !== view {
            window.selectionView.resetSelection()
        }
        focus(view.window)
    }

    func selectionViewDidCancel(_ view: SelectionView) {
        close()
    }

    func selectionView(_ view: SelectionView, didFinishWith image: CGImage, scale: CGFloat, frame: CGRect,
                       action: OverlayFinishAction) {
        let capturedAt = self.capturedAt // close() clears it
        let screen = view.window?.screen // the HUD shows where the selection was; read before the window closes
        close()
        if action == .recognizeText {
            ocr.recognize(image, selection: frame, on: screen) // next to the selection; only the text goes to the clipboard (design doc §3.5)
            return
        }
        if action == .pin {
            pins.pin(image, scale: scale, at: frame) // nothing on the clipboard (§3.2)
            onSuccess?()
            return
        }
        // Saving also copies (design doc §3.2), so a failed save still leaves the image on the clipboard.
        OutputService.copy(image, scale: scale)
        guard action == .save else {
            showHUD(.copied, on: screen)
            return
        }
        guard let date = capturedAt else {
            assertionFailure("finish without a presented capture")
            return
        }
        let directory = settings.saveDirectory
        let folder = FileManager.default.displayName(atPath: directory.path) // localized: 「下载」
        // PNG encoding + disk write happen off the main thread; the overlay is already closed.
        // The HUD waits for the outcome, back on the main actor; if a new session started meanwhile, it waits
        // for that session to close (pendingHUD).
        Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    let url = try OutputService.savePNG(image, scale: scale, to: directory, date: date)
                    Log.app.info("saved \(url.path, privacy: .private)")
                    return true
                } catch {
                    Log.app.error("save failed, image is on the clipboard: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }.value
            self?.showHUD(saved ? .saved(folder: folder) : .saveFailed, on: screen)
        }
    }

    func selectionView(_ view: SelectionView, didCopyColor text: String) {
        let screen = view.window?.screen
        close()
        hud.show(.colorCopied(text), on: screen)
    }

    func selectionViewShouldShowHover(_ view: SelectionView) -> Bool {
        selectionOwner == nil
    }

    func selectionViewDidEndWithoutSelection(_ view: SelectionView) {
        // The click made this overlay key; give focus back to the screen that still has a selection.
        focus(selectionOwner)
    }

    func selectionViewShouldBeginPress(_ view: SelectionView) -> Bool {
        // While typing, a click on another screen only ends typing (design doc §3.2.1); the keyboard goes back
        // to the screen with the selection, which the click had made key.
        guard let owner = overlays.first(where: { $0.selectionView.phase == .typing }) else { return true }
        owner.selectionView.endTyping()
        focus(owner)
        return false
    }

    func selectionViewDidRightClick(_ view: SelectionView) {
        // The phase is session-wide: with a selection anywhere, right click clears it; otherwise it exits.
        guard KeyRouter.rightClick(phase: selectionOwner != nil ? .editing(tool: nil) : .selecting) == .reselect else {
            close()
            return
        }
        overlays.forEach { $0.selectionView.resetSelection() }
        focus(view.window)
        overlays.forEach { $0.selectionView.refreshHoverAtMouse() }
    }

    func selectionViewMouseDidMove(_ view: SelectionView) {
        // Called on enter and on every mouse move; only act when the mouse changed screens.
        guard view !== mouseScreenView else { return }
        mouseScreenView = view
        // Only the screen under the mouse may show a hover highlight.
        for overlay in overlays where overlay.selectionView !== view {
            overlay.selectionView.clearHover()
        }
        // Keyboard follows the mouse between screens until a selection exists.
        guard selectionOwner == nil else { return }
        focus(view.window)
    }
}
