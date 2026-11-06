import Foundation

/// One picture of the menu bar icon (design doc §3.7): a scene, and for the animated scenes the step of
/// the animation. `StatusIconTimeline` picks the frame; the app's `StatusIcon` draws it.
public enum StatusIconFrame: Hashable, Sendable {
    case idle
    case needsPermission
    /// The ✓ flash: 0 ..< `StatusIconTimeline.doneLastStep` tighten the corners and draw the ✓; `doneLastStep`
    /// is the still ✓ that holds until the state ends.
    case done(step: Int)
    /// Scan line going down and back up; `step` cycles below `StatusIconTimeline.recognizingCycle`.
    case recognizing(step: Int)
    /// Reduce Motion: the three rows, no scan line.
    case recognizingStill
    /// One ripple leaving the centre; `step` cycles below `StatusIconTimeline.recordingCycle`.
    case recordingHotkey(step: Int)
    /// Reduce Motion: the centre dot inside one still ring.
    case recordingHotkeyStill
    /// The pin dot popping in: 0 ..< `StatusIconTimeline.pinnedLastStep` grow it; `pinnedLastStep` is the still dot.
    case pinned(step: Int)
}

/// The rhythm of the menu bar icon (design doc §3.7): which `StatusIconFrame` a scene shows at a given
/// step of its animation, and whether there is a next step. Steps are counted at `frameRate`.
public enum StatusIconTimeline {
    public static let frameRate: Double = 12
    /// The corners tighten and the ✓ is drawn.
    public static let doneTightenDuration: TimeInterval = 0.3
    /// The ✓ then stays; with Reduce Motion this is the whole flash.
    public static let doneHoldDuration: TimeInterval = 0.8
    public static let doneDuration: TimeInterval = doneTightenDuration + doneHoldDuration

    /// Steps 0 ... 3 run the ✓ flash; step 3 is the still ✓ (four steps ≈ 0.3 s at 12 fps).
    public static let doneLastStep = 3
    /// Steps 0 ... 4 pop the pin dot; step 4 is the still dot (five steps ≈ 0.4 s).
    public static let pinnedLastStep = 4
    /// 1.6 s per down-and-up scan at 12 fps.
    public static let recognizingCycle = 19
    /// 1.8 s per ripple at 12 fps.
    public static let recordingCycle = 22

    /// Scenes that keep animating for as long as they last.
    public static func loops(_ state: StatusIconState) -> Bool {
        switch state {
        case .recognizing, .recordingHotkey: true
        case .idle, .done, .pinned, .needsPermission: false
        }
    }

    /// The frame for `state` at `step`, and whether a later step shows something else (false: no timer is
    /// needed). With Reduce Motion every scene is a single still frame: the ✓ at once, the three text rows,
    /// the centre dot in one still ring, the pin dot already there.
    public static func frame(for state: StatusIconState, step: Int, reduceMotion: Bool) -> (frame: StatusIconFrame, continues: Bool) {
        switch state {
        case .idle:
            return (.idle, false)
        case .needsPermission:
            return (.needsPermission, false)
        case .done:
            if reduceMotion { return (.done(step: doneLastStep), false) }
            let clamped = min(step, doneLastStep)
            return (.done(step: clamped), clamped < doneLastStep)
        case .recognizing:
            if reduceMotion { return (.recognizingStill, false) }
            return (.recognizing(step: step % recognizingCycle), true)
        case .recordingHotkey:
            if reduceMotion { return (.recordingHotkeyStill, false) }
            return (.recordingHotkey(step: step % recordingCycle), true)
        case .pinned:
            if reduceMotion { return (.pinned(step: pinnedLastStep), false) }
            let clamped = min(step, pinnedLastStep)
            return (.pinned(step: clamped), clamped < pinnedLastStep)
        }
    }
}
