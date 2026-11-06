import Foundation

public enum AtomicFileWriter {
    /// Writes `data` to a temp file in the volume's item replacement directory, then moves it into place.
    /// Fails (and leaves nothing behind) if `url` already exists, the directory is missing, or the write fails,
    /// so a full disk never leaves a half-written file under the final name.
    public static func writeWithoutOverwriting(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        // The system's per-volume temporary area: a killed process leaves nothing in the user's folder.
        let scratch = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let temp = scratch.appendingPathComponent(url.lastPathComponent)
        try data.write(to: temp, options: [])
        try fileManager.moveItem(at: temp, to: url) // throws if `url` exists
    }
}
