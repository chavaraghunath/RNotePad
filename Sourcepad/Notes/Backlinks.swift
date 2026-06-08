// SPDX-License-Identifier: MIT
// Sourcepad — Phase 20 backlinks.
//
// For each note A that contains `[[B]]`, B has A as a backlink. We scan
// every markdown file in the workspace and emit (from, to) pairs that
// the upcoming Backlinks sidebar panel renders.
//
// Phase 20 minimum: in-memory aggregation. Phase 21+ may persist into
// ProjectIndex.links for incremental updates.

import Foundation

public enum BacklinksIndex {

    /// Returns absolute paths of files that wikilink TO `target`.
    public static func backlinks(toFile targetURL: URL) -> [URL] {
        guard let index = WorkspaceIndexHost.shared.index else { return [] }
        let targetBase = targetURL.deletingPathExtension().lastPathComponent.lowercased()
        var refs: [URL] = []
        for (path, language) in index.allFiles() where language == "markdown" {
            guard path != targetURL.path,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for link in WikilinkParser.extract(from: text) {
                if link.target.lowercased() == targetBase {
                    refs.append(URL(fileURLWithPath: path))
                    break
                }
            }
        }
        return refs
    }
}
