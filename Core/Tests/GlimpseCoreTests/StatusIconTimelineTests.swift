import Testing
@testable import GlimpseCore

struct StatusIconTimelineTests {
    private typealias Timeline = StatusIconTimeline

    @Test func stillScenesHaveOneFrameAndNoTimer() {
        for step in [0, 1, 100] {
            let idle = Timeline.frame(for: .idle, step: step, reduceMotion: false)
            #expect(idle.frame == .idle && !idle.continues)
            let permission = Timeline.frame(for: .needsPermission, step: step, reduceMotion: false)
            #expect(permission.frame == .needsPermission && !permission.continues)
        }
    }

    @Test func doneRunsItsStepsThenHoldsTheCheck() {
        for step in 0..<Timeline.doneLastStep {
            let result = Timeline.frame(for: .done, step: step, reduceMotion: false)
            #expect(result.frame == .done(step: step))
            #expect(result.continues)
        }
        let last = Timeline.frame(for: .done, step: Timeline.doneLastStep, reduceMotion: false)
        #expect(last.frame == .done(step: 3))
        #expect(!last.continues)
        // Past the end the step is clamped: the same still ✓, still no timer.
        let beyond = Timeline.frame(for: .done, step: 50, reduceMotion: false)
        #expect(beyond.frame == .done(step: Timeline.doneLastStep))
        #expect(!beyond.continues)
    }

    @Test func doneDurationIsTightenPlusHold() {
        #expect(Timeline.doneDuration == 1.1)
        #expect(Timeline.doneTightenDuration == 0.3)
        #expect(Timeline.doneHoldDuration == 0.8)
    }

    @Test func pinnedPopsThenHoldsTheDot() {
        for step in 0..<Timeline.pinnedLastStep {
            let result = Timeline.frame(for: .pinned, step: step, reduceMotion: false)
            #expect(result.frame == .pinned(step: step))
            #expect(result.continues)
        }
        let last = Timeline.frame(for: .pinned, step: Timeline.pinnedLastStep, reduceMotion: false)
        #expect(last.frame == .pinned(step: 4))
        #expect(!last.continues)
        let beyond = Timeline.frame(for: .pinned, step: 9, reduceMotion: false)
        #expect(beyond.frame == .pinned(step: Timeline.pinnedLastStep))
        #expect(!beyond.continues)
    }

    @Test func loopingScenesWrapTheirStep() {
        #expect(Timeline.recognizingCycle == 19)
        #expect(Timeline.recordingCycle == 22)
        let recognizing = Timeline.frame(for: .recognizing, step: 19, reduceMotion: false)
        #expect(recognizing.frame == .recognizing(step: 0))
        #expect(recognizing.continues)
        #expect(Timeline.frame(for: .recognizing, step: 40, reduceMotion: false).frame == .recognizing(step: 2))
        let recording = Timeline.frame(for: .recordingHotkey, step: 22, reduceMotion: false)
        #expect(recording.frame == .recordingHotkey(step: 0))
        #expect(recording.continues)
        #expect(Timeline.frame(for: .recordingHotkey, step: 45, reduceMotion: false).frame == .recordingHotkey(step: 1))
        // They keep going at every step.
        for step in 0..<50 {
            #expect(Timeline.frame(for: .recognizing, step: step, reduceMotion: false).continues)
            #expect(Timeline.frame(for: .recordingHotkey, step: step, reduceMotion: false).continues)
        }
    }

    @Test func reduceMotionMakesEverySceneOneStillFrame() {
        let expected: [(StatusIconState, StatusIconFrame)] = [
            (.idle, .idle),
            (.needsPermission, .needsPermission),
            (.done, .done(step: Timeline.doneLastStep)),
            (.recognizing, .recognizingStill),
            (.recordingHotkey, .recordingHotkeyStill),
            (.pinned, .pinned(step: Timeline.pinnedLastStep)),
        ]
        for (state, frame) in expected {
            for step in [0, 1, 7, 100] {
                let result = Timeline.frame(for: state, step: step, reduceMotion: true)
                #expect(result.frame == frame, "\(state) at step \(step)")
                #expect(!result.continues, "\(state) at step \(step)")
            }
        }
    }

    @Test func onlyRecognizingAndRecordingLoop() {
        #expect(Timeline.loops(.recognizing))
        #expect(Timeline.loops(.recordingHotkey))
        for state: StatusIconState in [.idle, .done, .pinned, .needsPermission] {
            #expect(!Timeline.loops(state))
        }
    }
}
