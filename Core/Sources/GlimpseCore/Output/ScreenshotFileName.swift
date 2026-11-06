import Foundation

public enum ScreenshotFileName {
    /// e.g. "Glimpse 2026-11-04 17.30.05.123.png". Milliseconds avoid clashes when saving twice in one second.
    public static func make(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return "Glimpse \(formatter.string(from: date)).png"
    }
}
