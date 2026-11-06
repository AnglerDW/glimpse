import os

/// Unified logging. Release builds log too, so nothing private goes in: file paths are interpolated with
/// `privacy: .private`, errors as `localizedDescription` only (an NSError's userInfo carries paths), and
/// plain state (action names, status codes, pixel rects) as `.public` (README: 系统日志不记路径).
enum Log {
    static let app = Logger(subsystem: "com.anglerdw.glimpse", category: "app")
}
