import AppKit
import GlimpseCore
import SwiftUI

/// The first-launch window (design doc §3.8): asks for Screen Recording, offers a restart when the grant
/// has not taken effect, and holds the 「开机自动启动」 switch. Shown at launch and whenever a capture
/// finds the permission missing; closes itself once the permission is there. When ScreenCaptureKit refused
/// a capture although the permission looks granted, it offers the restart and stays until the user closes it.
@MainActor
final class OnboardingWindowController {
    /// The permission arrived: the status item drops its warning mark.
    var onGranted: (() -> Void)?

    private let settings: SettingsStore
    private var window: OnboardingWindow?
    private var content: OnboardingView?
    private var flow = PermissionFlow()
    /// What the restart row shows now; render() only touches the view when this changes.
    private var renderedOffer: OnboardingView.RestartOffer?
    private var loginItem = LoginItemService.Display()
    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// Ordered out so a capture does not freeze it into the screenshot; see `captureFinished(succeeded:)`.
    private var isHiddenForCapture = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(reason: PermissionService.Problem) {
        switch reason {
        case .missing:
            // Kept while Glimpse runs, so closing the window does not forget that 「去授权」 was clicked;
            // started over once a grant was seen (it may have been revoked since), and when the preflight now
            // plainly says missing after a refused capture.
            if flow.step == .granted || flow.isCaptureRefused { flow = PermissionFlow() }
        case .captureRefused:
            flow.captureWasRefused()
        }
        isHiddenForCapture = false
        let isNew = window == nil
        if isNew {
            let view = OnboardingView(shortcut: settings.screenshotHotkey)
            view.onRequest = { [weak self] in self?.request() }
            view.onRestart = { [weak self] in self?.restart() }
            view.onClose = { [weak self] in self?.close() }
            view.onLaunchAtLoginChange = { [weak self] enabled in
                guard let self else { return }
                LoginItemService.recordChoice(settings: self.settings) // the user's flip wins over the recommendation
                self.loginItem.set(enabled)
                self.showLoginItem()
            }
            view.onOpenLoginItems = { LoginItemService.openSystemSettings() }
            content = view
            window = OnboardingWindow(content: view)
            startWatching()
        }
        loginItem.reload()
        showLoginItem()
        render(force: true)
        guard let window else { return }
        if isNew { window.center() } // a window the user moved stays where it is
        DockPresence.bringToFront(window)
    }

    /// A capture is about to start (e.g. a retry after a refused capture): the window steps aside.
    /// Returns whether it was on screen.
    func hideForCapture() -> Bool {
        guard let window, window.isVisible else { return false }
        window.orderOut(nil)
        isHiddenForCapture = true
        return true
    }

    /// The capture the window stepped aside for is over. It worked (called once its overlay is gone, so
    /// handing the keyboard back cannot take it from the overlay): the permission is there, so the window
    /// closes for good. It failed for another reason: the window comes back. (Refused again: the
    /// session calls `show(reason: .captureRefused)` instead.)
    func captureFinished(succeeded: Bool) {
        guard isHiddenForCapture, let window else { return }
        isHiddenForCapture = false
        if succeeded {
            flow = PermissionFlow()
            close()
            onGranted?()
        } else {
            DockPresence.bringToFront(window)
        }
    }

    private func request() {
        applyLoginItemRecommendation()
        flow.didRequest(openedSystemSettings: PermissionService.request())
        render()
    }

    /// 「去授权」 with the recommendation still showing (design doc §3.8): the switch shows on and the user has
    /// not flipped it, so launch at login is registered now, once, with this click; never silently at launch.
    /// A failure shows under the switch, as after a flip (design doc §6).
    private func applyLoginItemRecommendation() {
        guard LoginItemService.isRecommendationPending(settings: settings) else { return }
        LoginItemService.recordChoice(settings: settings)
        loginItem.set(true)
        showLoginItem()
    }

    private func restart() {
        guard !PermissionService.relaunch() else { return }
        NSSound.beep()
        content?.showRestartFailed()
        window?.fitContent()
    }

    /// The switch shows the recommendation (on) until the user has chosen, then the system's state.
    private func showLoginItem() {
        content?.showLoginItem(loginItem, recommended: LoginItemService.isRecommendationPending(settings: settings))
        window?.fitContent()
    }

    /// Polls once a second while open, and checks again whenever Glimpse becomes active (back from System
    /// Settings, where the login item may have changed too).
    private func startWatching() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.flow.poll(granted: PermissionService.isGranted)
                self.render()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loginItem.reload()
                self.showLoginItem()
                self.flow.appDidBecomeActive(granted: PermissionService.isGranted)
                self.render()
            }
        }
    }

    /// Shows the flow's step. Only when it changed (the poll runs every second), or when `force`d.
    private func render(force: Bool = false) {
        let offer: OnboardingView.RestartOffer?
        switch flow.step {
        case .needsGrant: offer = nil
        case .restartHint: offer = .quiet
        case .needsRestart: offer = flow.isCaptureRefused ? .captureRefused : .prominent
        case .granted:
            close()
            onGranted?()
            return
        }
        guard force || offer != renderedOffer else { return }
        renderedOffer = offer
        content?.showRestart(offer)
        window?.fitContent()
    }

    private func close() {
        isHiddenForCapture = false
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let window {
            window.orderOut(nil)
            DockPresence.remove(window)
        }
        window = nil
        content = nil
    }
}

/// Borderless and transparent, so the glass is the window; dragged by its background.
private final class OnboardingWindow: NSWindow {
    private let material = MaterialView(cornerRadius: 12, blendsBehindWindow: true)
    private let content: OnboardingView

    init(content: OnboardingView) {
        self.content = content
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        material.contentView.addSubview(content)
        contentView = material
        fitContent()
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes, like the ✕.
    override func cancelOperation(_ sender: Any?) {
        content.onClose?()
    }

    /// Sizes the window to the content (the restart row comes and goes), keeping the top edge in place.
    func fitContent() {
        let size = content.fittingSize
        let top = frame.maxY
        content.frame = CGRect(origin: .zero, size: size)
        material.frame = CGRect(origin: .zero, size: size)
        let origin = frame.isEmpty ? frame.origin : CGPoint(x: frame.minX, y: top - size.height)
        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

/// The window's content, top to bottom: ✕, icon, title, explanation, 「去授权」, the restart row (when
/// needed), the shortcut hint, 「开机自动启动」 and its error row. The icon, 「去授权」 and the switch use the
/// interface accent (design doc §3.9) and follow it when it changes.
private final class OnboardingView: NSView {
    var onRequest: (() -> Void)?
    var onRestart: (() -> Void)?
    var onClose: (() -> Void)?
    var onLaunchAtLoginChange: ((Bool) -> Void)?
    var onOpenLoginItems: (() -> Void)?

    private static let width: CGFloat = 400
    private static let inset: CGFloat = 24
    private static let textWidth = width - inset * 2

    private let stack = NSStackView()
    private let request = NSButton(title: String(localized: "去授权", comment: "Onboarding: primary button"), target: nil, action: nil)
    private let restartRow = NSStackView()
    private let restartHint = NSTextField(wrappingLabelWithString: "")
    private let restart = NSButton(title: String(localized: "重新启动 Glimpse", comment: "Onboarding: restart button"), target: nil, action: nil)

    /// How the window offers a restart (PermissionFlow): a quiet hint after the system's prompt, a clear one
    /// after the user came back from System Settings without the grant taking effect, and its own sentence
    /// when ScreenCaptureKit refused a capture although the permission looks granted.
    enum RestartOffer {
        case quiet, prominent, captureRefused
    }
    /// A SwiftUI switch, like the settings page: AppKit offers no way to tint a checkbox or switch.
    private let launchAtLogin = NSHostingView(rootView: LaunchAtLoginSwitch(isOn: false, tint: nil, onChange: { _ in }))
    private var launchAtLoginIsOn = false
    private var accentObservation: AccentObservation?
    private let loginItemRow = NSStackView()
    private let loginItemError = NSTextField(wrappingLabelWithString: "")
    private let openLoginItems = NSButton(title: String(localized: "打开登录项设置", comment: "Opens System Settings → Login Items"), target: nil, action: nil)

    init(shortcut: KeyCombo?) {
        super.init(frame: .zero)
        let textWidth = Self.textWidth

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .regular))
        icon.contentTintColor = .glimpseAccent

        let title = Self.label(String(localized: "允许 Glimpse 录制屏幕", comment: "Onboarding: title"), font: .systemFont(ofSize: 17, weight: .semibold), width: textWidth)
        let body = Self.label(String(localized: "截图需要「屏幕录制」权限。点「去授权」，在系统设置里打开 Glimpse 的开关。画面只在本机处理，不会上传。",
                                             comment: "Onboarding: body"), font: .systemFont(ofSize: 13), width: textWidth)
        body.textColor = .materialSecondaryText
        // The system's own prompt talks about recording the screen and system audio, which alarms people
        // (device feedback): say first what Glimpse actually does.
        let promptNote = Self.label(String(localized: "接下来 macOS 会弹出系统提示，提到“录制屏幕和系统音频”。这是系统对所有截图工具的统一措辞；Glimpse 只在你按快捷键时截一张图，不录屏、不录音。",
                                                   comment: "Onboarding: explains the system's Screen Recording prompt"),
                                    font: .systemFont(ofSize: 12), width: textWidth)
        promptNote.textColor = .materialSecondaryText

        request.target = self
        request.action = #selector(requestClicked)
        request.bezelStyle = .push
        request.keyEquivalent = "\r"

        restartHint.preferredMaxLayoutWidth = textWidth - 150
        restart.target = self
        restart.action = #selector(restartClicked)
        restart.bezelStyle = .push
        restartRow.orientation = .horizontal
        restartRow.alignment = .centerY
        restartRow.spacing = 12
        restartRow.addArrangedSubview(restartHint)
        restartRow.addArrangedSubview(restart)
        restartRow.isHidden = true

        let hotkeyText = shortcut.map {
            String(localized: "截图快捷键是 \($0.displayString)。按了没反应时，可能被微信、QQ 等应用的截图快捷键占用，请在那边改掉，或在 Glimpse 的「设置」里换一个。",
                   comment: "Onboarding: shortcut hint; %@ is the shortcut")
        } ?? String(localized: "截图快捷键还没有设置。按了没反应时，可能被微信、QQ 等应用的截图快捷键占用，请在那边改掉，或在 Glimpse 的「设置」里换一个。",
                    comment: "Onboarding: shortcut hint when no shortcut is set")
        let hint = Self.label(hotkeyText, font: .systemFont(ofSize: 12), width: textWidth)
        hint.textColor = .materialSecondaryText

        refreshLaunchAtLogin()
        loginItemError.font = .systemFont(ofSize: 12)
        loginItemError.textColor = .systemRed
        openLoginItems.target = self
        openLoginItems.action = #selector(openLoginItemsClicked)
        openLoginItems.bezelStyle = .push
        openLoginItems.controlSize = .small
        loginItemRow.orientation = .horizontal
        loginItemRow.alignment = .centerY
        loginItemRow.spacing = 8
        loginItemRow.addArrangedSubview(loginItemError)
        loginItemRow.addArrangedSubview(openLoginItems)
        loginItemRow.isHidden = true

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "关闭", comment: "Close (menu item / button)"))!,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = .materialSecondaryText
        close.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        for view in [icon, title, body, promptNote, request, restartRow, hint, launchAtLogin, loginItemRow] as [NSView] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(4, after: launchAtLogin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(close)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        accentObservation = AccentObservation { [weak self, weak icon] in
            guard let self else { return }
            // New values, so the controls drop what they resolved before; glimpseAccent resolves when drawn.
            icon?.contentTintColor = nil
            icon?.contentTintColor = .glimpseAccent
            applyAccent()
        }
        applyAccent()
    }

    /// 「重新启动 Glimpse」 is the primary button (Return) once a restart is what is needed.
    private var restartIsPrimary = false

    /// Only the primary button (the one Return presses) is filled with the accent; the switch follows it too.
    private func applyAccent() {
        request.applyAccentFill(!restartIsPrimary)
        restart.applyAccentFill(restartIsPrimary)
        refreshLaunchAtLogin()
    }

    /// Rebuilds the switch with its state and the current accent (nil: the system accent).
    private func refreshLaunchAtLogin() {
        launchAtLogin.rootView = LaunchAtLoginSwitch(isOn: launchAtLoginIsOn, tint: InterfaceAccent.current.tint) { [weak self] on in
            guard let self else { return }
            launchAtLoginIsOn = on // flips at once; showLoginItem then shows what the system did
            refreshLaunchAtLogin()
            onLaunchAtLoginChange?(on)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func showRestart(_ offer: RestartOffer?) {
        restartRow.isHidden = offer == nil
        // Return presses the button the window is asking for: 「重新启动」 once a restart is what is needed.
        let restartIsNeeded = offer == .prominent || offer == .captureRefused
        request.keyEquivalent = restartIsNeeded ? "" : "\r"
        restart.keyEquivalent = restartIsNeeded ? "\r" : ""
        restartIsPrimary = restartIsNeeded
        switch offer {
        case nil:
            break
        case .quiet:
            showRestartHint(String(localized: "打开开关后若没有生效，请重新启动 Glimpse", comment: "Onboarding: quiet restart hint"), size: 11, color: .materialTertiaryText)
            restart.controlSize = .small
        case .prominent:
            showRestartHint(String(localized: "已经打开了开关？需要重新启动 Glimpse 才能生效。", comment: "Onboarding: restart hint"), size: 12, color: .materialSecondaryText)
            restart.controlSize = .regular
        case .captureRefused:
            showRestartHint(String(localized: "系统设置里已允许，但截图仍被拒绝。请重新启动 Glimpse；若仍不行，在系统设置里关掉再打开 Glimpse 的开关。",
                                             comment: "Onboarding: capture refused although permission looks granted"),
                            size: 12, color: .materialSecondaryText)
            restart.controlSize = .regular
        }
        applyAccent() // after the size: the fill and title colour go to the button Return now presses
    }

    /// The restart could not be started (PermissionService.relaunch); stays until the offer changes.
    func showRestartFailed() {
        restartRow.isHidden = false
        showRestartHint(String(localized: "无法自动重启，请手动退出后重新打开", comment: "Onboarding: relaunch failed"), size: 12, color: .systemRed)
    }

    private func showRestartHint(_ text: String, size: CGFloat, color: NSColor) {
        restartHint.stringValue = text
        restartHint.font = .systemFont(ofSize: size)
        restartHint.textColor = color
    }

    /// The switch shows the system's state, or on while `recommended` (the user has not chosen yet; 「去授权」
    /// then registers it, design doc §3.8). A failure shows why (design doc §6), with 「打开登录项设置」 when
    /// Glimpse was switched off in System Settings → General → Login Items (as on the settings page).
    func showLoginItem(_ display: LoginItemService.Display, recommended: Bool) {
        launchAtLoginIsOn = recommended || display.isOn
        refreshLaunchAtLogin()
        loginItemError.stringValue = display.error ?? ""
        openLoginItems.isHidden = !display.needsApproval
        loginItemError.preferredMaxLayoutWidth = display.needsApproval ? Self.textWidth - 130 : Self.textWidth
        loginItemRow.isHidden = display.error == nil
    }

    private static func label(_ text: String, font: NSFont, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .materialText
        label.preferredMaxLayoutWidth = width
        return label
    }

    @objc private func requestClicked() { onRequest?() }
    @objc private func restartClicked() { onRestart?() }
    @objc private func closeClicked() { onClose?() }
    @objc private func openLoginItemsClicked() { onOpenLoginItems?() }
}

/// 「开机自动启动」 in the onboarding window: a small switch in the interface accent, label first, as on the
/// settings page.
private struct LaunchAtLoginSwitch: View {
    let isOn: Bool
    let tint: Color?
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            Text(String(localized: "开机自动启动", comment: "Launch at login switch"))
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .materialText))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(tint)
        .fixedSize()
    }
}
