import AppKit
import GlimpseCore

enum OutputService {
    /// Puts the image on the pasteboard lazily: nothing is encoded until a paste asks for a type,
    /// so finishing a capture never blocks on a (possibly ~60MB) TIFF encode.
    /// The rep's size is in points so a Retina capture pastes at the right size.
    @MainActor
    static func copy(_ image: CGImage, scale: CGFloat) {
        let provider = LazyImageProvider(image: image, scale: scale)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png, .tiff])
        // Clearing makes the previous provider's pasteboardFinishedWithDataProvider run; do it before we retain the new one.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        // The pasteboard does not retain providers; keep it until it reports it is finished.
        activeProvider = provider
    }

    @MainActor fileprivate static var activeProvider: LazyImageProvider?

    /// Encodes once and saves to `directory` with a millisecond-precise name. Atomic and never overwrites;
    /// throws if the directory is missing or not writable. Safe to call off the main thread.
    @discardableResult
    static func savePNG(_ image: CGImage, scale: CGFloat, to directory: URL, date: Date) throws -> URL {
        guard let png = bitmap(image, scale: scale).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(ScreenshotFileName.make(for: date))
        try AtomicFileWriter.writeWithoutOverwriting(png, to: url)
        return url
    }

    /// Thread-safe: every call creates a fresh rep and shares no state. It runs on the main thread
    /// (pasteboard provider) and on background threads (save).
    fileprivate static func bitmap(_ image: CGImage, scale: CGFloat) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep
    }
}

// Safe: immutable state; AppKit calls the provider methods on the main thread.
private final class LazyImageProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let image: CGImage
    private let scale: CGFloat

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        let rep = OutputService.bitmap(image, scale: scale)
        let data: Data?
        switch type {
        case .png: data = rep.representation(using: .png, properties: [:])
        case .tiff: data = rep.tiffRepresentation
        default: data = nil
        }
        if let data { item.setData(data, forType: type) }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        // AppKit does not say which thread calls this, so hop to the main actor explicitly.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if OutputService.activeProvider === self { OutputService.activeProvider = nil }
            }
        }
    }
}
