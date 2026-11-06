import Foundation
import Testing
@testable import GlimpseCore

/// The package's string catalog (Resources/Localizable.xcstrings) ships every language with every key, and the
/// keys are exactly the ones the code uses.
struct LocalizationTests {
    @Test func everyLanguageIsInTheBundle() {
        for language in LocalizedText.languages {
            #expect(LocalizedText.isAvailable(language), "\(language)")
        }
    }

    @Test func catalogHasExactlyTheKeysTheCodeUses() {
        let inCatalog = Set(LocalizedText.allKeys)
        let inCode = LocalizedText.keysUsedInCode
        #expect(!inCode.isEmpty)
        #expect(inCode.subtracting(inCatalog).isEmpty, "used in code, missing from the catalog: \(inCode.subtracting(inCatalog).sorted())")
        #expect(inCatalog.subtracting(inCode).isEmpty, "in the catalog, no longer used: \(inCatalog.subtracting(inCode).sorted())")
    }

    @Test func everyKeyHasAValueInEveryLanguage() {
        let keys = LocalizedText.allKeys
        #expect(!keys.isEmpty)
        for language in LocalizedText.languages {
            for key in keys {
                let value = LocalizedText.text(key, in: language)
                #expect(value?.isEmpty == false, "\(language): \(key)")
                // zh-Hant may legitimately equal zh-Hans (紫色, 橙色, 石墨色); English must differ.
                if language == "en" { #expect(value != key, "en still has the source text: \(key)") }
            }
        }
    }

    /// Approximates the runtime fallback: Bundle picks the .lproj the same way `preferredLocalizations(from:
    /// forPreferences:)` does, and with no match it uses CFBundleDevelopmentRegion / defaultLocalization, both
    /// "en" here. The real bundle lookup cannot be driven with another user's languages from a test, so this
    /// exercises the matching alone, with the catalog's language list.
    @Test func languagesWithoutATranslationFallBackToEnglish() {
        let available = LocalizedText.languages
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["nl"]) == ["en"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["vi-VN", "th-TH"]) == ["en"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["nl", "de-DE"]) == ["de"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["en-GB"]) == ["en"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["zh-TW"]) == ["zh-Hant"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["pt-PT"]) == ["pt-BR"])
        #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["zh-CN"]) == ["zh-Hans"])
    }

    @Test func sourceLanguageKeepsTheKeyAsItsText() {
        for key in LocalizedText.allKeys {
            #expect(LocalizedText.text(key, in: "zh-Hans") == key)
        }
    }

    /// Every language keeps the source's placeholders, in the source's order (nothing is positional).
    @Test func placeholdersSurviveTranslation() {
        let placeholder = try! NSRegularExpression(pattern: "%(?:lld|d|@)")
        func found(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
        }
        for key in LocalizedText.allKeys {
            let expected = found(key)
            for language in LocalizedText.languages {
                #expect(LocalizedText.text(key, in: language).map(found) == expected, "\(language): \(key)")
            }
        }
    }

    @Test func accentTitlesAndRejectionsAreLocalized() {
        for accent in AccentColor.allCases {
            #expect(!accent.title.isEmpty)
        }
        let rejections: [HotkeyRecording.Rejection] = [.needsModifier, .unsupportedKey, .sameAsOther, .reserved, .typesCharacter]
        #expect(Set(rejections.map(\.message)).count == rejections.count)
        for rejection in rejections {
            #expect(!rejection.message.isEmpty)
        }
    }
}
