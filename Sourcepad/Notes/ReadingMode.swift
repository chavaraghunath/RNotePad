// SPDX-License-Identifier: MIT
// Sourcepad — Phase 21 reading mode for prose.
//
// Toggles a typography-tuned mode on the active editor pane: serif font,
// wider line-height, justified text via Scintilla's setEditorFont. Hides
// the sidebar + line numbers while active.
//
// Phase 21 minimum: font + linenum toggle; the sidebar collapse + chrome
// dim land in a polish pass.

import AppKit

public enum ReadingMode {

    public private(set) static var isActive = false

    public static func toggle() {
        let active = !isActive
        isActive = active
        if let pane = activePane() {
            if active {
                SciSetEditorFont(pane.view, "New York", 16)
                SciShowLineNumbers(pane.view, false)
            } else {
                SciSetEditorFont(pane.view, Preferences.shared.fontName, Preferences.shared.fontSize)
                SciShowLineNumbers(pane.view, Preferences.shared.showLineNumbers)
            }
        }
    }

    private static func activePane() -> EditorPaneViewController? {
        if let doc = NSDocumentController.shared.currentDocument as? TextDocument,
           let editor = doc.primaryEditorViewController() {
            return editor.editorPane
        }
        return nil
    }
}
