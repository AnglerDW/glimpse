import Foundation
import Testing
@testable import GlimpseCore

struct InterfaceLanguageTests {
    private let languages = InterfaceLanguage.allCases.filter { $0 != .system }

    @Test func systemIsFirstAndHasNoCode() {
        #expect(InterfaceLanguage.allCases.first == .system)
        #expect(InterfaceLanguage.system.code == nil)
        #expect(InterfaceLanguage.system.appleLanguagesValue == nil)
        #expect(InterfaceLanguage.system.nativeName == nil)
        #expect(!InterfaceLanguage.system.title.isEmpty)
    }

    /// The choices are exactly the languages the catalogs ship, under the identifiers the catalogs use.
    @Test func codesAreTheCatalogLanguages() {
        #expect(Set(languages.compactMap(\.code)) == Set(LocalizedText.languages))
        for language in languages {
            #expect(language.rawValue == language.code)
            #expect(language.appleLanguagesValue == [language.rawValue])
            #expect(LocalizedText.isAvailable(language.rawValue), "\(language.rawValue)")
        }
    }

    @Test func nativeNamesAreSetAndDistinct() {
        let names = languages.compactMap(\.nativeName)
        #expect(names.count == languages.count)
        #expect(Set(names).count == names.count)
        for language in languages {
            #expect(language.title == language.nativeName)
        }
        #expect(InterfaceLanguage.zhHans.nativeName == "简体中文")
        #expect(InterfaceLanguage.ptBR.nativeName == "Português (Brasil)")
    }

    @Test func storedByCodeAndUnknownValuesFollowTheSystem() {
        #expect(InterfaceLanguage(rawValue: "zh-Hant") == .zhHant)
        #expect(InterfaceLanguage(rawValue: "nl") == nil)
    }
}
