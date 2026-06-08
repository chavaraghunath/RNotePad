// SPDX-License-Identifier: MIT
// Sourcepad — Phase 19 wikilinks.
//
// Recognise [[note]], [[note#section]], [[note|alias]].
// Resolution: search ProjectIndex.allFiles() for a file whose basename
// (sans extension) matches the link target; first hit wins. Phase 20+
// will broaden this with a per-workspace alias map.

import Foundation

public struct WikilinkRef {
    public let target: String
    public let section: String?
    public let alias: String?
    public let range: NSRange  // location in the parent string's UTF-16 index space

    public var displayText: String { alias ?? target }
}

public enum WikilinkParser {

    /// Scan a string for `[[…]]` occurrences. Pretty literal — does NOT
    /// try to skip code fences or quoted strings.
    public static func extract(from text: String) -> [WikilinkRef] {
        var out: [WikilinkRef] = []
        let ns = text as NSString
        let pattern = "\\[\\[([^\\[\\]\\|#]+)(#([^\\[\\]\\|]+))?(\\|([^\\[\\]]+))?\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let target = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let sectionRange = m.range(at: 3)
            let section = sectionRange.location != NSNotFound
                ? ns.substring(with: sectionRange).trimmingCharacters(in: .whitespaces)
                : nil
            let aliasRange = m.range(at: 5)
            let alias = aliasRange.location != NSNotFound
                ? ns.substring(with: aliasRange).trimmingCharacters(in: .whitespaces)
                : nil
            out.append(WikilinkRef(target: target, section: section, alias: alias, range: m.range))
        }
        return out
    }

    /// Find a workspace file whose basename (case-insensitive, dropping
    /// the extension) matches `target`. Returns nil if unresolved.
    public static func resolve(_ target: String) -> URL? {
        guard let index = WorkspaceIndexHost.shared.index else { return nil }
        let needle = target.lowercased()
        for (path, _) in index.allFiles() {
            let url = URL(fileURLWithPath: path)
            let baseLower = url.deletingPathExtension().lastPathComponent.lowercased()
            if baseLower == needle { return url }
        }
        return nil
    }
}
