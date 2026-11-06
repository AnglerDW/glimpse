import AppKit

/// Glimpse is a menu-bar app with no Dock icon. While the settings or onboarding window is open it shows in
/// the Dock and in ⌘Tab, so the window can be found again behind other apps; once both are closed it goes back
/// to the menu bar only and hands the keyboard back to the app that was in front before.
@MainActor
enum DockPresence {
    private static var windows: Set<ObjectIdentifier> = []
    /// The last app other than Glimpse to become active; it gets the keyboard back. Kept current while
    /// one of our windows is open, so returning to Glimpse through the Dock or ⌘Tab hands back to the app
    /// the user just left, not the one in front when the window first opened.
    private static var previousApp: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    static func add(_ window: NSWindow) {
        watchActivations()
        guard windows.insert(ObjectIdentifier(window)).inserted, windows.count == 1 else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func remove(_ window: NSWindow) {
        guard windows.remove(ObjectIdentifier(window)) != nil, windows.isEmpty else { return }
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(.accessory)
        // Not NSApp.hide: it would hide the pinned screenshots too. Under cooperative activation (macOS 14+)
        // Glimpse yields first, so the other app's activate() is honoured.
        if wasActive, let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }

    /// Shows `window` in front with the keyboard and activates Glimpse. From the menu bar menu or at launch
    /// macOS grants the activation; from a global shortcut it may refuse it (cooperative activation on
    /// macOS 14+), so the window is ordered front and made key first, and is visible and usable either way.
    static func bringToFront(_ window: NSWindow) {
        if !NSApp.isActive, let app = NSWorkspace.shared.frontmostApplication, !isGlimpse(app) {
            previousApp = app
        }
        add(window)
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    /// Remembers every other app that becomes active, from the first time one of our windows opens.
    private static func watchActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, !isGlimpse(app) { previousApp = app }
            }
        }
    }

    private static func isGlimpse(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
