import Foundation
import Testing
@testable import GlimpseCore

struct AnnotationStyleStoreTests {
    /// Runs `body` with a throwaway suite, removing its plist afterwards.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "glimpse-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func startsRedMedium() {
        withDefaults { defaults in
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .red, width: .medium))
        }
    }

    @Test func styleIsRememberedAcrossInstances() {
        withDefaults { defaults in
            AnnotationStyleStore(defaults: defaults).style = AnnotationStyle(color: .blue, width: .thick)
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .blue, width: .thick))
        }
    }

    @Test func corruptValueFallsBackToTheStandardStyle() {
        withDefaults { defaults in
            defaults.set(Data([0xFF]), forKey: AnnotationStyleStore.key)
            #expect(AnnotationStyleStore(defaults: defaults).style == .standard)
        }
    }

    @Test func anUnreadableFieldKeepsTheOther() {
        withDefaults { defaults in
            // A colour this version does not know (say, from a later one): only the colour falls back.
            defaults.set(Data(#"{"color":"purple","width":"thick"}"#.utf8), forKey: AnnotationStyleStore.key)
            #expect(AnnotationStyleStore(defaults: defaults).style == AnnotationStyle(color: .red, width: .thick))
        }
    }
}
