import AppKit
import GlimpseCore

/// Plays a `StatusIconState` on the menu bar button, following `StatusIconTimeline`: one timer at its frame
/// rate while the scene still has frames to show, none once it is still (idle, needsPermission, the held ✓,
/// the pin dot after its pop, and every scene with Reduce Motion), so a quiet icon costs nothing. Frames
/// come from `StatusIcon`'s cache; the button only gets a new image when the frame changes.
@MainActor
final class StatusIconAnimator {
    /// The button the frames go to.
    private weak var button: NSStatusBarButton?
    private(set) var state: StatusIconState = .idle
    private var step = 0
    private var timer: Timer?
    private var shown: StatusIconFrame?
    /// Repaints when Reduce Motion is switched, so a looping scene stops (or starts) at once.
    private var motionObserver: NSObjectProtocol?

    init(button: NSStatusBarButton?) {
        self.button = button
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.motionSettingChanged() }
        }
        render()
    }

    deinit {
        timer?.invalidate()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }

    /// Switches to `state`, starting at `step` (0: from its first frame; `StatusIconTimeline.pinnedLastStep`
    /// shows the pin dot already settled, for a return to the pinned scene whose pop already played). The
    /// same state again is left alone; `restart` replays it anyway (a second success during the ✓ flash
    /// starts the flash over).
    func show(_ state: StatusIconState, from step: Int = 0, restart: Bool = false) {
        guard restart || state != self.state else { return }
        self.state = state
        self.step = step
        render()
    }

    /// Reduce Motion changed: a looping scene starts its loop over (or stops); a scene coming back from its
    /// still frame restarts from the top; a finished pop or ✓ is not replayed when motion is reduced.
    private func motionSettingChanged() {
        if StatusIconTimeline.loops(state) || !Self.reduceMotion { step = 0 }
        render()
    }

    private func render() {
        let (frame, continues) = StatusIconTimeline.frame(for: state, step: step, reduceMotion: Self.reduceMotion)
        if frame != shown {
            shown = frame
            button?.image = StatusIcon.image(for: frame)
        }
        continues ? startTimer() : stopTimer()
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func startTimer() {
        guard timer == nil else { return }
        let interval = 1 / StatusIconTimeline.frameRate
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.step += 1
                self.render()
            }
        }
        timer.tolerance = interval * 0.1 // lets the system coalesce wake-ups; a frame a little late is invisible
        // .common: keeps ticking while the status menu is open (menu tracking leaves the default mode).
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
