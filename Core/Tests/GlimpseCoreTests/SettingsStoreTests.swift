import Foundation
import Testing
@testable import GlimpseCore

struct SettingsStoreTests {
    /// Runs `body` with a store backed by a throwaway suite, removing its plist afterwards.
    private func withStore(_ body: (SettingsStore, UserDefaults) throws -> Void) rethrows {
        let name = "glimpse-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(SettingsStore(defaults: defaults), defaults)
    }

    @Test func defaultHotkeyIsCommandShiftA() {
        // kVK_ANSI_A = 0; Carbon cmdKey = 0x100, shiftKey = 0x200
        #expect(KeyCombo.defaultScreenshot == KeyCombo(keyCode: 0, modifiers: 0x0300))
    }

    @Test func defaults() {
        withStore { store, _ in
            #expect(store.screenshotHotkey == .defaultScreenshot)
            #expect(store.saveDirectory.lastPathComponent == "Downloads")
        }
    }

    @Test func hotkeyCanBeChangedAndCleared() {
        withStore { store, _ in
            let combo = KeyCombo(keyCode: 18, modifiers: 0x0100)
            store.screenshotHotkey = combo
            #expect(store.screenshotHotkey == combo)
            store.screenshotHotkey = nil
            #expect(store.screenshotHotkey == nil)
        }
    }

    @Test func corruptHotkeyDataFallsBackToDefault() {
        withStore { store, defaults in
            defaults.set(Data([0xFF]), forKey: "screenshotHotkey")
            #expect(store.screenshotHotkey == .defaultScreenshot)
        }
    }

    @Test func ocrHotkeyIsControlOUntilChosen() {
        // kVK_ANSI_O = 31; Carbon controlKey = 0x1000
        #expect(KeyCombo.defaultOCR == KeyCombo(keyCode: 31, modifiers: 0x1000))
        withStore { store, _ in
            #expect(store.ocrHotkey == .defaultOCR)
            let combo = KeyCombo(keyCode: 17, modifiers: KeyCombo.command | KeyCombo.option)
            store.ocrHotkey = combo
            #expect(store.ocrHotkey == combo)
            #expect(store.screenshotHotkey == .defaultScreenshot) // a separate key
        }
    }

    /// A user who cleared the shortcut before ⌃O became the default keeps it cleared: a stored `nil` is not
    /// the same as never set.
    @Test func clearedOcrHotkeyStaysCleared() {
        withStore { store, defaults in
            store.ocrHotkey = nil
            #expect(store.ocrHotkey == nil)
            #expect(SettingsStore(defaults: defaults).ocrHotkey == nil)
            defaults.set(Data([0xFF]), forKey: "ocrHotkey") // unreadable: back to the default
            #expect(store.ocrHotkey == .defaultOCR)
        }
    }

    @Test func accentFollowsTheSystemUntilPicked() {
        withStore { store, defaults in
            #expect(store.accentColor == .system)
            store.accentColor = .purple
            #expect(SettingsStore(defaults: defaults).accentColor == .purple)
            defaults.set("teal", forKey: "accentColor") // a name this version does not know
            #expect(store.accentColor == .system)
        }
    }

    /// The onboarding recommendation (switch shown on) is pending until the user has chosen; the choice sticks.
    @Test func interfaceLanguageFollowsTheSystemUntilPicked() {
        withStore { store, defaults in
            #expect(store.interfaceLanguage == .system)
            #expect(defaults.object(forKey: "interfaceLanguage") == nil)
            store.interfaceLanguage = .ja
            #expect(defaults.string(forKey: "interfaceLanguage") == "ja")
            #expect(SettingsStore(defaults: defaults).interfaceLanguage == .ja)
            defaults.set("nl", forKey: "interfaceLanguage") // a language this version does not ship
            #expect(store.interfaceLanguage == .system)
            store.interfaceLanguage = .system
            #expect(defaults.object(forKey: "interfaceLanguage") == nil)
        }
    }

    @Test func loginItemChoiceIsPendingUntilMadeOnce() {
        withStore { store, defaults in
            #expect(!store.loginItemDefaultApplied)
            store.loginItemDefaultApplied = true
            #expect(SettingsStore(defaults: defaults).loginItemDefaultApplied)
        }
    }

    @Test func saveDirectoryPersists() {
        withStore { store, _ in
            store.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
            #expect(store.saveDirectory.path == "/tmp/shots")
        }
    }

    @Test func saveDirectoryValidation() {
        withStore { store, defaults in
            let downloads = SettingsStore.defaultSaveDirectory
            defaults.set("file:///tmp/glimpse%20x", forKey: "saveDirectory")
            #expect(store.saveDirectory.path == "/tmp/glimpse x")
            defaults.set("/no/such/dir", forKey: "saveDirectory")
            #expect(store.saveDirectory.path == "/no/such/dir") // kept: save fails, copy-only
            defaults.set("relative/dir", forKey: "saveDirectory")
            #expect(store.saveDirectory == downloads)
            defaults.set("https://example.com/x", forKey: "saveDirectory")
            #expect(store.saveDirectory == downloads)
            defaults.set(42, forKey: "saveDirectory")
            #expect(store.saveDirectory == downloads)
            store.saveDirectory = URL(fileURLWithPath: "/tmp/shots")
            #expect(store.saveDirectory.path == "/tmp/shots")
        }
    }
}
