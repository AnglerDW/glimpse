import AppKit
import GlimpseCore

extension KeyInput {
    init(event: NSEvent) {
        let key: KeyInput.Key
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .enter          // Return, keypad Enter
        case 49: key = .space
        case 123: key = .arrow(dx: -1, dy: 0)
        case 124: key = .arrow(dx: 1, dy: 0)
        case 125: key = .arrow(dx: 0, dy: 1)  // down (screen-local y grows downward)
        case 126: key = .arrow(dx: 0, dy: -1)
        default: key = Self.character(for: event).map { .character($0) } ?? .other
        }
        let flags = event.modifierFlags
        self.init(key: key,
                  command: flags.contains(.command),
                  shift: flags.contains(.shift),
                  option: flags.contains(.option),   // ⌥R / ⌃R must not switch tools (KeyRouter ignores them)
                  control: flags.contains(.control))
    }

    /// Non-Latin layouts (Russian, Greek…) report non-ASCII characters, which would break ⌘C / ⌘S / ⌘Z and
    /// the tool letters; fall back to the physical key's ANSI letter.
    private static func character(for event: NSEvent) -> Character? {
        if let c = event.charactersIgnoringModifiers?.first, c.isASCII { return c }
        if let letter = ansiLetters[event.keyCode] { return letter }
        return event.charactersIgnoringModifiers?.first
    }

    private static let ansiLetters: [UInt16: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
}
