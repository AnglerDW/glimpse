import AppKit
import GlimpseCore
import ScreenCaptureKit

struct CapturedScreen {
    let info: ScreenInfo
    let image: CGImage
    let nsScreen: NSScreen
}

struct CaptureResult {
    let screens: [CapturedScreen]
    /// Front-to-back, CG global frames; of Glimpse's own windows only the occluders (pins, panels) are kept.
    let windows: [WindowInfo]
    let primaryScreenHeight: CGFloat
    /// When the capture finished; used for the saved file's name.
    let capturedAt = Date()
}

enum CaptureError: Error {
    case noDisplays
    /// An NSScreen has no matching SCDisplay (displays changed mid-capture).
    case displayMismatch
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
final class CaptureService {
    /// Capture first, show overlays afterwards, so the overlay never appears in the image (design doc §3.2).
    func captureAll() async throws -> CaptureResult {
        // Read the layout before the first await so windows and screen height describe the same moment.
        let windows = Self.onScreenWindows()
        guard let primary = NSScreen.screens.first else { throw CaptureError.noDisplays }
        let primaryScreenHeight = primary.frame.height

        // Only displays are needed, so desktop windows can be skipped.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)

        // Build every job on the main actor (NSScreen is main-thread only).
        var jobs: [(info: ScreenInfo, screen: NSScreen, filter: SCContentFilter, config: SCStreamConfiguration)] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.displayMismatch
            }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            // Match the live screen's colour space so the frozen image looks identical on P3 displays.
            if let colorSpaceName = screen.colorSpace?.cgColorSpace?.name {
                config.colorSpaceName = colorSpaceName
            }
            // Nothing excluded: our status-bar item belongs to this process, so excluding the app
            // would drop it from the image. Pinned screenshots stay in it too, like any window on screen
            // (design doc §3.6); the window list keeps them only as occluders, so they are never snapped to.
            let filter = SCContentFilter(display: display, excludingWindows: [])
            jobs.append((ScreenInfo(displayID: id, frame: screen.frame, scale: screen.backingScaleFactor),
                         screen, filter, config))
        }
        guard !jobs.isEmpty else { throw CaptureError.noDisplays }

        // Capture all displays concurrently, then reassemble in NSScreen.screens order.
        var images = [CGImage?](repeating: nil, count: jobs.count)
        try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, job) in jobs.enumerated() {
                let filter = job.filter
                let config = job.config
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (index, image)
                }
            }
            for try await (index, image) in group {
                images[index] = image
            }
        }

        // Every child task either returned or threw, so every slot is filled.
        let captured = zip(jobs, images).compactMap { job, image in
            image.map { CapturedScreen(info: job.info, image: $0, nsScreen: job.screen) }
        }
        return CaptureResult(screens: captured, windows: windows, primaryScreenHeight: primaryScreenHeight)
    }

    /// ScreenCaptureKit's window list has no z-order; CGWindowList returns windows front-to-back.
    /// Windows of every layer are kept so the hit tester sees what covers a normal window (Dock,
    /// menu bar, floating panels); it only ever returns layer 0. Fully transparent windows (alpha 0)
    /// and anything at or above the screen-saver level (cursor, shielding, our overlay level) are dropped
    /// here so invisible full-screen system windows cannot block highlighting. Of our own windows only
    /// those above layer 0 stay, as occluders: a pinned screenshot hides the window behind it.
    static func onScreenWindows() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let displayFrames = NSScreen.screens.compactMap { $0.displayID }.map { CGDisplayBounds($0) }
        let all: [WindowInfo] = list.compactMap { entry in
            // Some apps keep fully transparent layer-0 windows on screen; they must not be snapped to.
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer < Int(CGWindowLevelForKey(.screenSaverWindow)),
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            return WindowInfo(windowID: number, frame: bounds, layer: layer, ownerPID: pid)
        }
        return WindowHitTester.removingDisplayCoveringOverlays(WindowHitTester.removingOwnWindows(all, ownPID: ownPID),
                                                               displayFrames: displayFrames)
    }
}
