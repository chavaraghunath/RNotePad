// SPDX-License-Identifier: MIT
// Sourcepad — protocol the editor pane uses to talk to whatever's actually
// displaying the file.
//
// Phase 4 carves out this abstraction so later phases can swap in a CSV
// grid, JSON tree, hex view, SQLite browser, etc. — without touching the
// surrounding sidebar / preview / status-bar / find-bar chrome.
//
// Today, EditorPaneViewController is the only conformer (Scintilla path).
// EditorContentFactory always returns it. Future phases register new
// content types by adding a case to the factory and implementing this
// protocol on a new NSViewController.

import AppKit

/// Lightweight payload for status-bar / palette UIs that need cursor info
/// without coupling to the underlying view's coordinate system.
public struct EditorCaretInfo {
    public let line0Based: Int
    public let column0Based: Int
    public let byteOffset: Int
    public let lineCount: Int
    public let bufferByteCount: Int
    public let selectionByteCount: Int

    public init(line0Based: Int,
                column0Based: Int,
                byteOffset: Int,
                lineCount: Int,
                bufferByteCount: Int,
                selectionByteCount: Int) {
        self.line0Based = line0Based
        self.column0Based = column0Based
        self.byteOffset = byteOffset
        self.lineCount = lineCount
        self.bufferByteCount = bufferByteCount
        self.selectionByteCount = selectionByteCount
    }
}

/// Anything that can act as the document-displaying region in an editor pane.
///
/// Conformers are NSViewControllers — they own their NSView, manage their
/// own first-responder behavior, and persist their own state. They do NOT
/// handle preview pane / sidebar / find bar / status bar — that's the
/// container's job.
///
/// The protocol is intentionally narrow. View-mode-specific commands (CSV
/// column reorder, JSON tree expand-all, hex byte-edit) belong on the
/// concrete type and are dispatched via the responder chain like any other
/// menu action.
public protocol EditorContent: AnyObject {

    /// The NSView the container will install as the document region.
    /// Typically `self.view` for an NSViewController conformer.
    var contentView: NSView { get }

    /// Current text contents — full UTF-8 source-of-truth. For non-text
    /// view modes (hex, grid, tree) this is the serialised form the
    /// document would save to disk.
    var currentText: String { get }

    /// Replace the entire buffer. Used by external reload, "revert to
    /// saved", and trim-trailing-whitespace-on-save passes.
    func replaceWholeBuffer(with text: String)

    /// Lexer name (Lexilla identifier) currently applied, or nil for plain.
    var activeLexer: String? { get }

    /// Switch lexer. Pass nil for plain text.
    func setLexer(_ name: String?)

    /// Caret + selection info for status bar consumers.
    var caretInfo: EditorCaretInfo { get }

    /// Whether this content type supports a side preview (markdown, html,
    /// css, image, etc.). Text-mode editors usually return true and let
    /// PreviewRenderer decide based on filename; non-text editors typically
    /// return false because they ARE the preview.
    var supportsPreview: Bool { get }

    /// Hook called once when the document's bytes have been loaded into
    /// the editor. Lexer attach + initial styling typically happen here.
    func documentContentsDidLoad()

    /// Mark current buffer as the clean save point. Called after a
    /// successful save so the modified flag clears.
    func markSavePoint()

    /// Caret byte position used by session restore.
    func currentCaretByte() -> Int

    /// Called whenever the buffer changes. The container wires this so a
    /// preview re-render / status-bar refresh can fire.
    var onTextChanged: (() -> Void)? { get set }
}
