import Carbon.HIToolbox
import GlimpseCore

/// Global shortcuts Glimpse registers (design doc §3.1).
enum HotkeyAction: UInt32, CaseIterable {
    case screenshot = 1
    /// 提取文字; ⌃O by default.
    case ocr = 2
}

enum HotkeyRegistrationResult: Equatable {
    case registered
    /// eventHotKeyExistsErr: another program already registered this combo globally.
    case conflict
    case failed(OSStatus)
}

/// Registers global shortcuts through Carbon, one per `HotkeyAction`.
/// Use on the main thread only. Not `@MainActor` so `deinit` can release the Carbon refs.
/// Carbon only reports a conflict when another program registered the same combo globally;
/// app menu shortcuts cannot be detected (design doc §3.1).
final class HotkeyService {
    private static let signature = OSType(0x474C_4D50) // 'GLMP'

    private var handlerRef: EventHandlerRef?
    private var registrations: [HotkeyAction: (ref: EventHotKeyRef, combo: KeyCombo, handler: () -> Void)] = [:]

    /// Registers `combo` for `action`. When `action` already has a hotkey, the old one stays
    /// in place unless the new combo registers successfully.
    @discardableResult
    func register(_ combo: KeyCombo, for action: HotkeyAction, handler: @escaping () -> Void) -> HotkeyRegistrationResult {
        // Same combo again (e.g. settings re-saved unchanged): Carbon would report our own
        // registration as a conflict, so just swap the handler.
        if let existing = registrations[action], existing.combo == combo {
            registrations[action] = (existing.ref, combo, handler)
            return .registered
        }

        let installStatus = installHandlerIfNeeded()
        guard installStatus == noErr else { return .failed(installStatus) }

        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            if status == OSStatus(eventHotKeyExistsErr) { return .conflict }
            return .failed(status == noErr ? OSStatus(paramErr) : status)
        }

        // Swap only after the new combo is in place.
        if let old = registrations[action] { UnregisterEventHotKey(old.ref) }
        registrations[action] = (newRef, combo, handler)
        return .registered
    }

    func unregister(_ action: HotkeyAction) {
        guard let old = registrations.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(old.ref)
    }

    deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.ref) }
        registrations.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func installHandlerIfNeeded() -> OSStatus {
        if handlerRef != nil { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            return service.handle(event)
        }, 1, &spec, userData, &ref)
        if status == noErr { handlerRef = ref }
        return status
    }

    /// Runs inside the Carbon callback (main thread).
    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        // Not ours: let other handlers see the event.
        guard status == noErr,
              hotKeyID.signature == Self.signature,
              let action = HotkeyAction(rawValue: hotKeyID.id),
              let handler = registrations[action]?.handler
        else { return OSStatus(eventNotHandledErr) }

        // Return to Carbon immediately; never run UI work inside the Carbon callback.
        DispatchQueue.main.async { handler() }
        return noErr
    }
}
