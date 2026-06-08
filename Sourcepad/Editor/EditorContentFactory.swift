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
        // Phase 4: real alternative content types haven't shipped yet,
        // so any non-.text mode resolves to PlaceholderContent. The
        // surrounding chrome (sidebar / preview / status bar) is the
        // thing being proven swappable.
        if let override = nextOpenOverride {
            nextOpenOverride = nil
            if override != .text {
                let kind: PlaceholderContent.Kind
                switch override {
                case .grid:   kind = .grid
                case .tree:   kind = .tree
                case .sqlite: kind = .sqlite
                case .hex:    kind = .hex
                case .font:   kind = .font
                case .pdf:    kind = .pdf
                case .text:   kind = .grid // unreachable
                }
                return PlaceholderContent(kind: kind, initialText: document.contents)
            }
        }
        // Default: the Scintilla path. EditorPaneViewController already
        // accepts a document at init and pulls bytes via
        // documentContentsDidLoad().
        return EditorPaneViewController(document: document)
    }
}
