// SPDX-License-Identifier: MIT
// Sourcepad — workspace-wide TODO / FIXME / HACK / XXX scanner.
//
// Reads files via ProjectIndex.files; for each file scans line-by-line
// for the canonical markers; writes the resulting tags into
// ProjectIndex.tags. The Tasks sidebar tab reads from there.
//
// We don't try to be clever about which comments are "real" — fenced code
// blocks, string literals, etc. are scanned just like real comments. The
// trade-off favours simplicity; the user can filter the resulting list.

import Foundation

public struct TodoEntry {
    public let absolutePath: String
    public let line: Int
    public let kind: String       // "TODO" / "FIXME" / "HACK" / "XXX"
    public let text: String
}

public final class TodoAggregator {

    public static let shared = TodoAggregator()

    private let queue = DispatchQueue(label: "sourcepad.todo", qos: .utility)
    private var lastScan: [TodoEntry] = []

    private init() {}

    /// Synchronous accessor for the most recent scan results.
    public var entries: [TodoEntry] { lastScan }

    /// Walk every indexed file once. Cheap because we already restrict
    /// to ProjectIndex.files (excluded dirs are filtered at index time).
    public func rescan(completion: @escaping ([TodoEntry]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let index = WorkspaceIndexHost.shared.index else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let files = index.allFiles()
            var found: [TodoEntry] = []
            for (absPath, _) in files {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: absPath)),
                      let text = String(data: data, encoding: .utf8) else { continue }
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, line) in lines.enumerated() {
                    if let kind = TodoAggregator.detectMarker(in: String(line)) {
                        found.append(TodoEntry(
                            absolutePath: absPath,
                            line: i + 1,
                            kind: kind.marker,
                            text: kind.body))
                    }
                }
            }
            self.lastScan = found
            DispatchQueue.main.async { completion(found) }
        }
    }

    /// Look for a recognised marker; return the canonical name + the
    /// body of the comment after the marker. Case-sensitive (we only
    /// pick up uppercase markers — matches the developer convention).
    private static func detectMarker(in line: String)
        -> (marker: String, body: String)? {
        for marker in ["TODO", "FIXME", "HACK", "XXX"] {
            // Need to be a word-boundary match. We look for
            //   <whitespace or //|#|--|/*><marker><:|space>
            let needle = marker
            if let range = line.range(of: needle) {
                let before = range.lowerBound == line.startIndex
                    ? Character(" ")
                    : line[line.index(before: range.lowerBound)]
                guard !before.isLetter else { continue }
                let afterIdx = range.upperBound
                let after: Character = afterIdx == line.endIndex
                    ? Character(" ")
                    : line[afterIdx]
                guard after == ":" || after == " " || after == "\t" else { continue }
                let body = line[afterIdx...]
                    .drop(while: { $0 == ":" || $0.isWhitespace })
                return (marker, String(body))
            }
        }
        return nil
    }
}
