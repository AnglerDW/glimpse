import Testing
@testable import GlimpseCore

struct PermissionFlowTests {
    @Test func startsAskingForTheGrant() {
        #expect(PermissionFlow().step == .needsGrant)
    }

    @Test func aGrantSeenByThePollClosesTheWindow() {
        var flow = PermissionFlow()
        flow.poll(granted: false)
        #expect(flow.step == .needsGrant)
        flow.poll(granted: true)
        #expect(flow.step == .granted)
    }

    @Test func backFromSystemSettingsWithoutTheGrantOffersARestart() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: true)
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsRestart)
        flow.poll(granted: false) // the poll keeps the restart button
        #expect(flow.step == .needsRestart)
    }

    @Test func theFirstSystemPromptOnlyGetsTheQuietHint() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: false) // only the system's prompt appeared
        #expect(flow.step == .restartHint)
        flow.appDidBecomeActive(granted: false) // declined, or opened System Settings from the prompt
        #expect(flow.step == .restartHint)
        flow.didRequest(openedSystemSettings: true) // the second click opens System Settings
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsRestart)
    }

    @Test func becomingActiveBeforeAskingChangesNothing() {
        var flow = PermissionFlow()
        flow.appDidBecomeActive(granted: false)
        #expect(flow.step == .needsGrant)
    }

    @Test func backFromSystemSettingsWithTheGrantCloses() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: true)
        flow.appDidBecomeActive(granted: true)
        #expect(flow.step == .granted)
    }

    @Test func aRefusedCaptureOffersARestartThatTheGrantDoesNotClose() {
        var flow = PermissionFlow()
        flow.captureWasRefused() // the preflight says granted, ScreenCaptureKit still says no
        #expect(flow.step == .needsRestart)
        #expect(flow.isCaptureRefused)
        flow.poll(granted: true)
        #expect(flow.step == .needsRestart)
        flow.appDidBecomeActive(granted: true)
        #expect(flow.step == .needsRestart)
    }

    @Test func aRefusedCaptureReplacesTheQuietHint() {
        var flow = PermissionFlow()
        flow.didRequest(openedSystemSettings: false)
        flow.captureWasRefused()
        #expect(flow.step == .needsRestart)
        flow.didRequest(openedSystemSettings: false) // 「去授权」 again does not bring the quiet hint back
        #expect(flow.step == .needsRestart)
    }
}
