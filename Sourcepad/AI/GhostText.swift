// SPDX-License-Identifier: MIT
// Sourcepad — Phase 11 inline ghost-text tab completion.
//
// Flow:
//   1. On idle (debounced from .charAdded) we ask MLXService for a
//      short completion of the surrounding context.
//   2. The reply is rendered as an EOL annotation in faded grey at the
//      caret line. We track the byte the completion was anchored to.
//   3. Tab while a ghost is showing inserts the completion text via
//      SciInsertTextAt; the annotation clears.
//   4. Any movement, Esc, or further typing dismisses the ghost.

import AppKit

public final class GhostText {

    public weak var pane: EditorPaneViewController?

    private var currentSuggestion: String?
    private var anchorByte: Int = -1
    private var pendingWork: DispatchWorkItem?

    public init() {}

    /// Cancel any pending request + clear the current annotation.
    public func dismiss() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let pane else { return }
        if anchorByte >= 0 {
            let line = SciLineFromByte(pane.view, anchorByte)
            SciSetEOLAnnotationText(pane.view, line, nil)
        }
        currentSuggestion = nil
        anchorByte = -1
    }

    /// Schedule a completion request after `idleSeconds` of typing pause.
    public func scheduleAfterCharAdded(caretByte: Int, prefix: String, suffix: String) {
        dismiss()
        guard Preferences.shared.aiInlineCompleteEnabled,
              MLXService.shared.isAvailable else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.fireRequest(caretByte: caretByte, prefix: prefix, suffix: suffix)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Accept the current suggestion (Tab key). Returns true if a
    /// suggestion was inserted; false otherwise (caller falls back to
    /// the default Tab behavior).
    @discardableResult
    public func acceptIfAvailable() -> Bool {
        guard let pane, let suggestion = currentSuggestion, anchorByte >= 0 else {
            return false
        }
        SciBeginUndoAction(pane.view)
        SciInsertTextAt(pane.view, anchorByte, suggestion)
        SciSetSelectionBytes(pane.view, anchorByte + suggestion.lengthOfBytes(using: .utf8),
                             anchorByte + suggestion.lengthOfBytes(using: .utf8))
        SciEndUndoAction(pane.view)
        dismiss()
        return true
    }

    // MARK: - Implementation

    private func fireRequest(caretByte: Int, prefix: String, suffix: String) {
        let promptText = """
        You are an autocomplete engine. Given the code before and after the caret, suggest a SHORT continuation (one expression, one statement, or one line). Return ONLY the text to insert at the caret — no surrounding code, no explanations, no markdown fences.

        --- code before caret ---
        \(prefix)
        --- code after caret ---
        \(suffix)
        --- continuation ---
        """
        MLXService.shared.complete(prompt: promptText, maxTokens: 64) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                let trimmed = GhostText.firstLine(of: text)
                guard !trimmed.isEmpty else { return }
                self.present(caretByte: caretByte, suggestion: trimmed)
            case .failure:
                break
            }
        }
    }

    private func present(caretByte: Int, suggestion: String) {
        guard let pane else { return }
        // If the caret moved while we waited, drop the suggestion.
        let curByte = pane.currentCaretByte()
        if curByte != caretByte { return }
        currentSuggestion = suggestion
        anchorByte = caretByte
        let line = SciLineFromByte(pane.view, caretByte)
        // Render via EOL annotation. (Visual is "ghost" — single style 0
        // for now; later we can dedicate a style index in Allocations.h.)
        SciSetEOLAnnotationVisibility(pane.view, /* SC_ANNOTATION_STANDARD */ 1)
        SciSetEOLAnnotationText(pane.view, line, "  ⌶ " + suggestion)
    }

    private static func firstLine(of s: String) -> String {
        if let nl = s.firstIndex(of: "\n") {
            return String(s[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
