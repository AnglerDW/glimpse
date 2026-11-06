import CoreGraphics
import Testing
@testable import GlimpseCore

/// Layout used by every test:
/// - primary: built-in 1728×1117 @2x at AppKit origin
/// - external: 2560×1440 @1x to the LEFT of primary, top edges aligned
///   (AppKit minY = 1117 - 1440 = -323; in CG global coords its top-left is (-2560, 0))
struct CoordinateSpaceTests {
    let primary = ScreenInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2)
    let external = ScreenInfo(displayID: 2, frame: CGRect(x: -2560, y: -323, width: 2560, height: 1440), scale: 1)
    let primaryHeight: CGFloat = 1117

    @Test func cgRectToAppKitRect() {
        let r = CoordinateSpace.appKitRect(fromCG: CGRect(x: 100, y: 50, width: 200, height: 100),
                                           primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 100, y: 967, width: 200, height: 100))
    }

    @Test func appKitPointToLocalOnExternalScreen() {
        // 60pt right of the external screen's left edge, 40pt below its top edge.
        let p = CoordinateSpace.localPoint(fromAppKit: CGPoint(x: -2500, y: 1077), in: external)
        #expect(p == CGPoint(x: 60, y: 40))
    }

    @Test func cgRectToLocalOnExternalScreen() {
        let r = CoordinateSpace.localRect(fromCG: CGRect(x: -2460, y: 30, width: 300, height: 200),
                                          in: external, primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 100, y: 30, width: 300, height: 200))
    }

    @Test func cgRectToLocalOnPrimaryIsIdentity() {
        let r = CoordinateSpace.localRect(fromCG: CGRect(x: 10, y: 20, width: 30, height: 40),
                                          in: primary, primaryScreenHeight: primaryHeight)
        #expect(r == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func localPointToCGGlobalOnExternalScreen() {
        let g = CoordinateSpace.cgGlobalPoint(fromLocal: CGPoint(x: 100, y: 30),
                                              in: external, primaryScreenHeight: primaryHeight)
        #expect(g == CGPoint(x: -2460, y: 30))
    }

    @Test func pixelRectOnRetinaSnapsOutwardToWholePixels() {
        let r = CoordinateSpace.pixelRect(fromLocal: CGRect(x: 10.25, y: 20.5, width: 100, height: 50), scale: 2)
        #expect(r == CGRect(x: 20, y: 41, width: 201, height: 100))
    }

    @Test func pixelRectOnNonRetinaIsUnchanged() {
        let r = CoordinateSpace.pixelRect(fromLocal: CGRect(x: 3, y: 4, width: 5, height: 6), scale: 1)
        #expect(r == CGRect(x: 3, y: 4, width: 5, height: 6))
    }

    @Test func pixelRectIgnoresFloatingPointNoise() {
        // maxX = 0.1 + 0.2 = 0.30000000000000004; ×10 = 3.0000000000000004, which would round up to 4.
        let r = CoordinateSpace.pixelRect(fromLocal: CGRect(x: 0.1, y: 0, width: 0.2, height: 1), scale: 10)
        #expect(r == CGRect(x: 1, y: 0, width: 2, height: 10))
    }

    @Test func localRectToAppKitOnExternalScreen() {
        // The inverse of localRect(fromAppKit:): 100pt right of and 30pt below the external screen's top-left.
        let local = CGRect(x: 100, y: 30, width: 300, height: 200)
        let global = CoordinateSpace.appKitRect(fromLocal: local, in: external)
        #expect(global == CGRect(x: -2460, y: 887, width: 300, height: 200))
        #expect(CoordinateSpace.localRect(fromAppKit: global, in: external) == local)
    }

    @Test func containsInclusiveCountsMaxEdges() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(!r.contains(CGPoint(x: 100, y: 50)))          // what containsInclusive exists to fix
        #expect(r.containsInclusive(CGPoint(x: 100, y: 50)))
        #expect(r.containsInclusive(CGPoint(x: 0, y: 0)))
        #expect(r.containsInclusive(CGPoint(x: 50, y: 25)))
        #expect(!r.containsInclusive(CGPoint(x: 100.5, y: 25)))
        #expect(!r.containsInclusive(CGPoint(x: 50, y: -0.5)))
        #expect(!CGRect.null.containsInclusive(.zero))
    }
}
