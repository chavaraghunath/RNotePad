// SPDX-License-Identifier: MIT
// Sourcepad — ⌘P "Quick Open File" provider.
//
// Reads ProjectIndex.files for the active workspace, applies fuzzy match
// against the file basename, ranks by score. Items show basename as the
// primary label and the dirname as subtitle.

import AppKit

public final class FilePaletteProvider: PaletteProvider {

    public var displayName: String { "Open File" }
    public var placeholder: String { "Type to search files in workspace…" }

    public init() {}

    public func items(for query: String) -> [PaletteItem] {
        guard let index = WorkspaceIndexHost.shared.index else { return [] }
        let all = index.allFiles()
        if query.isEmpty {
            // Empty query — return up to maxResults arbitrary files (ordered
            // by basename). Useful so the user sees a listing immediately.
            let sorted = all.sorted {
                let a = ($0.absolutePath as NSString).lastPathComponent
                let b = ($1.absolutePath as NSString).lastPathComponent
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            return sorted.prefix(200).map { item in
                let url = URL(fileURLWithPath: item.absolutePath)
                return PaletteItem(
                    title: url.lastPathComponent,
                    subtitle: url.deletingLastPathComponent().path,
                    symbol: symbol(for: item.language),
                    payload: url,
                    matchedIndices: [],
                    score: 0)
            }
        }

        var ranked: [PaletteItem] = []
        ranked.reserveCapacity(all.count)
        for (absPath, language) in all {
            let url = URL(fileURLWithPath: absPath)
            let basename = url.lastPathComponent
            guard let match = PaletteFuzzy.match(query: query, candidate: basename) else { continue }
            ranked.append(PaletteItem(
                title: basename,
                subtitle: url.deletingLastPathComponent().path,
                symbol: symbol(for: language),
                payload: url,
                matchedIndices: match.indices,
                score: match.score))
        }
        ranked.sort { $0.score > $1.score }
        return ranked
    }

    public func activate(_ item: PaletteItem) {
        guard let url = item.payload as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSLog("[Sourcepad] FilePaletteProvider open failed: \(url.path) — \(error)")
            }
        }
    }

    /// Pick an SF Symbol for the language that the row represents. Falls
    /// back to a generic doc icon.
    private func symbol(for language: String?) -> String {
        switch language {
        case "python":           return "chevron.left.forwardslash.chevron.right"
        case "markdown":         return "text.alignleft"
        case "hypertext", "xml": return "doc.text.below.ecg"
        case "json":             return "curlybraces"
        case "yaml":             return "list.bullet.rectangle"
        case "css", "scss":      return "paintbrush"
        default:                 return "doc"
        }
    }
}
