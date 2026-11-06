import Foundation
import GlimpseCore
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (design doc §3.9, §5.1). The system holds the state;
/// nothing is mirrored in Glimpse's settings except that the default was applied once.
@MainActor
enum LoginItemService {
    enum Failure: LocalizedError {
        /// Registered, but switched off in System Settings → General → Login Items.
        case requiresApproval
        case system(String)

        var errorDescription: String? {
            switch self {
            case .requiresApproval:
                String(localized: "需要在「系统设置 → 通用 → 登录项」里允许 Glimpse", comment: "Launch at login error")
            case .system(let reason):
                String(localized: "开启失败：\(reason)", comment: "Launch at login error; %@ is the system's reason")
            }
        }
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Throws `Failure` with a reason for the user; the switch then goes back (design doc §6).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            // register() also throws when the item is already there; the status says what actually holds.
            switch service.status {
            case .enabled where enabled, .notRegistered where !enabled: return
            case .requiresApproval where enabled: throw Failure.requiresApproval
            default: throw Failure.system(error.localizedDescription)
            }
        }
        if enabled, service.status == .requiresApproval { throw Failure.requiresApproval }
    }

    /// Recommended on (design doc §3.8, §3.9), but never registered without the user: while this is true the
    /// onboarding switch shows on, and 「去授权」 applies what the switch shows, once. Over as soon as the user
    /// flips a switch (`recordChoice`) or 「去授权」 applied it. Never in Debug builds: the development build in
    /// build/ must not register itself as a login item (the switches still work by hand).
    static func isRecommendationPending(settings: SettingsStore) -> Bool {
        #if DEBUG
        return false
        #else
        return !settings.loginItemDefaultApplied
        #endif
    }

    /// The user chose (flipped a switch, or clicked 「去授权」 with the switch as shown): the recommendation
    /// is not shown or applied again.
    static func recordChoice(settings: SettingsStore) {
        settings.loginItemDefaultApplied = true
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// What a 「开机自动启动」 control shows. Shared by the settings page and the onboarding window, so both
    /// read the system the same way.
    @MainActor
    struct Display {
        private(set) var isOn = false
        private(set) var error: String?
        /// The error is fixed in System Settings → Login Items; the control offers 「打开登录项设置」.
        private(set) var needsApproval = false
        /// The system's state when `error` was set: the error stays until that state changes.
        private var statusAtError: SMAppService.Status?

        /// Reads the system's state, also when Glimpse comes back from System Settings. Switched off in
        /// System Settings → Login Items shows the hint and its button right away; any other error stays until
        /// the system's state changes.
        mutating func reload() {
            let status = LoginItemService.status
            isOn = status == .enabled
            if status == .requiresApproval {
                error = Failure.requiresApproval.errorDescription
                needsApproval = true
                statusAtError = status
            } else if error != nil, needsApproval || status != statusAtError {
                error = nil
                needsApproval = false
                statusAtError = nil
            }
        }

        /// The user flipped the control. A failure puts it back and says why (design doc §6).
        mutating func set(_ enabled: Bool) {
            error = nil
            needsApproval = false
            do {
                try LoginItemService.setEnabled(enabled)
            } catch {
                self.error = error.localizedDescription
                needsApproval = (error as? Failure).map {
                    if case .requiresApproval = $0 { true } else { false }
                } ?? false
                statusAtError = LoginItemService.status
            }
            isOn = LoginItemService.isEnabled
        }

        /// For SwiftUI: the control follows the click and the old error goes, as a change of its own before
        /// `set(_:)`, so putting the control back is always a change the page sees, even when the same
        /// failure happens twice in a row.
        mutating func follow(_ enabled: Bool) {
            isOn = enabled
            error = nil
            needsApproval = false
        }
    }
}
