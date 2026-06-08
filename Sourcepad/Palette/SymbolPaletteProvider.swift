// SPDX-License-Identifier: MIT
// Sourcepad — ⌘T "Go to Symbol" provider.
//
// Reads ProjectIndex.symbols. Phase 2 populates `files` but not `symbols`;
// the table is empty until Tree-sitter (Phase 5) and LSP (Phases 6-8) start
// emitting symbols. Wiring the provider now means ⌘T works the instant
// either of those phases lands — no menu / dispatcher changes needed later.

import AppKit

public final class SymbolPaletteProvider: PaletteProvider {

    public var displayName: String { "Go to Symbol" }
    public var placeholder: String { "Type to search symbols…" }

    public init() {}

    public func items(for query: String) -> [PaletteItem] {
        guard let index = WorkspaceIndexHost.shared.index else { return [] }
        let all = index.allSymbols()

        // Empty state: tell the user why the list is empty rather than
        // showing a confusing zero results.
        if all.isEmpty {
            let helper = PaletteItem(
                title: "No symbols indexed yet",
                subtitle: "Tree-sitter (Phase 5) + LSP (Phase 6) populate this list",
                symbol: "info.circle",
                payload: NSNull(),
                matchedIndices: [],
                score: 0)
            return [helper]
        }

        if query.isEmpty {
            return all.prefix(200).map { sym in
                PaletteItem(
                    title: sym.name,
                    subtitle: subtitleFor(sym),
                    symbol: symbolGlyph(for: sym.kind),
                    payload: SymbolPayload(absolutePath: sym.absolutePath, line: sym.line),
                    matchedIndices: [],
                    score: 0)
            }
        }
        var ranked: [PaletteItem] = []
        for sym in all {
            guard let match = PaletteFuzzy.match(query: query, candidate: sym.name) else { continue }
            ranked.append(PaletteItem(
                title: sym.name,
                subtitle: subtitleFor(sym),
                symbol: symbolGlyph(for: sym.kind),
                payload: SymbolPayload(absolutePath: sym.absolutePath, line: sym.line),
                matchedIndices: match.indices,
                score: match.score))
        }
        ranked.sort { $0.score > $1.score }
        return ranked
    }

    public func activate(_ item: PaletteItem) {
        guard let payload = item.payload as? SymbolPayload else { return }
        let url = URL(fileURLWithPath: payload.absolutePath)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, _ in
            guard let editor = (doc as? TextDocument)?.primaryEditorViewController() else { return }
            // Symbol jump only meaningful in Scintilla path; placeholder
            // view modes have no caret to move.
            editor.editorPane?.goToLine(max(1, payload.line))
        }
    }

    private func subtitleFor(_ s: (name: String, kind: String?, absolutePath: String, line: Int, col: Int)) -> String {
        let url = URL(fileURLWithPath: s.absolutePath)
        let where_ = "\(url.lastPathComponent):\(s.line)"
        if let k = s.kind, !k.isEmpty { return "\(k)  \(where_)" }
        return where_
    }

    private func symbolGlyph(for kind: String?) -> String {
        switch kind {
        case "function", "method":  return "function"
        case "class":               return "square.stack.3d.up"
        case "struct", "enum":      return "square.grid.2x2"
        case "variable", "field":   return "v.circle"
        case "constant":            return "c.circle"
        case "interface", "trait":  return "i.circle"
        default:                    return "ellipsis"
        }
    }

    private struct SymbolPayload {
        let absolutePath: String
        let line: Int
    }
}
