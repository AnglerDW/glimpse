import CoreGraphics
import Foundation
import GlimpseCore
import Vision

/// Local, offline text recognition with Vision (design doc §3.5, §5.1): accurate mode, the languages the
/// system is set to (`OCRLanguages`), with language correction. Nothing leaves the Mac.
enum OCRService {
    /// The user's preferred languages, as far as Vision supports them, plus en-US (design doc §3.5).
    /// `supportedRecognitionLanguages()` depends on the request's level and revision, so it is asked per request.
    static func recognitionLanguages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        return OCRLanguages.recognitionLanguages(preferred: Locale.preferredLanguages, supported: supported)
    }

    /// The lines Vision finds in `image`, in no particular order (`ReadingOrder` sorts them).
    /// Runs off the main thread; cancelling the calling task stops Vision (it then throws).
    static func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages(for: request)
        request.usesLanguageCorrection = true
        let box = RequestBox(request)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let request = box.request
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return (request.results ?? []).compactMap { observation -> RecognizedLine? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    // Vision's box is normalised with a bottom-left origin; RecognizedLine is top-left.
                    let box = observation.boundingBox
                    return RecognizedLine(text: text, frame: CGRect(x: box.minX, y: 1 - box.maxY,
                                                                    width: box.width, height: box.height))
                }
            }.value
        } onCancel: {
            box.request.cancel()
        }
    }
}

/// Hands the request to the background task and to the cancellation handler. Vision documents `cancel()`
/// as callable from another thread while `perform` runs; nothing else touches the request concurrently.
private final class RequestBox: @unchecked Sendable {
    let request: VNRecognizeTextRequest

    init(_ request: VNRecognizeTextRequest) {
        self.request = request
    }
}
