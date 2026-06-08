// SPDX-License-Identifier: MIT
// Sourcepad — auto-pair brackets and quotes via a window-level event monitor.
// Bracket / quote inserts emit the matching close char and rewind the caret
// by one. Pressing the closing char when it's already next character just
// steps over it instead of duplicating.

import AppKit

public final class AutoPair {

    public static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}",
        "\"": "\"", "'": "'", "`": "`",
    ]
    public static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`"]

    /// Try to handle a single character of typed input. Returns true if the
    /// event should be consumed (we did the work via the bridge). Returns
    /// false to let Scintilla insert normally.
    public static func handle(typedChar: Character,
                              in sciView: NSView,
                              currentText getText: () -> String) -> Bool {
        let sel = SciGetSelectionBytes(sciView)

        // Step-over: if user types a closer that's already at the caret, just
        // advance one. (Avoids "()|)" duplicates.)
        if closers.contains(typedChar), sel.length == 0 {
            let pos = Int(sel.location)
            let total = SciTextLengthBytes(sciView)
            if pos < total {
                // Read one byte at caret.
                let nextChar = peekChar(at: pos, sciView: sciView)
                if nextChar == typedChar {
                    SciSetSelectionBytes(sciView, pos + 1, pos + 1)
                    return true
                }
            }
        }

        // Open: insert opener + closer, leave caret between.
        guard let closer = pairs[typedChar] else { return false }

        // Skip pairing inside strings/comments — Scintilla can tell us via style.
        if isInStringOrComment(at: Int(sel.location), sciView: sciView) {
            return false
        }

        // If selection is non-empty, wrap selection: opener + text + closer.
        let openerStr = String(typedChar)
        let closerStr = String(closer)
        SciBeginUndoAction(sciView)
        if sel.length > 0 {
            // Wrap. The bridge replaces selection; we recompute selection so
            // it stays selecting the original text.
            let start = Int(sel.location)
            let end   = start + Int(sel.length)
            let inner = sliceUTF8Bytes(getText(), start: start, end: end)
            let newText = openerStr + inner + closerStr
            _ = SciReplaceBytesRange(sciView, start, end, newText)
            let openerBytes = (openerStr as NSString).lengthOfBytes(using: String.Encoding.utf8.rawValue)
            let innerBytes  = (inner as NSString).lengthOfBytes(using: String.Encoding.utf8.rawValue)
            SciSetSelectionBytes(sciView, start + openerBytes, start + openerBytes + innerBytes)
        } else {
            let start = Int(sel.location)
            let combined = openerStr + closerStr
            _ = SciReplaceBytesRange(sciView, start, start, combined)
            let openerBytes = (openerStr as NSString).lengthOfBytes(using: String.Encoding.utf8.rawValue)
            SciSetSelectionBytes(sciView, start + openerBytes, start + openerBytes)
        }
        SciEndUndoAction(sciView)
        return true
    }

    // MARK: - Helpers

    private static func peekChar(at bytePos: Int, sciView: NSView) -> Character? {
        // Quick hack: read the full buffer, find the char at bytePos. For
        // performance this should use a bridge SciGetCharAt — but we read once
        // per keystroke, only the byte at caret, so this loop terminates fast.
        let text = SciGetText(sciView)
        var byteIdx = 0
        for ch in text {
            let bytes = String(ch).utf8.count
            if byteIdx == bytePos { return ch }
            byteIdx += bytes
            if byteIdx > bytePos { return nil }
        }
        return nil
    }

    private static func isInStringOrComment(at bytePos: Int, sciView: NSView) -> Bool {
        // We don't expose SciGetStyleAt yet; default to "no" (always pair).
        // Phase 4's comment work will add the style query if needed.
        _ = bytePos; _ = sciView
        return false
    }

    private static func sliceUTF8Bytes(_ text: String, start: Int, end: Int) -> String {
        let utf8 = Array(text.utf8)
        guard start <= end, end <= utf8.count else { return "" }
        let bytes = Array(utf8[start..<end])
        return String(decoding: bytes, as: UTF8.self)
    }
}
