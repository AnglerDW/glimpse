import AppKit
import GlimpseCore

/// The global shortcuts (design doc §3.1): registers what `SettingsStore` holds, applies changes from
/// the settings page, and remembers which stored shortcut failed to register so the page can show it red.
/// A shortcut that fails to register stays stored, so it is tried again on the next launch.
@MainActor
final class HotkeyController {
    private let settings: SettingsStore
    private let service = HotkeyService()
    private let handlers: [HotkeyAction: () -> Void]
    /// Stored shortcuts that are not registered right now (taken by another program).
    private(set) var failures: Set<HotkeyAction> = []
    /// What is registered changed: the status menu shows the working shortcuts.
    var onChange: (() -> Void)?
    /// The shortcuts were suspended for recording (true) or put back (false); the menu bar icon shows the
    /// recording (design doc §3.7).
    var onSuspendedChange: ((Bool) -> Void)?
    /// True between `suspend()` and the next `registerAll()`.
    private(set) var isSuspended = false {
        didSet { if isSuspended != oldValue { onSuspendedChange?(isSuspended) } }
    }

    init(settings: SettingsStore, handlers: [HotkeyAction: () -> Void]) {
        self.settings = settings
        self.handlers = handlers
    }

    /// The stored shortcut, working or not; nil when cleared (or never set).
    func combo(for action: HotkeyAction) -> KeyCombo? {
        switch action {
        case .screenshot: settings.screenshotHotkey
        case .ocr: settings.ocrHotkey
        }
    }

    /// The stored shortcut if it is registered; what the menu shows.
    func activeCombo(for action: HotkeyAction) -> KeyCombo? {
        failures.contains(action) ? nil : combo(for: action)
    }

    /// Registers every stored shortcut (launch, and after recording).
    func registerAll() {
        isSuspended = false
        for action in HotkeyAction.allCases {
            if let combo = combo(for: action) {
                let result = register(combo, for: action)
                if result == .registered {
                    failures.remove(action)
                } else {
                    failures.insert(action)
                    Log.app.error("failed to register \(String(describing: action), privacy: .public) hotkey: \(String(describing: result), privacy: .public)")
                }
            } else {
                service.unregister(action)
                failures.remove(action)
            }
        }
        onChange?()
    }

    /// Takes every shortcut off while the settings page records one: Carbon would otherwise grab the
    /// current shortcut before the recorder sees it. `registerAll()` puts them back.
    func suspend() {
        HotkeyAction.allCases.forEach(service.unregister)
        isSuspended = true
    }

    /// Applies a shortcut from the settings page. A new combo is stored only once it registers; on failure
    /// the previous one stays in place and the result says why. Clearing always succeeds.
    @discardableResult
    func set(_ combo: KeyCombo?, for action: HotkeyAction) -> HotkeyRegistrationResult {
        guard let combo else {
            service.unregister(action)
            store(nil, for: action)
            failures.remove(action)
            onChange?()
            return .registered
        }
        let result = register(combo, for: action)
        if result == .registered {
            store(combo, for: action)
            failures.remove(action)
            onChange?()
        }
        return result
    }

    private func register(_ combo: KeyCombo, for action: HotkeyAction) -> HotkeyRegistrationResult {
        service.register(combo, for: action, handler: handlers[action] ?? {})
    }

    private func store(_ combo: KeyCombo?, for action: HotkeyAction) {
        switch action {
        case .screenshot: settings.screenshotHotkey = combo
        case .ocr: settings.ocrHotkey = combo
        }
    }
}
