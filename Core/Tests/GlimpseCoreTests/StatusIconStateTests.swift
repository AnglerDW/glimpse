import Testing
@testable import GlimpseCore

struct StatusIconStateTests {
    @Test func nothingSetIsIdle() {
        #expect(StatusIconState.resolve(StatusIconInputs()) == .idle)
    }

    @Test func eachInputAloneGivesItsScene() {
        #expect(StatusIconState.resolve(StatusIconInputs(needsPermission: true)) == .needsPermission)
        #expect(StatusIconState.resolve(StatusIconInputs(isDoneFlashing: true)) == .done)
        #expect(StatusIconState.resolve(StatusIconInputs(isRecognizing: true)) == .recognizing)
        #expect(StatusIconState.resolve(StatusIconInputs(isRecordingHotkey: true)) == .recordingHotkey)
        #expect(StatusIconState.resolve(StatusIconInputs(pinCount: 1)) == .pinned)
    }

    @Test func pinCountBelowOneIsIdle() {
        #expect(StatusIconState.resolve(StatusIconInputs(pinCount: 0)) == .idle)
        #expect(StatusIconState.resolve(StatusIconInputs(pinCount: -1)) == .idle)
        #expect(StatusIconState.resolve(StatusIconInputs(pinCount: 1)) == .pinned)
        #expect(StatusIconState.resolve(StatusIconInputs(pinCount: 7)) == .pinned)
        #expect(!StatusIconInputs(pinCount: 0).hasPins)
        #expect(StatusIconInputs(pinCount: 2).hasPins)
    }

    @Test func priorityIsPermissionDoneRecognizingRecordingPinned() {
        let all = StatusIconInputs(needsPermission: true, isDoneFlashing: true, isRecognizing: true,
                                   isRecordingHotkey: true, pinCount: 3)
        #expect(StatusIconState.resolve(all) == .needsPermission)
        var inputs = all
        inputs.needsPermission = false
        #expect(StatusIconState.resolve(inputs) == .done)
        inputs.isDoneFlashing = false
        #expect(StatusIconState.resolve(inputs) == .recognizing)
        inputs.isRecognizing = false
        #expect(StatusIconState.resolve(inputs) == .recordingHotkey)
        inputs.isRecordingHotkey = false
        #expect(StatusIconState.resolve(inputs) == .pinned)
        inputs.pinCount = 0
        #expect(StatusIconState.resolve(inputs) == .idle)
    }

    @Test func pinnedLosesToEveryOtherScene() {
        #expect(StatusIconState.resolve(StatusIconInputs(isRecordingHotkey: true, pinCount: 2)) == .recordingHotkey)
        #expect(StatusIconState.resolve(StatusIconInputs(isRecognizing: true, pinCount: 2)) == .recognizing)
        #expect(StatusIconState.resolve(StatusIconInputs(isDoneFlashing: true, pinCount: 2)) == .done)
        #expect(StatusIconState.resolve(StatusIconInputs(needsPermission: true, pinCount: 2)) == .needsPermission)
    }
}
