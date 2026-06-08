// SPDX-License-Identifier: MIT
// Sourcepad — apply LSP WorkspaceEdit results (from textDocument/rename,
// code actions, etc.).
//
// LSP WorkspaceEdit:
//   {
//     changes: { uri: [TextEdit] },  -- legacy form
//     documentChanges: [TextDocumentEdit | CreateFile | RenameFile | DeleteFile]  -- preferred
//   }
//
// Phase 8 handles the most common case: documentChanges OR changes with
// TextEdit arrays. CreateFile / RenameFile / DeleteFile cases land in a
// later polish pass.

import AppKit

public enum LSPWorkspaceEditApplier {

    /// Apply the given workspace edit by opening each affected document
    /// (if not already open), then editing it in byte-position order from
    /// the END of the document toward the START so earlier offsets stay
    /// valid as we mutate.
    public static func apply(_ raw: Any?) {
        guard let dict = raw as? [String: Any] else { return }

        // Collect (uri, edits) pairs.
        var perURI: [String: [[String: Any]]] = [:]

        if let docChanges = dict["documentChanges"] as? [[String: Any]] {
            for change in docChanges {
                guard let td = change["textDocument"] as? [String: Any],
                      let uri = td["uri"] as? String,
                      let edits = change["edits"] as? [[String: Any]] else { continue }
                perURI[uri, default: []].append(contentsOf: edits)
            }
        }
        if let legacy = dict["changes"] as? [String: [[String: Any]]] {
            for (uri, edits) in legacy {
                perURI[uri, default: []].append(contentsOf: edits)
            }
        }

        for (uri, rawEdits) in perURI {
            guard let path = LSP.path(forURI: uri) else { continue }
            let url = URL(fileURLWithPath: path)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, _ in
                guard let editor = (doc as? TextDocument)?.primaryEditorViewController(),
                      let pane = editor.editorPane else { return }
                applyEdits(rawEdits, to: pane)
            }
        }
    }

    /// Apply the given TextEdit array to the pane. Sorts descending by
    /// (start.line, start.character) so each edit's byte positions stay
    /// valid through the mutation.
    private static func applyEdits(_ rawEdits: [[String: Any]],
                                   to pane: EditorPaneViewController) {
        struct Edit {
            let startLine: Int
            let startCol: Int
            let endLine: Int
            let endCol: Int
            let newText: String
        }
        var parsed: [Edit] = []
        for e in rawEdits {
            guard let r = LSP.Range_(e["range"]),
                  let newText = e["newText"] as? String else { continue }
            parsed.append(Edit(startLine: r.start.line,
                               startCol: r.start.character,
                               endLine: r.end.line,
                               endCol: r.end.character,
                               newText: newText))
        }
        // Sort descending so we mutate later positions first.
        parsed.sort { a, b in
            if a.startLine != b.startLine { return a.startLine > b.startLine }
            return a.startCol > b.startCol
        }
        let source = pane.currentText
        SciBeginUndoAction(pane.view)
        for edit in parsed {
            let startByte = LSPDiagnostics.byteOffsetStatic(
                forLineColumnUTF16: LSP.Position(line: edit.startLine, character: edit.startCol),
                in: source)
            let endByte = LSPDiagnostics.byteOffsetStatic(
                forLineColumnUTF16: LSP.Position(line: edit.endLine, character: edit.endCol),
                in: source)
            _ = SciReplaceBytesRange(pane.view, startByte, endByte, edit.newText)
        }
        SciEndUndoAction(pane.view)
    }
}
