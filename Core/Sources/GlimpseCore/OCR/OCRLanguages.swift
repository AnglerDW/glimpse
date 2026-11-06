/// Which languages 提取文字 asks Vision for (design doc §3.5): the user's preferred languages, as far as Vision
/// supports them, so the recognition follows the system language instead of a fixed list.
public enum OCRLanguages {
    /// At most this many of the user's preferred languages are taken before the fixed additions.
    public static let preferredLimit = 3
    /// Always included: Latin text turns up in screenshots in every language.
    public static let fallback = "en-US"

    /// `preferred` is `Locale.preferredLanguages` (`zh-Hans-CN`, `en-GB`, `ja-JP`, …), `supported` is
    /// `VNRecognizeTextRequest.supportedRecognitionLanguages()` (`en-US`, `zh-Hans`, `ja-JP`, …).
    /// Returns Vision's identifiers, most preferred first: the first `preferredLimit` preferred languages
    /// Vision supports (each matched to Vision's closest identifier); then, whenever a Chinese-script language
    /// is there (zh-Hans, zh-Hant, or Cantonese yue-Hans / yue-Hant), both zh-Hans and zh-Hant, the same script
    /// first (Simplified and Traditional are often mixed on one screen); then `en-US` when missing.
    public static func recognitionLanguages(preferred: [String], supported: [String]) -> [String] {
        var result: [String] = []
        for tag in preferred {
            guard let match = bestMatch(for: tag, in: supported), !result.contains(match) else { continue }
            result.append(match)
            if result.count == preferredLimit { break }
        }
        if let first = result.first(where: { Tag($0).isChineseScript }) {
            let script = Tag(first).script ?? "Hans"
            let scripts = script.caseInsensitiveCompare("Hant") == .orderedSame ? ["Hant", "Hans"] : ["Hans", "Hant"]
            for wanted in scripts {
                guard let partner = supported.first(where: { isChinese($0, script: wanted) }), !result.contains(partner),
                      let last = result.lastIndex(where: { Tag($0).isChineseScript }) else { continue }
                // After the last Chinese-script entry, so a script the user listed keeps its place.
                result.insert(partner, at: last + 1)
            }
        }
        if !result.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) {
            result.append(fallback)
        }
        return result
    }

    /// Vision's identifier for a preferred language: an exact match, else the same language and script
    /// (the region decides between several, else the first), else the same language. Chinese without a script
    /// (`zh-TW`) is read by region: Taiwan, Hong Kong and Macau write Traditional.
    static func bestMatch(for tag: String, in supported: [String]) -> String? {
        let wanted = Tag(tag)
        guard !wanted.language.isEmpty else { return nil }
        if let exact = supported.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return exact }
        let sameLanguage = supported.filter { Tag($0).language == wanted.language }
        guard !sameLanguage.isEmpty else { return nil }
        let script = wanted.script ?? (wanted.language == "zh" ? inferredChineseScript(region: wanted.region) : nil)
        let candidates: [String]
        if let script {
            let sameScript = sameLanguage.filter { Tag($0).script?.caseInsensitiveCompare(script) == .orderedSame }
            candidates = sameScript.isEmpty ? sameLanguage : sameScript
        } else {
            candidates = sameLanguage
        }
        if let region = wanted.region,
           let sameRegion = candidates.first(where: { Tag($0).region?.caseInsensitiveCompare(region) == .orderedSame }) {
            return sameRegion
        }
        return candidates.first
    }

    private static func inferredChineseScript(region: String?) -> String {
        switch region?.uppercased() {
        case "TW", "HK", "MO": "Hant"
        default: "Hans"
        }
    }

    private static func isChinese(_ identifier: String, script: String) -> Bool {
        let tag = Tag(identifier)
        return tag.language == "zh" && tag.script?.caseInsensitiveCompare(script) == .orderedSame
    }

    /// The pieces of a BCP 47 tag this needs: `zh-Hans-CN` → zh / Hans / CN; `en-GB` → en / nil / GB.
    private struct Tag {
        let language: String
        let script: String?
        let region: String?

        /// Mandarin or Cantonese in Han script: what the zh-Hans / zh-Hant pairing applies to.
        var isChineseScript: Bool {
            (language == "zh" || language == "yue")
                && (script == nil || script?.caseInsensitiveCompare("Hans") == .orderedSame
                    || script?.caseInsensitiveCompare("Hant") == .orderedSame)
        }

        init(_ identifier: String) {
            let parts = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
            language = parts.first?.lowercased() ?? ""
            var script: String?
            var region: String?
            for part in parts.dropFirst() {
                if part.count == 4, part.allSatisfy(\.isLetter) {
                    script = script ?? part
                } else if part.count == 2 && part.allSatisfy(\.isLetter) || part.count == 3 && part.allSatisfy(\.isNumber) {
                    region = region ?? part
                }
            }
            self.script = script
            self.region = region
        }
    }
}
