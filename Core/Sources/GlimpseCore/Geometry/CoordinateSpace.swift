import CoreGraphics

/// One display. `frame` is in AppKit global coordinates (origin at the primary screen's
/// bottom-left, y up), in points. `scale` is the backing scale factor (2 on Retina).
/// `scale` must equal captured image pixels ÷ frame points, or pixel crops will be off.
public struct ScreenInfo: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
    }
}

/// Conversions between the coordinate systems Glimpse deals with.
///
/// - CG global: origin at the primary screen's top-left, y down (CGWindowList).
/// - AppKit global: origin at the primary screen's bottom-left, y up (NSScreen, NSEvent).
/// - Local: origin at one screen's top-left, y down, points (overlay views, selection).
/// - Pixel: local × scale, matching the captured CGImage (origin top-left).
///
/// Every `primaryScreenHeight` parameter must come from `NSScreen.screens[0]` (the screen
/// with the menu bar), not `NSScreen.main` (the screen with keyboard focus).
public enum CoordinateSpace {
    public static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func localPoint(fromAppKit point: CGPoint, in screen: ScreenInfo) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
    }

    public static func localRect(fromAppKit rect: CGRect, in screen: ScreenInfo) -> CGRect {
        CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    public static func appKitRect(fromLocal rect: CGRect, in screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    public static func localRect(fromCG rect: CGRect, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGRect {
        localRect(fromAppKit: appKitRect(fromCG: rect, primaryScreenHeight: primaryScreenHeight), in: screen)
    }

    public static func cgGlobalPoint(fromLocal point: CGPoint, in screen: ScreenInfo, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: screen.frame.minX + point.x, y: primaryScreenHeight - (screen.frame.maxY - point.y))
    }

    /// Local points → pixel rect in the captured image, snapped outward to whole pixels
    /// so the crop never loses a partially covered pixel.
    public static func pixelRect(fromLocal rect: CGRect, scale: CGFloat) -> CGRect {
        let x0 = snapped(rect.minX * scale).rounded(.down)
        let y0 = snapped(rect.minY * scale).rounded(.down)
        let x1 = snapped(rect.maxX * scale).rounded(.up)
        let y1 = snapped(rect.maxY * scale).rounded(.up)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Snaps values within 1e-6 of an integer to it, so floating-point noise
    /// (e.g. 200.00000000001) doesn't grab an extra pixel when rounding outward.
    private static func snapped(_ v: CGFloat) -> CGFloat {
        let n = v.rounded()
        return abs(v - n) < 1e-6 ? n : v
    }
}

extension CGRect {
    /// Like `contains(_:)`, but the max edges count as inside too. `contains` excludes maxX / maxY,
    /// where the mouse can sit (the last row / column of a screen, in AppKit's or a view's coordinates).
    public func containsInclusive(_ point: CGPoint) -> Bool {
        !isNull && point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
