import CoreGraphics
import Testing
@testable import GlimpseCore

struct AccentContrastTests {
    @Test func contrastRatioMatchesWCAG() {
        let white = RGBA(red: 1, green: 1, blue: 1), black = RGBA(red: 0, green: 0, blue: 0)
        #expect(abs(white.contrastRatio(with: black) - 21) < 0.001)
        #expect(white.contrastRatio(with: white) == 1)
        #expect(abs(RGBA(hex: 0x007AFF).contrastRatio(with: white) - 4.02) < 0.01) // system blue
    }

    @Test func filledButtonTitlePerAccentPreset() {
        let darkTitle = AccentColor.allCases.flatMap { accent in
            [false, true].compactMap { dark -> String? in
                guard let fill = accent.rgba(darkAppearance: dark) else { return nil }
                return fill.filledButtonPrefersDarkTitle ? "\(accent.rawValue)\(dark ? "-dark" : "")" : nil
            }
        }
        #expect(darkTitle == ["orange", "orange-dark", "green", "green-dark", "graphite-dark"])
    }

    @Test func whiteTitlesKeepAtLeastThreeToOne() {
        let white = RGBA(red: 1, green: 1, blue: 1), black = RGBA(red: 0, green: 0, blue: 0)
        for accent in AccentColor.allCases {
            for dark in [false, true] {
                guard let fill = accent.rgba(darkAppearance: dark) else { continue }
                let title = fill.filledButtonPrefersDarkTitle ? black : white
                #expect(fill.contrastRatio(with: title) >= 3, "\(accent) dark: \(dark)")
            }
        }
    }
}
