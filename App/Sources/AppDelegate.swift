import AppKit
import GlimpseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var hotkeys: HotkeyController?
    private var statusItem: StatusItemController?
    // Created in applicationDidFinishLaunching (main thread). A `lazy var` initializer would run in a
    // nonisolated context and fail to compile, because CaptureSessionController is @MainActor.
    private var session: CaptureSessionController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        InterfaceAccent.current = settings.accentColor
        let ocr = OCRController()
        let pins = PinWindowController(settings: settings)
        let session = CaptureSessionController(settings: settings, ocr: ocr, pins: pins)
        self.session = session
        let statusItem = StatusItemController(onCapture: { [weak self] in self?.startCapture() },
                                              onRecognizeText: { [weak self] in self?.startRecognizingText() },
                                              onSettings: { [weak self] in self?.showSettings() },
                                              onCloseAllPins: { [weak pins] in pins?.closeAll() })
        self.statusItem = statusItem
        // The menu bar icon's scenes (design doc §3.7); the permission mark is refreshed below.
        ocr.onRecognizingChange = { [weak statusItem] in statusItem?.setRecognizing($0) }
        pins.onCountChange = { [weak statusItem] in statusItem?.setPinCount($0) }
        session.onSuccess = { [weak statusItem] in statusItem?.flashDone() }

        let hotkeys = HotkeyController(settings: settings, handlers: [
            .screenshot: { [weak self] in
                self?.statusItem?.performAfterMenuCloses { [weak self] in self?.startCapture() }
            },
            .ocr: { [weak self] in
                self?.statusItem?.performAfterMenuCloses { [weak self] in self?.startRecognizingText() }
            },
        ])
        hotkeys.onChange = { [weak self, weak hotkeys] in
            guard let hotkeys else { return }
            for action in HotkeyAction.allCases {
                self?.statusItem?.updateShortcut(hotkeys.activeCombo(for: action), for: action)
            }
        }
        hotkeys.onSuspendedChange = { [weak statusItem] in statusItem?.setRecordingHotkey($0) }
        self.hotkeys = hotkeys
        hotkeys.registerAll()
        settingsWindow = SettingsWindowController(model: SettingsModel(settings: settings, hotkeys: hotkeys))

        let onboarding = OnboardingWindowController(settings: settings)
        onboarding.onGranted = { [weak self] in self?.refreshPermissionMark() }
        self.onboarding = onboarding
        session.onPermissionMissing = { [weak self] problem in self?.showOnboarding(problem) }
        session.onCaptureWillStart = { [weak onboarding] in onboarding?.hideForCapture() ?? false }
        session.onCaptureSucceeded = { [weak self] in self?.refreshPermissionMark() }
        session.onCaptureFinished = { [weak self] succeeded in self?.onboarding?.captureFinished(succeeded: succeeded) }
        // The permission can be granted or revoked in System Settings at any time; check on the way back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionMark() }
        }
        refreshPermissionMark()
        if !PermissionService.isGranted { onboarding.show(reason: .missing) } // first launch, or still not granted (§3.8)
    }

    // CaptureSessionController is @MainActor. applicationDidFinishLaunching gets main-actor isolation from
    // the NSApplicationDelegate requirement; these private helpers do not, so they are annotated here.
    // Class-level @MainActor would break the nonisolated top-level code in main.swift.
    @MainActor
    private func startCapture() {
        session?.start()
    }

    @MainActor
    private func startRecognizingText() {
        session?.start(recognizingText: true)
    }

    @MainActor
    private func showSettings() {
        settingsWindow?.show()
    }

    @MainActor
    private func showOnboarding(_ problem: PermissionService.Problem) {
        refreshPermissionMark()
        onboarding?.show(reason: problem)
    }

    /// Missing, or refused by ScreenCaptureKit since the last capture that worked (design doc §6).
    @MainActor
    private func refreshPermissionMark() {
        statusItem?.setNeedsPermission(!PermissionService.isGranted || PermissionService.captureRefused)
    }
}
