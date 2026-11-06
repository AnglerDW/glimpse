import AppKit
import GlimpseCore

/// Extracts the text of a selection (提取文字) and shows it (design doc §3.5): the result goes to the clipboard
/// at once and into the result panel, where it can be edited and copied again. No HUD: the panel says
/// 「已复制」 itself (§3.8.1).
@MainActor
final class OCRController {
    /// A recognition started (true) or ended (false): finished with text, no text or an error, cancelled by a
    /// newer one or a new capture, or its panel closed. The menu bar icon animates meanwhile (§3.7).
    var onRecognizingChange: ((Bool) -> Void)?

    /// Created on the first recognition.
    private var panel: OCRResultPanel?
    /// The recognition whose result the panel waits for; a newer one replaces it.
    private var current: Task<Void, Never>?
    /// Counts recognitions, so a replaced one finishing late cannot end the newer one's "recognizing".
    private var generation = 0
    private var isRecognizing = false

    /// `image` is the selection's frozen pixels without annotations; `selection` is where it was on screen
    /// (AppKit global coordinates) and `screen` the screen it was on: the panel opens next to it.
    func recognize(_ image: CGImage, selection: CGRect, on screen: NSScreen?) {
        current?.cancel() // stops the older recognition's Vision request too
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.show(.recognizing, nextTo: selection, on: screen)
        generation += 1
        let generation = self.generation
        setRecognizing(true)
        current = Task { [weak self] in
            let text: String?
            do {
                text = ReadingOrder.text(of: try await OCRService.recognize(image))
            } catch {
                if !Task.isCancelled {
                    Log.app.error("text recognition failed: \(error.localizedDescription, privacy: .public)")
                }
                text = nil
            }
            if let self, generation == self.generation { self.setRecognizing(false) }
            // Replaced by a newer recognition, or the panel was closed meanwhile: leave the clipboard alone.
            guard !Task.isCancelled, panel.isVisible else { return }
            guard let text else { return panel.update(.failed) }
            guard !text.isEmpty else { return panel.update(.noText) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel.update(.copied(text))
        }
    }

    private func makePanel() -> OCRResultPanel {
        let panel = OCRResultPanel()
        panel.onDismiss = { [weak self] in self?.cancelCurrent() } // closed: the recognition is not wanted
        return panel
    }

    /// A new capture is starting: the panel must not end up in the frozen screen, and a recognition still
    /// running is dropped. Returns whether the panel was on screen.
    func dismissPanel() -> Bool {
        cancelCurrent()
        guard let panel, panel.isVisible else { return false }
        panel.dismiss()
        return true
    }

    private func cancelCurrent() {
        current?.cancel()
        current = nil
        setRecognizing(false)
    }

    private func setRecognizing(_ recognizing: Bool) {
        guard recognizing != isRecognizing else { return }
        isRecognizing = recognizing
        onRecognizingChange?(recognizing)
    }
}
