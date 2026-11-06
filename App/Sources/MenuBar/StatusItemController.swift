import AppKit
import GlimpseCore

/// The menu bar icon and its menu (design doc §3.7): 截图, 提取文字, 关闭所有贴图 (N) while pins are up, 设置…, 退出.
/// The icon shows one of six scenes (`StatusIconState`), picked by priority from what the app reports here.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Time for the menu to finish fading out so it doesn't end up in the screenshot.
    private static let menuFadeDelay: TimeInterval = 0.25

    private let item: NSStatusItem
    private let menu = NSMenu()
    /// The items that start a global-shortcut action; they show the shortcut while it works.
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    /// 「关闭所有贴图 (N)」: hidden while there is no pin.
    private let closePinsItem: NSMenuItem
    private let onCapture: () -> Void
    private let onRecognizeText: () -> Void
    private let onSettings: () -> Void
    private let onCloseAllPins: () -> Void
    private var isMenuOpen = false

    private var inputs = StatusIconInputs()
    private let animator: StatusIconAnimator
    /// Ends the ✓ flash after its duration; a newer success replaces it.
    private var doneFlashTask: Task<Void, Never>?

    init(onCapture: @escaping () -> Void, onRecognizeText: @escaping () -> Void, onSettings: @escaping () -> Void,
         onCloseAllPins: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onRecognizeText = onRecognizeText
        self.onSettings = onSettings
        self.onCloseAllPins = onCloseAllPins
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        animator = StatusIconAnimator(button: item.button) // shows the idle icon at once
        closePinsItem = NSMenuItem(title: "", action: #selector(closePinsClicked), keyEquivalent: "")
        super.init()

        let captureItem = NSMenuItem(title: String(localized: "menu.takeScreenshot", defaultValue: "截图", comment: "Menu bar item: take a screenshot (source text 截图)"), action: #selector(captureClicked), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        actionItems[.screenshot] = captureItem
        let ocrItem = NSMenuItem(title: String(localized: "提取文字", comment: "Shortcut row / menu item / toolbar button / panel title: extract text (OCR)"), action: #selector(recognizeTextClicked), keyEquivalent: "")
        ocrItem.target = self
        menu.addItem(ocrItem)
        actionItems[.ocr] = ocrItem
        closePinsItem.target = self
        closePinsItem.isHidden = true
        menu.addItem(closePinsItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: String(localized: "设置…", comment: "Menu item: open settings"), action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "退出 Glimpse", comment: "Menu item: quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    deinit {
        doneFlashTask?.cancel()
    }

    /// Shows `combo` next to the item for `action`; clears it when nil or not representable in a menu.
    func updateShortcut(_ combo: KeyCombo?, for action: HotkeyAction) {
        guard let menuItem = actionItems[action] else { return }
        if let combo, let key = combo.menuKeyEquivalent {
            menuItem.keyEquivalent = key
            menuItem.keyEquivalentModifierMask = combo.menuModifierMask
        } else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }

    // MARK: - Icon scenes (design doc §3.7)

    /// The Screen Recording permission is missing, or the last capture was refused (design doc §6). Checked
    /// on every activation; nothing changes when the value is the same.
    func setNeedsPermission(_ needed: Bool) {
        update { $0.needsPermission = needed }
    }

    /// 提取文字 is running (true) or over, cancelled or its panel closed (false).
    func setRecognizing(_ recognizing: Bool) {
        update { $0.isRecognizing = recognizing }
    }

    /// The settings page records a shortcut (the global shortcuts are suspended meanwhile).
    func setRecordingHotkey(_ recording: Bool) {
        update { $0.isRecordingHotkey = recording }
    }

    /// How many pins are on screen; also shows or hides 「关闭所有贴图 (N)」.
    func setPinCount(_ count: Int) {
        closePinsItem.title = String(localized: "关闭所有贴图 (\(count))", comment: "Menu item; %lld is the number of pins")
        closePinsItem.isHidden = count < 1
        update { $0.pinCount = count }
    }

    /// A copy, save or pin just worked: the ✓ flash, restarted by a newer success. It lasts
    /// `StatusIconTimeline.doneDuration`, or only the hold with Reduce Motion (the ✓ appears at once). A scene
    /// with higher priority (missing permission) keeps showing instead.
    func flashDone() {
        doneFlashTask?.cancel()
        update(restart: true) { $0.isDoneFlashing = true }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? StatusIconTimeline.doneHoldDuration : StatusIconTimeline.doneDuration
        doneFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.doneFlashTask = nil
            self.update { $0.isDoneFlashing = false }
        }
    }

    /// Applies `change` and shows the resulting scene. Equal inputs change nothing unless `restart`, which
    /// replays the scene from its first frame. The pin dot pops only when the pin count goes from 0 to ≥ 1:
    /// coming back to the pinned scene from another one (the ✓ flash, a recognition) shows the dot settled.
    private func update(restart: Bool = false, _ change: (inout StatusIconInputs) -> Void) {
        let pinsWereUp = inputs.hasPins
        var changed = inputs
        change(&changed)
        guard restart || changed != inputs else { return }
        inputs = changed
        let state = StatusIconState.resolve(inputs)
        let step = state == .pinned && pinsWereUp ? StatusIconTimeline.pinnedLastStep : 0
        animator.show(state, from: step, restart: restart)
    }

    // MARK: - Menu

    /// Closes the status menu first if it is open, then runs `action` once it has faded out.
    func performAfterMenuCloses(_ action: @escaping () -> Void) {
        guard isMenuOpen else {
            action()
            return
        }
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { action() }
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    @objc private func captureClicked() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { [onCapture] in onCapture() }
    }

    @objc private func recognizeTextClicked() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuFadeDelay) { [onRecognizeText] in onRecognizeText() }
    }

    @objc private func settingsClicked() {
        onSettings()
    }

    @objc private func closePinsClicked() {
        onCloseAllPins()
    }
}
