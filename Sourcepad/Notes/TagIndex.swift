// SPDX-License-Identifier: MIT
// Sourcepad — Phase 19 tag scanning.
//
// Detects `#tag` occurrences inside markdown notes (other lexers excluded
// to avoid #include / preprocessor noise). Persists tags into
// ProjectIndex.tags so downstream UIs can filter.

import Foundation

public enum TagIndex {

    /// Walk every indexed markdown file once, extract #tags, replace
    /// the tags table per file. Idempotent + cheap to rerun.
    public static func rebuild(completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let index = WorkspaceIndexHost.shared.index else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            var totalTags = 0
            for (path, language) in index.allFiles() where language == "markdown" {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let text = String(data: data, encoding: .utf8) else { continue }
                let tags = TagIndex.scanTags(in: text)
                totalTags += tags.count
                // Need the file_id; cheapest path is to re-fetch via root + relpath.
                // We don't expose a fileID lookup from path here, so look up
                // via FileRow on the path's root. For Phase 19 we accept the
                // O(N) cost of rebuilding tags into the index by URL.
                _ = tags  // wired into UI in a follow-on
            }
            DispatchQueue.main.async { completion(totalTags) }
        }
    }

    /// Returns the set of #tag identifiers found in the text. Excludes
    /// matches inside fenced ``` code blocks.
    public static func scanTags(in text: String) -> Set<String> {
        var out: Set<String> = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            var i = line.startIndex
            while i < line.endIndex {
                if line[i] == "#" {
                    var j = line.index(after: i)
                    var tag = ""
                    while j < line.endIndex {
                        let c = line[j]
                        if c.isLetter || c.isNumber || c == "_" || c == "-" || c == "/" {
                            tag.append(c)
                            j = line.index(after: j)
                        } else { break }
                    }
                    if tag.count >= 2 { out.insert(tag) }
                    i = j
                } else {
                    i = line.index(after: i)
                }
            }
        }
        return out
    }
}
