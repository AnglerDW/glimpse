import Foundation

/// Remembers the colour and width level all tools share, across captures and launches (design doc §3.3).
// Safe: the only state is a `UserDefaults`, which is thread-safe.
public final class AnnotationStyleStore: @unchecked Sendable {
    static let key = "annotationStyle"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `.standard` until something is picked, or when the stored value cannot be read at all; a single
    /// unreadable field falls back alone (see `AnnotationStyle.init(from:)`).
    public var style: AnnotationStyle {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let style = try? JSONDecoder().decode(AnnotationStyle.self, from: data) else { return .standard }
            return style
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                assertionFailure("Failed to encode AnnotationStyle")
                return
            }
            defaults.set(data, forKey: Self.key)
        }
    }
}
