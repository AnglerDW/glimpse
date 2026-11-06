import AppKit
import GlimpseCore

/// One borderless full-screen panel per display. Must be able to become key,
/// otherwise Esc / Enter / letter keys go to the previously active app (design doc §5.1).
///
/// A non-activating panel takes key focus without activating Glimpse: on macOS 14+
/// cooperative activation may refuse `NSApp.activate()` for a hotkey-triggered LSUIElement
/// app, and hiding the app afterwards to return focus would also hide future pin windows.
final class OverlayWindow: NSPanel {
    let selectionView: SelectionView

    init(captured: CapturedScreen, windows: [WindowInfo], primaryScreenHeight: CGFloat, styleStore: AnnotationStyleStore) {
        let content = OverlayContentView(captured: captured, windows: windows, primaryScreenHeight: primaryScreenHeight,
                                         styleStore: styleStore)
        selectionView = content.selectionView
        super.init(contentRect: captured.nsScreen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        contentView = content
        setFrame(captured.nsScreen.frame, display: false)
        initialFirstResponder = selectionView
    }

    override var canBecomeKey: Bool { true }
}
