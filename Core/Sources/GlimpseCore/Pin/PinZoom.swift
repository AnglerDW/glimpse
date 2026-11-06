import CoreGraphics
import Foundation

/// Scroll-wheel and pinch zoom for pinned images (design doc §3.6). Zoom 1 is the capture's own size in points.
public enum PinZoom {
    /// Never past 500%.
    public static let maximumZoom: CGFloat = 5
    /// Nor past this many points on the longer side: a big capture at 500% would be a window larger than
    /// any screen and a huge backing store.
    public static let maximumSide: CGFloat = 10_000

    /// No smaller than 10%, and the shorter side no smaller than 24pt, unless the image is smaller to start with.
    public static func minimum(imageSize: CGSize) -> CGFloat {
        let shorter = min(imageSize.width, imageSize.height)
        guard shorter > 0 else { return 1 }
        return min(1, max(0.1, 24 / shorter))
    }

    /// 500%, or less when the longer side would pass `maximumSide`; never below the minimum.
    public static func maximum(imageSize: CGSize) -> CGFloat {
        let longer = max(imageSize.width, imageSize.height)
        guard longer > 0 else { return maximumZoom }
        return max(minimum(imageSize: imageSize), min(maximumZoom, maximumSide / longer))
    }

    /// The zoom after one scroll event. `delta` is positive for "zoom in" (wheel away from the user);
    /// precise (trackpad) deltas are in points and much finer than a wheel's lines.
    public static func zoom(_ current: CGFloat, scrolledBy delta: CGFloat, precise: Bool, imageSize: CGSize) -> CGFloat {
        settle(current, current * exp(delta * (precise ? 0.01 : 0.1)), imageSize: imageSize)
    }

    /// The zoom after one trackpad pinch event (`NSEvent.magnification`: 0.1 is 10% larger).
    public static func zoom(_ current: CGFloat, magnifiedBy magnification: CGFloat, imageSize: CGSize) -> CGFloat {
        settle(current, current * max(0.01, 1 + magnification), imageSize: imageSize)
    }

    /// Within this much of 100%, a zoom heading towards it stops there.
    static let actualSizeSnap: CGFloat = 0.03

    /// 100% is where the image is sharp, so a zoom that crosses it, or comes within `actualSizeSnap` of it
    /// on the way there, stops at exactly 1. Leaving 100% is never held back, however fine the steps.
    private static func settle(_ current: CGFloat, _ next: CGFloat, imageSize: CGSize) -> CGFloat {
        let crossed = (current < 1 && next > 1) || (current > 1 && next < 1)
        let arriving = abs(next - 1) < abs(current - 1) && abs(next - 1) <= actualSizeSnap
        let settled = crossed || arriving ? 1 : next
        return min(max(settled, minimum(imageSize: imageSize)), maximum(imageSize: imageSize))
    }

    /// The window frame at `zoom`, scaled about `anchor` (the mouse, in the same coordinates as `frame`), so
    /// the pixel under the mouse stays under it. On the screen's pixel grid (`backingScale` pixels per point);
    /// at exactly 100% the size is the image's own, so every image pixel lands on one screen pixel.
    public static func frame(_ frame: CGRect, zoomedTo zoom: CGFloat, imageSize: CGSize, anchor: CGPoint,
                             backingScale: CGFloat) -> CGRect {
        let scale = max(1, backingScale)
        func onGrid(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let size = zoom == 1 ? imageSize
            : CGSize(width: max(1 / scale, onGrid(imageSize.width * zoom)),
                     height: max(1 / scale, onGrid(imageSize.height * zoom)))
        let fx = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let fy = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        return CGRect(x: onGrid(anchor.x - fx * size.width), y: onGrid(anchor.y - fy * size.height),
                      width: size.width, height: size.height)
    }
}
