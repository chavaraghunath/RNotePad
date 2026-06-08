// SPDX-License-Identifier: MIT
// Sourcepad — render LSP publishDiagnostics into editor indicators.
//
// On each publishDiagnostics for our document we:
//   - clear indicators 9–12 from the whole buffer
//   - clear margin 4 markers (12–15)
//   - paint each diagnostic's range with the indicator for its severity
//   - paint a margin marker on the diagnostic's start line
//
// LSP positions are (line, character) where character is UTF-16 code units.
// Scintilla works in bytes — we convert per-position. For LSP-utf16 +
// non-ASCII text this is the load-bearing translation.

import AppKit

public final class LSPDiagnostics {

    public weak var sciView: NSView?
    /// Cached source so we can convert LSP positions (UTF-16) → byte
    /// offsets without paying for SciGetText on every diagnostic.
    public var lastSource: String = ""

    private var lastDiagnosticLines: Set<Int> = []
    public private(set) var currentDiagnostics: [LSP.Diagnostic] = []

    public init() {}

    public func setupIndicators(view: NSView,
                                errorColor: NSColor,
                                warningColor: NSColor,
                                infoColor: NSColor,
                                hintColor: NSColor) {
        self.sciView = view
        SciDefineIndicator(view, Int32(SPIndicatorLSPError),
                           .squiggle, errorColor, 255)
        SciDefineIndicator(view, Int32(SPIndicatorLSPWarning),
                           .squiggle, warningColor, 255)
        SciDefineIndicator(view, Int32(SPIndicatorLSPInfo),
                           .dots, infoColor, 255)
        SciDefineIndicator(view, Int32(SPIndicatorLSPHint),
                           .dots, hintColor, 200)
        SciSetupDiagnosticMargin(view,
                                 errorColor, warningColor, infoColor, hintColor)
    }

    public func clearAll() {
        guard let view = sciView else { return }
        let docLen = SciTextLengthBytes(view)
        SciIndicatorClearRange(view, Int32(SPIndicatorLSPError),   0, docLen)
        SciIndicatorClearRange(view, Int32(SPIndicatorLSPWarning), 0, docLen)
        SciIndicatorClearRange(view, Int32(SPIndicatorLSPInfo),    0, docLen)
        SciIndicatorClearRange(view, Int32(SPIndicatorLSPHint),    0, docLen)
        for line in lastDiagnosticLines {
            SciMarkerRemove(view, line, Int32(SPMarkerDiagError))
            SciMarkerRemove(view, line, Int32(SPMarkerDiagWarning))
            SciMarkerRemove(view, line, Int32(SPMarkerDiagInfo))
            SciMarkerRemove(view, line, Int32(SPMarkerDiagHint))
        }
        lastDiagnosticLines.removeAll()
        currentDiagnostics.removeAll()
    }

    public func apply(_ diagnostics: [LSP.Diagnostic], sourceForConversion: String) {
        guard let view = sciView else { return }
        clearAll()
        self.lastSource = sourceForConversion
        self.currentDiagnostics = diagnostics

        for d in diagnostics {
            let startByte = byteOffset(forLineColumnUTF16: d.range.start, in: sourceForConversion)
            let endByte   = byteOffset(forLineColumnUTF16: d.range.end,   in: sourceForConversion)
            let length = max(1, endByte - startByte)
            let (indicator, marker) = mapping(for: d.severity)
            SciIndicatorFillRange(view, indicator, startByte, length)
            SciMarkerAdd(view, d.range.start.line, marker)
            lastDiagnosticLines.insert(d.range.start.line)
        }
    }

    /// Find the smallest diagnostic whose range covers `bytePos`, if any.
    /// Used by hover / status-bar to surface the message on dwell.
    public func diagnostic(atByte bytePos: Int, source: String) -> LSP.Diagnostic? {
        guard let view = sciView else { return nil }
        _ = view
        for d in currentDiagnostics {
            let s = byteOffset(forLineColumnUTF16: d.range.start, in: source)
            let e = byteOffset(forLineColumnUTF16: d.range.end,   in: source)
            if bytePos >= s && bytePos <= e { return d }
        }
        return nil
    }

    // MARK: - Severity → indicator + marker mapping

    private func mapping(for sev: LSP.DiagnosticSeverity) -> (Int32, Int32) {
        switch sev {
        case .error:       return (Int32(SPIndicatorLSPError),   Int32(SPMarkerDiagError))
        case .warning:     return (Int32(SPIndicatorLSPWarning), Int32(SPMarkerDiagWarning))
        case .information: return (Int32(SPIndicatorLSPInfo),    Int32(SPMarkerDiagInfo))
        case .hint:        return (Int32(SPIndicatorLSPHint),    Int32(SPMarkerDiagHint))
        }
    }

    // MARK: - Position conversion
    //
    // LSP positions are zero-based (line, UTF-16 character).
    // Scintilla works in UTF-8 byte offsets.
    //
    // We walk `source` once per position. For modest files this is fine;
    // future optimisation: cache per-line UTF-16 → byte byte ranges if
    // profiling shows it's hot.

    static func byteOffsetStatic(forLineColumnUTF16 pos: LSP.Position, in source: String) -> Int {
        var byte = 0
        var line = 0
        var col = 0
        for scalar in source.unicodeScalars {
            if line == pos.line && col == pos.character { return byte }
            let utf8Count = String(scalar).utf8.count
            let utf16Count = scalar.utf16.count
            if scalar == "\n" {
                if line == pos.line {
                    // Position past EOL — clamp to line end.
                    return byte
                }
                line += 1
                col = 0
                byte += utf8Count
            } else {
                col += utf16Count
                byte += utf8Count
            }
            // Stop early if we've passed the requested line.
            if line > pos.line { return byte }
        }
        return byte
    }

    private func byteOffset(forLineColumnUTF16 pos: LSP.Position, in source: String) -> Int {
        return LSPDiagnostics.byteOffsetStatic(forLineColumnUTF16: pos, in: source)
    }
}
