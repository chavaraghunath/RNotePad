// SPDX-License-Identifier: MIT
// Sourcepad — Phase 24 Live Text OCR.
//
// Reads text out of an image via Vision's VNRecognizeTextRequest. The
// menu surface: drop a screenshot, then "Image → OCR Text" inserts the
// recognised lines at the caret.

import AppKit
import Vision

public enum LiveTextOCR {

    /// Run OCR on an image at `url`; calls `completion` on the main
    /// queue with the joined recognised lines (or nil on failure).
    public static func recognize(at url: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let nsimg = NSImage(contentsOf: url),
                  let cg = nsimg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                let lines: [String] = (request.results ?? []).compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// Show an open panel, OCR the chosen image, insert text at caret.
    public static func runForActiveEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recognize(at: url) { text in
            guard let text else { NSSound.beep(); return }
            insertAtCaret(text)
        }
    }

    private static func insertAtCaret(_ text: String) {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let pane = doc.primaryEditorViewController()?.editorPane else { return }
        let sel = SciGetSelectionBytes(pane.view)
        let pos = sel.location == NSNotFound ? 0 : sel.location
        SciInsertTextAt(pane.view, pos, text)
    }
}
