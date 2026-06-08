// SPDX-License-Identifier: MIT
// Sourcepad — Phase 24 Continuity Camera insertion.
//
// On macOS 13+, NSMenu auto-surfaces Continuity Camera entries when a
// view declares an "Insert from iPhone" capability via the standard
// NSImage(usingPasteboard:)/services menu. We expose a plain "Insert
// Image from File…" entry as the universal fallback; the Continuity
// Camera entry is surfaced by AppKit when the iPhone is on the same
// iCloud account + on the same network.

import AppKit

public enum ContinuityCamera {

    /// Open the system image picker and insert the picked image's path
    /// as a markdown image link at the caret. The user can choose
    /// "Import from iPhone" via the standard file picker on macOS 13+.
    public static func insertImageReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let pane = doc.primaryEditorViewController()?.editorPane else { return }
        let sel = SciGetSelectionBytes(pane.view)
        let pos = sel.location == NSNotFound ? 0 : sel.location
        SciInsertTextAt(pane.view, pos, "![](\(url.path))")
    }
}
