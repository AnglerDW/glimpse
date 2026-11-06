import CoreGraphics

/// An on-screen window. `frame` is in CG global coordinates (top-left origin).
public struct WindowInfo: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let layer: Int
    public let ownerPID: pid_t

    public init(windowID: CGWindowID, frame: CGRect, layer: Int, ownerPID: pid_t) {
        self.windowID = windowID
        self.frame = frame
        self.layer = layer
        self.ownerPID = ownerPID
    }
}

public enum WindowHitTester {
    /// Drops non-normal windows (layer > 0) that cover a whole display, such as a third-party tint or
    /// dim overlay. Left in, they would be the first hit everywhere and disable all highlighting.
    /// Layer 0 is kept: a full-screen app window is a legitimate target.
    /// `displayFrames` are in CG global coordinates, like `WindowInfo.frame`.
    public static func removingDisplayCoveringOverlays(_ windows: [WindowInfo], displayFrames: [CGRect]) -> [WindowInfo] {
        windows.filter { window in
            guard window.layer > 0 else { return true }
            return !displayFrames.contains { $0.width > 0 && $0.height > 0 && window.frame.contains($0) }
        }
    }

    /// Drops Glimpse's own normal windows (layer 0, such as the settings window): they are never a target.
    /// Its windows above layer 0 (pinned screenshots, the text recognition panel) are kept as occluders:
    /// they are in the frozen screen, so the window behind one must not light up under the mouse.
    public static func removingOwnWindows(_ windows: [WindowInfo], ownPID: pid_t) -> [WindowInfo] {
        windows.filter { $0.ownerPID != ownPID || $0.layer > 0 }
    }

    /// `windows` must be ordered front-to-back (the order CGWindowListCopyWindowInfo returns) and may
    /// include every layer. The first window under the point wins; it is returned only if it is a normal
    /// app window (layer 0), so a Dock, menu bar or floating panel in front blocks the window behind it.
    public static func topmostWindow(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        guard let hit = windows.first(where: { $0.frame.width > 1 && $0.frame.height > 1 && $0.frame.contains(point) }),
              hit.layer == 0 else { return nil }
        return hit
    }
}
