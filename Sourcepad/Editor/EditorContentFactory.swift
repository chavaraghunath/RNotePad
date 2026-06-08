// SPDX-License-Identifier: MIT
// Sourcepad — resolves (document, override?) → EditorContent.
//
// The factory is the single decision point for "what kind of view does this
// file get?" Phase 4 wires the factory + an override hook the View > Open As
// menu sets. Phases 14-17 add real cases (CSV grid, JSON tree, SQLite
// browser, hex view, font preview, PDF preview).

import AppKit

public enum EditorContentMode: String {
    case text       // ScintillaEditorContent (the default for everything today)
    case grid       // CSV grid — Phase 14
    case tree       // JSON / YAML / TOML tree — Phase 14
    case sqlite     // SQLite browser — Phase 15
    case hex        // hex view — Phase 16
    case font       // font preview — Phase 16
    case pdf        // PDF preview — Phase 17
}

public enum EditorContentFactory {

    /// One-shot "open this file as <mode>" override. The next document
    /// open consumes this and resets it back to nil so subsequent files
    /// pick up their default mode again.
    public static var nextOpenOverride: EditorContentMode?

    /// Resolve the content for `document`. The factory inspects the
    /// override first; otherwise picks the best-fit default.
    public static func makeContent(for document: TextDocument) -> EditorContent {
        if let override = nextOpenOverride {
            nextOpenOverride = nil
            if let content = makeForMode(override, document: document) {
                return content
            }
        }
        // Default: the Scintilla path. EditorPaneViewController already
        // accepts a document at init and pulls bytes via
        // documentContentsDidLoad().
        return EditorPaneViewController(document: document)
    }

    /// Phase 14–17: produce a real content type for a non-text mode if
    /// the implementation has landed; otherwise fall through to the
    /// placeholder (still proves the abstraction).
    private static func makeForMode(_ mode: EditorContentMode,
                                    document: TextDocument) -> EditorContent? {
        let url = document.fileURL
        let initialText = document.contents
        switch mode {
        case .text:
            return nil
        case .grid:
            return CSVGridContent(initialText: initialText)
        case .tree:
            return JSONTreeContent(initialText: initialText)
        case .hex:
            if let u = url { return HexViewContent(fileURL: u) }
            return HexViewContent(initialText: initialText)
        case .sqlite:
            if let u = url { return SQLiteBrowserContent(fileURL: u) }
            return PlaceholderContent(kind: .sqlite, initialText: initialText)
        case .font:
            return PlaceholderContent(kind: .font, initialText: initialText)
        case .pdf:
            return PlaceholderContent(kind: .pdf, initialText: initialText)
        }
    }
}
