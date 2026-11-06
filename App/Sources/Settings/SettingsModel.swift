import AppKit
import GlimpseCore
import Observation

/// What the settings page shows and changes (design doc §3.9). Every change applies at once and is
/// stored in `SettingsStore`; launch at login lives in the system (`LoginItemService`).
@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let hotkeys: HotkeyController
    /// The settings window: the folder picker opens as a sheet on it.
    @ObservationIgnored weak var sheetParent: NSWindow?

    private(set) var screenshotHotkey: KeyCombo?
    private(set) var ocrHotkey: KeyCombo?
    /// The red line under a shortcut: a failed registration or a rejected key. Nil when it works.
    private(set) var hotkeyErrors: [HotkeyAction: String] = [:]
    private(set) var accent: AccentColor
    private(set) var saveDirectory: URL
    /// 「语言」: Glimpse's own record (SettingsStore), never read back from AppleLanguages.
    private(set) var interfaceLanguage: InterfaceLanguage
    /// The choice this process launched with: a different choice needs a relaunch to show.
    @ObservationIgnored private let languageAtLaunch: InterfaceLanguage
    var needsRelaunchForLanguage: Bool { interfaceLanguage != languageAtLaunch }
    /// `relaunch()` could not start the restart; shown in red under the language row.
    private(set) var relaunchFailed = false
    /// 「开机自动启动」: the switch, and the red line under it when it failed.
    private(set) var loginItem = LoginItemService.Display()
    var launchAtLogin: Bool { loginItem.isOn }
    var loginItemError: String? { loginItem.error }
    /// The error is fixed in System Settings → Login Items; the page offers a button for it.
    var loginItemNeedsApproval: Bool { loginItem.needsApproval }

    init(settings: SettingsStore, hotkeys: HotkeyController) {
        self.settings = settings
        self.hotkeys = hotkeys
        accent = settings.accentColor
        saveDirectory = settings.saveDirectory
        let language = settings.interfaceLanguage
        interfaceLanguage = language
        languageAtLaunch = language
        reload()
    }

    /// Reads everything again when the window opens.
    func reload() {
        reloadHotkeys()
        saveDirectory = settings.saveDirectory
        reloadLoginItem()
    }

    /// The stored shortcuts, and a red line for each one that is not registered.
    private func reloadHotkeys() {
        screenshotHotkey = hotkeys.combo(for: .screenshot)
        ocrHotkey = hotkeys.combo(for: .ocr)
        hotkeyErrors = [:]
        for action in hotkeys.failures {
            if let combo = hotkeys.combo(for: action) { hotkeyErrors[action] = Self.unavailableMessage(combo) }
        }
    }

    /// The system's login item state, also when Glimpse comes back from System Settings.
    func reloadLoginItem() {
        loginItem.reload()
    }

    // MARK: - Shortcuts

    func combo(for action: HotkeyAction) -> KeyCombo? {
        action == .screenshot ? screenshotHotkey : ocrHotkey
    }

    func recordingChanged(_ recording: Bool, for action: HotkeyAction) {
        if recording {
            hotkeyErrors[action] = nil
            hotkeys.suspend()
        } else {
            // Ended without a key too (a click elsewhere): a shortcut that still fails gets its red line back.
            hotkeys.registerAll()
            reloadHotkeys()
        }
    }

    func apply(_ outcome: HotkeyRecording.Outcome, for action: HotkeyAction) {
        switch outcome {
        case .cancel:
            reloadHotkeys()
        case .clear:
            hotkeys.set(nil, for: action)
            reloadHotkeys()
        case .record(let combo):
            let result = hotkeys.set(combo, for: action)
            reloadHotkeys()
            if result != .registered { hotkeyErrors[action] = Self.failureMessage(combo, result) }
        case .reject(let rejection):
            reloadHotkeys()
            hotkeyErrors[action] = rejection.message
        }
    }

    private static func unavailableMessage(_ combo: KeyCombo) -> String {
        String(localized: "「\(combo.displayString)」没有注册成功，现在不可用，请换一个",
               comment: "Shortcut error at launch; %@ is the shortcut")
    }

    private static func failureMessage(_ combo: KeyCombo, _ result: HotkeyRegistrationResult) -> String {
        switch result {
        case .conflict:
            String(localized: "「\(combo.displayString)」已被其他 App 占用，请换一个", comment: "Shortcut error; %@ is the shortcut")
        case .failed(let status):
            String(localized: "「\(combo.displayString)」注册失败（\(status)），请换一个",
                   comment: "Shortcut error; %@ is the shortcut, %d the OSStatus")
        case .registered: ""
        }
    }

    // MARK: - Accent

    func setAccent(_ accent: AccentColor) {
        self.accent = accent
        settings.accentColor = accent
        InterfaceAccent.current = accent
    }

    // MARK: - Save folder

    /// The folder's name as Finder shows it (「下载」).
    var saveDirectoryName: String { FileManager.default.displayName(atPath: saveDirectory.path) }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        panel.prompt = String(localized: "选择", comment: "Open panel: confirm button")
        panel.message = String(localized: "选择截图的保存位置", comment: "Open panel: message")
        guard let window = sheetParent else {
            if panel.runModal() == .OK, let url = panel.url { useSaveDirectory(url) }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useSaveDirectory(url) }
        }
    }

    private func useSaveDirectory(_ url: URL) {
        settings.saveDirectory = url
        saveDirectory = settings.saveDirectory
    }

    // MARK: - Interface language

    /// Stores the choice and mirrors it into `AppleLanguages` in the app's own defaults, which is what macOS
    /// reads at the next launch (design doc §3.9); 「跟随系统」 removes the override instead of writing one.
    func setInterfaceLanguage(_ language: InterfaceLanguage) {
        interfaceLanguage = language
        settings.interfaceLanguage = language
        relaunchFailed = false
        if let value = language.appleLanguagesValue {
            UserDefaults.standard.set(value, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// 「重新启动 Glimpse」: the same restart as the onboarding window's.
    func relaunch() {
        relaunchFailed = !PermissionService.relaunch()
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemService.recordChoice(settings: settings) // the onboarding window no longer recommends
        loginItem.follow(enabled)
        loginItem.set(enabled) // a failure puts the switch back (design doc §6)
    }

    // MARK: - About

    /// The About row's text, 「版本 0.1.0（Build 1）」: CFBundleShortVersionString and CFBundleVersion.
    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "版本 \(short)（Build \(build)）",
                      comment: "About: version line; %@ are CFBundleShortVersionString and CFBundleVersion")
    }

    /// NSHumanReadableCopyright (「© 2026 AnglerDW」); nil when the bundle has none.
    var copyright: String? {
        (Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
