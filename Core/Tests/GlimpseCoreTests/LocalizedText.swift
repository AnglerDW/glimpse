import Foundation
@testable import GlimpseCore

/// Reads the package's string catalog the way the code does, so expectations do not depend on the language
/// `swift test` happens to run under (the runner may resolve to en on one Mac and zh-Hans on another).
///
/// Xcode compiles Resources/Localizable.xcstrings into one `<language>.lproj` per language; `swift build`
/// copies the .xcstrings file into the bundle as it is. Both are read here, so the tests see the same catalog
/// under `swift test` and inside an Xcode build.
enum LocalizedText {
    /// Every language the catalog ships; the source language first.
    static let languages = ["zh-Hans", "en", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR", "ru", "it"]

    /// `key` in whatever language the process resolved to: what `String(localized:bundle: .module)` returns.
    static func current(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// The bundle carries this language, compiled or in the catalog file.
    static func isAvailable(_ language: String) -> Bool {
        lproj(for: language) != nil || catalog.languages.contains(language)
    }

    /// Every key in the catalog (from the compiled source-language table, or the catalog file).
    static var allKeys: [String] {
        if let bundle = lproj(for: languages[0]),
           let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
           let data = try? Data(contentsOf: url),
           let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
            return table.keys.sorted()
        }
        return catalog.strings.keys.sorted()
    }

    /// `key` in one specific language; nil when that language or key is missing.
    static func text(_ key: String, in language: String) -> String? {
        if let bundle = lproj(for: language) {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: nil)
            return value == "\u{0}" ? nil : value
        }
        return catalog.strings[key]?[language]
    }

    /// The keys the package's code passes to `String(localized:)`, read from the sources next to this test
    /// target; interpolations are written as the placeholder `String(localized:)` turns them into.
    static var keysUsedInCode: Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GlimpseCore")
        guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
        let call = try! NSRegularExpression(pattern: #"String\(localized:\s*"((?:[^"\\]|\\.)*)""#)
        let interpolation = try! NSRegularExpression(pattern: #"\\\((?:[^()]|\([^()]*\))*\)"#)
        var keys: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = String(text[Range(match.range(at: 1), in: text)!])
                let mutable = NSMutableString(string: literal)
                // The package only interpolates Strings (HUDMessage); the generator checks the types.
                interpolation.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: "%@")
                keys.insert((mutable as String).replacingOccurrences(of: "\\\"", with: "\""))
            }
        }
        return keys
    }

    private static func lproj(for language: String) -> Bundle? {
        Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// The raw catalog: key → language → value (the source language falls back to the key).
    private static let catalog: (languages: Set<String>, strings: [String: [String: String]]) = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = json["sourceLanguage"] as? String,
              let entries = json["strings"] as? [String: [String: Any]] else { return ([], [:]) }
        var languages: Set<String> = []
        var strings: [String: [String: String]] = [:]
        for (key, entry) in entries {
            var values = [source: key]
            for (language, localization) in entry["localizations"] as? [String: [String: Any]] ?? [:] {
                guard let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String else { continue }
                values[language] = value
                languages.insert(language)
            }
            strings[key] = values
        }
        return (languages, strings)
    }()
}
