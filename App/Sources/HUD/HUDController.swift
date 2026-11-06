import AppKit
import GlimpseCore

/// Short glass notices after a capture ends (design doc §3.8.1): 「已复制到剪贴板」, 「已保存到「下载」」, failures.
/// One borderless, non-activating panel above normal windows that never takes clicks or focus, so the
/// previously active app keeps the keyboard. It fades in, stays `HUDLayout.displayDuration`, fades out;
/// a new message replaces the one on screen and restarts the timer. With Reduce Motion it appears and
/// disappears without fading. No system notifications (no notification permission to ask for).
@MainActor
final class HUDController {
    /// Room around the glass for its shadow (the system glass's own, or the macOS 14 / 15 emulated one,
    /// which reaches about 40pt below the shape); the panel itself is transparent.
    private static let shadowRoom: CGFloat = 48
    /// Least space between the HUD and the sides of the screen; longer messages are truncated.
    private static let screenMargin: CGFloat = 24

    private lazy var panel = HUDPanel()
    /// Hides the current message; cancelled when a new one replaces it.
    private var hideTask: Task<Void, Never>?

    /// Shows `message` on `screen` (the screen the capture happened on); if that screen is gone or nil,
    /// on the screen under the mouse. Call after the overlay has closed, so it cannot cover the HUD.
    func show(_ message: HUDMessage, on screen: NSScreen?) {
        let target = screen.flatMap { NSScreen.screens.contains($0) ? $0 : nil } ?? Self.screenUnderMouse
        guard let target else { return }
        hideTask?.cancel()

        let hud = HUDView(message: message, maxWidth: target.visibleFrame.width - Self.screenMargin * 2)
        let room = Self.shadowRoom
        let hudFrame = HUDLayout.frame(size: hud.frame.size, visibleFrame: target.visibleFrame)
        hud.frame.origin = CGPoint(x: room, y: room)
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hud)
        panel.setFrame(hudFrame.insetBy(dx: -room, dy: -room), display: true)

        if !panel.isVisible {
            panel.alphaValue = Self.reduceMotion ? 1 : 0
            panel.orderFrontRegardless() // not makeKey: the HUD never takes focus
        }
        fade(to: 1)
        // The panel never takes focus, so VoiceOver would not read it on its own. Posted from the panel, not
        // NSApp: Glimpse is never the active app, and announcements from an inactive app's application
        // element can be dropped.
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: message.text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HUDLayout.displayDuration))
            guard !Task.isCancelled, let self else { return }
            self.fade(to: 0)
            try? await Task.sleep(for: .seconds(Self.reduceMotion ? 0 : HUDLayout.fadeDuration))
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Takes the HUD off screen at once. A new capture calls this first: the captures exclude nothing,
    /// so a HUD still on screen would end up in the screenshot. Returns whether it was on screen.
    @discardableResult
    func dismiss() -> Bool {
        hideTask?.cancel()
        hideTask = nil
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        return wasVisible
    }

    /// Fading is the window's alpha, animated by the window server; at rest it is 1, so the glass inside
    /// is never drawn into a translucent group (see MaterialView).
    private func fade(to alpha: CGFloat) {
        guard !Self.reduceMotion else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDLayout.fadeDuration
            panel.animator().alphaValue = alpha
        }
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.containsInclusive(mouse) } ?? NSScreen.main
    }
}

/// The HUD's window: borderless, transparent, non-activating; above normal windows and the Dock, on every
/// Space and over full-screen apps; clicks go through to whatever is underneath.
private final class HUDPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the glass casts its own
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = NSView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
