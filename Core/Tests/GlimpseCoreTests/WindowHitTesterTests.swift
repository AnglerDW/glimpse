import CoreGraphics
import Testing
@testable import GlimpseCore

struct WindowHitTesterTests {
    // Front-to-back, as CGWindowListCopyWindowInfo returns them. Frames are CG global.
    let windows = [
        WindowInfo(windowID: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 33), layer: 25, ownerPID: 10),     // menu bar
        WindowInfo(windowID: 2, frame: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, ownerPID: 11),  // front
        WindowInfo(windowID: 3, frame: CGRect(x: 50, y: 50, width: 800, height: 600), layer: 0, ownerPID: 12),    // behind
    ]

    @Test func picksFrontmostNormalWindow() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 200, y: 200), in: windows)?.windowID == 2)
    }

    @Test func fallsThroughToWindowBehind() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 60, y: 60), in: windows)?.windowID == 3)
    }

    @Test func ignoresNonNormalLayers() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 10, y: 10), in: windows) == nil)
    }

    @Test func emptyAreaHitsNothing() {
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 1000, y: 1000), in: windows) == nil)
    }

    @Test func higherLayerWindowBlocksWindowBehind() {
        let dock = WindowInfo(windowID: 4, frame: CGRect(x: 0, y: 150, width: 120, height: 200), layer: 20, ownerPID: 13)
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 60, y: 200), in: [dock] + windows) == nil)
        // Outside the Dock's frame the window behind is still reachable.
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 200, y: 200), in: [dock] + windows)?.windowID == 2)
    }

    @Test func displayCoveringOverlaysAreDroppedButNormalWindowsKept() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let tint = WindowInfo(windowID: 6, frame: display, layer: 8, ownerPID: 15)
        let fullScreenApp = WindowInfo(windowID: 7, frame: display, layer: 0, ownerPID: 16)
        let result = WindowHitTester.removingDisplayCoveringOverlays([tint, fullScreenApp] + windows, displayFrames: [display])
        #expect(result.map(\.windowID) == [7, 1, 2, 3])   // the menu bar does not cover the display
    }

    @Test func ownPinsBlockTheWindowBehindButAreNeverHit() {
        // Glimpse is pid 20: a pinned screenshot (floating, layer 3) over the front window, and a normal
        // Glimpse window (layer 0, such as the settings window) elsewhere.
        let pin = WindowInfo(windowID: 8, frame: CGRect(x: 150, y: 150, width: 100, height: 100), layer: 3, ownerPID: 20)
        let settings = WindowInfo(windowID: 9, frame: CGRect(x: 600, y: 100, width: 200, height: 200), layer: 0, ownerPID: 20)
        let kept = WindowHitTester.removingOwnWindows([pin, settings] + windows, ownPID: 20)
        #expect(kept.map(\.windowID) == [8, 1, 2, 3])
        // Over the pin nothing is highlighted; beside it the window behind still is.
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 200, y: 200), in: kept) == nil)
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 300, y: 300), in: kept)?.windowID == 2)
        // Where the settings window was, the window behind it is the target.
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 700, y: 200), in: kept)?.windowID == 3)
    }

    @Test func tinyWindowsAreSkippedNotBlocking() {
        let sliver = WindowInfo(windowID: 5, frame: CGRect(x: 55, y: 0, width: 1, height: 800), layer: 25, ownerPID: 14)
        #expect(WindowHitTester.topmostWindow(at: CGPoint(x: 55.5, y: 200), in: [sliver] + windows)?.windowID == 3)
    }
}
