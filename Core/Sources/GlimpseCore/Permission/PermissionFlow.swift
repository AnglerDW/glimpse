/// The onboarding window's state (design doc §3.8). Screen Recording often only takes effect after a
/// restart, so after the user went to System Settings and came back without it, the window offers one.
public struct PermissionFlow: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Show 「去授权」.
        case needsGrant
        /// 「去授权」 only brought up the system's own prompt (its 「打开系统设置」 button may have opened System
        /// Settings without us knowing): show 「去授权」 plus a quiet hint with a secondary restart button.
        case restartHint
        /// Show 「去授权」 and 「重新启动 Glimpse」.
        case needsRestart
        /// Close the window; capturing works.
        case granted
    }

    public private(set) var step: Step = .needsGrant
    /// ScreenCaptureKit refused a capture although the preflight says granted (design doc §6). The preflight
    /// cannot tell when this is over, so the window stays (offering the restart) until the user closes it.
    public private(set) var isCaptureRefused = false
    /// System Settings was opened from this window. Only then can "back without the grant" mean the grant
    /// needs a restart: declining the system's first prompt is not a visit to System Settings.
    private var openedSystemSettings = false

    public init() {}

    /// 「去授权」 clicked. `openedSystemSettings` is false the very first time, when only the system's own
    /// prompt appears (see PermissionService.request).
    public mutating func didRequest(openedSystemSettings opened: Bool) {
        if opened {
            openedSystemSettings = true
        } else if step == .needsGrant {
            step = .restartHint
        }
    }

    /// A capture was refused while the preflight says granted: offer the restart at once.
    public mutating func captureWasRefused() {
        isCaptureRefused = true
        step = .needsRestart
    }

    /// The once-a-second check while the window is open.
    public mutating func poll(granted: Bool) {
        if granted, !isCaptureRefused { step = .granted }
    }

    /// Glimpse became the active app again, i.e. the user is back from System Settings (§3.8 step 3).
    public mutating func appDidBecomeActive(granted: Bool) {
        if granted {
            if !isCaptureRefused { step = .granted }
        } else if openedSystemSettings {
            step = .needsRestart
        }
    }
}
