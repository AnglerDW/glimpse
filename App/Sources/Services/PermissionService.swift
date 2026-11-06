import AppKit
import ScreenCaptureKit

/// Screen Recording permission (design doc §3.8, §5.1): check it, ask for it, and restart Glimpse,
/// which macOS often needs before a fresh grant takes effect.
enum PermissionService {
    /// Why the onboarding window opens.
    enum Problem {
        /// The preflight says the permission is missing (never granted, or revoked).
        case missing
        /// The preflight says granted, but ScreenCaptureKit refused the capture (design doc §6).
        case captureRefused
    }

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// ScreenCaptureKit refused the last capture although `isGranted` said yes (design doc §6). Set when it
    /// refuses, cleared by the next capture that works; the menu bar icon keeps its mark meanwhile.
    @MainActor static var captureRefused = false

    /// 「去授权」: asks the system, which puts Glimpse in the Screen Recording list (an app that never asked
    /// is missing there, and the user would have to add it with 「+」). The first time for this app identity
    /// the system shows its own prompt, which has its own 「打开系统设置」 button; after that nothing visible
    /// happens, which is why the window offers 「打开系统设置…」 as well. Nothing is remembered here: a
    /// "did we ask before" flag cannot tell whether the system will prompt again (it prompts once per code
    /// signature, so every rebuild of an ad-hoc signed app starts over), and guessing wrong stacked the
    /// prompt and System Settings on top of each other (device feedback).
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// ScreenCaptureKit refused because the permission is missing (revoked, or denied when macOS 15+
    /// asked again), even though the preflight said yes.
    static func isPermissionDenial(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    /// Starts a new instance once this one has exited, then quits (design doc §3.8 step 3). A shell waits
    /// for this process to exit, so the new instance can register the same global shortcut (held until then),
    /// plus a moment for the system to finish tearing it down (status item, hotkey). If this process is still
    /// there after 10 seconds (the quit was cancelled), the shell gives up instead of opening a second instance.
    /// Returns false when the shell could not be started; Glimpse then keeps running.
    @MainActor
    static func relaunch() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // $0 is the app, $1 this process: wait up to 10 s (100 × 0.1 s) for it to exit, then open the app again.
        let script = "i=0; while /bin/kill -0 \"$1\" 2>/dev/null; do i=$((i + 1)); "
            + "[ \"$i\" -gt 100 ] && exit 1; /bin/sleep 0.1; done; /bin/sleep 0.3; /usr/bin/open \"$0\""
        process.arguments = ["-c", script, Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try process.run()
        } catch {
            Log.app.error("could not restart: \(error.localizedDescription, privacy: .public)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
