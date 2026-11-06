import AppKit
import GlimpseCore
import os
import SwiftUI

/// The accent picked in Settings (design doc §3.9). Set at launch and on every change; read whenever
/// `NSColor.glimpseAccent` resolves, which AppKit may do off the main thread, hence the lock.
enum InterfaceAccent {
    private static let choice = OSAllocatedUnfairLock(initialState: AccentColor.system)

    /// Posted on the main thread when the choice changes.
    static let didChangeNotification = Notification.Name("GlimpseInterfaceAccentDidChange")

    static var current: AccentColor {
        get { choice.withLock { $0 } }
        set {
            let previous = choice.withLock { stored in
                let previous = stored
                stored = newValue
                return previous
            }
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
}

extension NSColor {
    /// Glimpse's interface accent: the selection border and handles, the selected toolbar button, ✓, the
    /// chosen colour swatch's ring, the magnifier's crosshair (design doc §3.9, §4.3). The system accent,
    /// or the preset picked in Settings, a step brighter in dark appearance. Annotation colours never use it.
    /// Resolved each time it is drawn; views that keep it as a CGColor refresh through `AccentObservation`.
    static let glimpseAccent = NSColor(name: "glimpseAccent") { appearance in
        if let preset = InterfaceAccent.current.rgba(darkAppearance: appearance.isDark) {
            return preset.nsColor
        }
        var system = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            system = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        }
        return system
    }
}

extension NSColor {
    /// The title colour on a button filled with `glimpseAccent`: white, or black where white would fall below
    /// 3:1 (`RGBA.filledButtonPrefersDarkTitle`: orange, green, the brighter graphite, or such a system accent).
    static let glimpseAccentTitle = NSColor(name: "glimpseAccentTitle") { appearance in
        var fill: RGBA?
        appearance.performAsCurrentDrawingAppearance {
            if let accent = NSColor.glimpseAccent.usingColorSpace(.sRGB) {
                fill = RGBA(red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent)
            }
        }
        return fill?.filledButtonPrefersDarkTitle == true ? .black : .white
    }
}

extension NSButton {
    /// Fills a push button's bezel with the interface accent, its title in `glimpseAccentTitle`, or (false)
    /// puts back the plain button. Call it again after changing `title` (which drops the attributed one) and
    /// when the accent changes: both colours resolve when drawn, but the button must be told to redraw.
    func applyAccentFill(_ filled: Bool) {
        let plain = title
        bezelColor = nil // a new value each time, so the button drops what it resolved before
        guard filled else {
            title = plain
            needsDisplay = true
            return
        }
        bezelColor = .glimpseAccent
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(string: plain, attributes: [
            .foregroundColor: NSColor.glimpseAccentTitle,
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .paragraphStyle: paragraph,
        ])
        needsDisplay = true
    }
}

/// Calls `handler` on the main thread whenever the accent may look different: the Settings choice changed,
/// or the system accent changed (System Settings → Appearance), which matters while following the system.
/// Views that cache the accent as a CGColor or in drawn content keep one of these for as long as they live.
final class AccentObservation {
    private var tokens: [NSObjectProtocol] = []

    init(_ handler: @escaping @MainActor () -> Void) {
        for name in [InterfaceAccent.didChangeNotification, NSColor.systemColorsDidChangeNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

extension AccentColor {
    /// The SwiftUI tint for Glimpse's own windows (settings, onboarding): the preset, a step brighter in dark
    /// appearance; nil while following the system, which keeps SwiftUI's own (system) accent.
    var tint: Color? {
        guard self != .system else { return nil }
        let accent = self
        return Color(nsColor: NSColor(name: nil) { appearance in
            accent.rgba(darkAppearance: appearance.isDark)?.nsColor ?? .controlAccentColor
        })
    }
}
