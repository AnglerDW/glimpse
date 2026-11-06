import Testing
@testable import GlimpseCore

struct OCRLanguagesTests {
    /// What `VNRecognizeTextRequest.supportedRecognitionLanguages()` returns on macOS 14.
    private let supported = ["en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "zh-Hans", "zh-Hant",
                             "yue-Hans", "yue-Hant", "ko-KR", "ja-JP", "ru-RU", "uk-UA", "th-TH", "vi-VT"]

    private func languages(_ preferred: [String]) -> [String] {
        OCRLanguages.recognitionLanguages(preferred: preferred, supported: supported)
    }

    @Test func simplifiedChineseMacGetsBothScriptsAndEnglish() {
        #expect(languages(["zh-Hans-CN", "en-CN"]) == ["zh-Hans", "zh-Hant", "en-US"])
    }

    @Test func traditionalChineseMacGetsBothScriptsTraditionalFirst() {
        #expect(languages(["zh-Hant-TW", "en-TW"]) == ["zh-Hant", "zh-Hans", "en-US"])
        #expect(languages(["zh-Hant-HK"]) == ["zh-Hant", "zh-Hans", "en-US"])
    }

    @Test func chineseWithoutScriptIsReadFromTheRegion() {
        #expect(languages(["zh-TW"]) == ["zh-Hant", "zh-Hans", "en-US"])
        #expect(languages(["zh-CN"]) == ["zh-Hans", "zh-Hant", "en-US"])
        #expect(languages(["zh"]) == ["zh-Hans", "zh-Hant", "en-US"])
    }

    @Test func japaneseMacGetsJapaneseThenEnglish() {
        #expect(languages(["ja-JP"]) == ["ja-JP", "en-US"])
    }

    @Test func englishIsNeverDuplicated() {
        #expect(languages(["en-US"]) == ["en-US"])
        #expect(languages(["en-GB", "fr-FR"]) == ["en-US", "fr-FR"])
        #expect(languages(["en-US", "zh-Hans-CN"]) == ["en-US", "zh-Hans", "zh-Hant"])
    }

    @Test func atMostThreePreferredLanguagesAreTaken() {
        #expect(languages(["de-DE", "fr-FR", "it-IT", "ja-JP"]) == ["de-DE", "fr-FR", "it-IT", "en-US"])
        // The partner script and en-US come on top of the three.
        #expect(languages(["de-DE", "fr-FR", "zh-Hans-CN", "ja-JP"]) == ["de-DE", "fr-FR", "zh-Hans", "zh-Hant", "en-US"])
    }

    @Test func unsupportedLanguagesAreSkipped() {
        #expect(languages(["sw-KE"]) == ["en-US"])
        #expect(languages([]) == ["en-US"])
        #expect(languages(["sw-KE", "ko-KR", "nl-NL", "ru-RU"]) == ["ko-KR", "ru-RU", "en-US"])
    }

    @Test func regionAndCaseDoNotMatter() {
        #expect(languages(["pt-PT"]) == ["pt-BR", "en-US"])
        #expect(languages(["es-MX"]) == ["es-ES", "en-US"])
        #expect(languages(["JA-jp"]) == ["ja-JP", "en-US"])
        #expect(languages(["es-419"]) == ["es-ES", "en-US"])
        #expect(languages(["zh_Hans_CN"]) == ["zh-Hans", "zh-Hant", "en-US"]) // underscores, as some APIs write them
        #expect(languages(["zh-Hans-SG"]) == ["zh-Hans", "zh-Hant", "en-US"])
        #expect(languages(["zh-HK"]) == ["zh-Hant", "zh-Hans", "en-US"])
    }

    /// Cantonese is written in Han characters too, so it brings both Mandarin scripts along.
    @Test func cantoneseBringsBothChineseScripts() {
        #expect(languages(["yue-Hant-HK"]) == ["yue-Hant", "zh-Hant", "zh-Hans", "en-US"])
        #expect(languages(["yue-Hans-CN"]) == ["yue-Hans", "zh-Hans", "zh-Hant", "en-US"])
        #expect(languages(["yue-Hant-HK", "zh-Hant-HK", "en-HK"]) == ["yue-Hant", "zh-Hant", "zh-Hans", "en-US"])
    }

    @Test func noSupportedLanguagesStillGivesEnglish() {
        #expect(OCRLanguages.recognitionLanguages(preferred: ["zh-Hans-CN", "ja-JP"], supported: []) == ["en-US"])
        #expect(OCRLanguages.recognitionLanguages(preferred: [], supported: []) == ["en-US"])
    }

    @Test func duplicatePreferredLanguagesCountOnce() {
        #expect(languages(["fr-FR", "fr-CA", "fr-CH", "de-DE"]) == ["fr-FR", "de-DE", "en-US"])
    }
}
