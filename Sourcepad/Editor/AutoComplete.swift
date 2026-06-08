// SPDX-License-Identifier: MIT
// Sourcepad — buffer-word + lexer-keyword autocomplete.
// Triggered from SCN_UPDATEUI; harvests words from the open buffer plus the
// active lexer's keyword set (Phase 7's keyword sets registered by Lexilla).

import AppKit

public final class AutoComplete {

    /// Minimum prefix length before we show the popup.
    public static let minimumPrefix = 2

    /// Re-derive autocomplete suggestions for the current caret position.
    /// Call from SCN_UPDATEUI on the editor pane.
    public static func update(in sciView: NSView, lexer: String?) {
        let sel = SciGetSelectionBytes(sciView)
        guard sel.length == 0 else {
            SciAutoCCancel(sciView)
            return
        }
        // Pull the prefix (word characters immediately before the caret).
        let caret = Int(sel.location)
        let text = SciGetText(sciView)
        let utf8 = Array(text.utf8)
        var start = caret
        while start > 0 {
            let b = utf8[start - 1]
            if isWordByte(b) { start -= 1 } else { break }
        }
        let prefixLen = caret - start
        guard prefixLen >= minimumPrefix else {
            if SciAutoCActive(sciView) { SciAutoCCancel(sciView) }
            return
        }
        let prefix = String(decoding: utf8[start..<caret], as: UTF8.self)
        let candidates = harvestWords(text, lexer: lexer, prefix: prefix)
        guard !candidates.isEmpty else {
            if SciAutoCActive(sciView) { SciAutoCCancel(sciView) }
            return
        }
        SciAutoCSetIgnoreCase(sciView, true)
        SciAutoCSetSeparator(sciView, 32)  // space
        SciAutoCShow(sciView, prefixLen, candidates.joined(separator: " "))
    }

    private static func isWordByte(_ b: UInt8) -> Bool {
        return (b >= 0x30 && b <= 0x39) ||                  // 0-9
               (b >= 0x41 && b <= 0x5A) ||                  // A-Z
               (b >= 0x61 && b <= 0x7A) ||                  // a-z
                b == 0x5F                                   // _
    }

    private static func harvestWords(_ text: String, lexer: String?, prefix: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        // 1. Buffer words.
        var current = ""
        for ch in text.unicodeScalars {
            let v = ch.value
            let isWord = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A)
                || (v >= 0x61 && v <= 0x7A) || v == 0x5F
            if isWord {
                current.unicodeScalars.append(ch)
            } else {
                if current.count >= minimumPrefix,
                   current.lowercased().hasPrefix(prefix.lowercased()),
                   current != prefix,
                   seen.insert(current).inserted {
                    out.append(current)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= minimumPrefix,
           current.lowercased().hasPrefix(prefix.lowercased()),
           current != prefix,
           seen.insert(current).inserted {
            out.append(current)
        }

        // 2. Lexer keywords (already registered with Scintilla but we don't
        // have a direct accessor — re-derive from the auto-generated table).
        if let lexer, let sets = SPKeywordSetsForLexer(lexer) {
            for set in sets {
                for word in (set as NSString).components(separatedBy: " ") {
                    if word.count >= minimumPrefix,
                       word.lowercased().hasPrefix(prefix.lowercased()),
                       word != prefix,
                       seen.insert(word).inserted {
                        out.append(word)
                    }
                }
            }
        }

        out.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(out.prefix(200))
    }
}
