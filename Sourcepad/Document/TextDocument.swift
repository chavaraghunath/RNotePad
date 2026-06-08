// SPDX-License-Identifier: MIT
// Sourcepad — NSDocument backing a single text file.

import AppKit

@objc(SPTextDocument)
public final class TextDocument: NSDocument {

    /// In-memory contents. Set from disk via read(from:ofType:) and from the
    /// editor view on save via the EditorViewController pull.
    public var contents: String = ""

    /// The original encoding the file was loaded with. Used for save back.
    public var encoding: String.Encoding = .utf8

    /// True if the file had a UTF-8 BOM.
    public var hasUTF8BOM: Bool = false

    /// Lexer name deduced from the file's shebang line (if present).
    /// Used as a fallback when the filename gives no hint.
    public var shebangLexer: String?

    public enum LineEndings: String {
        case lf = "LF", crlf = "CRLF", cr = "CR", mixed = "Mixed"
    }

    /// Line endings detected from the file content on read.
    public var lineEndings: LineEndings = .lf

    public override init() {
        super.init()
        self.hasUndoManager = false  // Scintilla owns undo.
    }

    public override func close() {
        if let url = fileURL { ClosedTabHistory.shared.push(url) }
        super.close()
    }

    public override class var autosavesInPlace: Bool { true }

    // MARK: - Window controller

    public override func makeWindowControllers() {
        let wc = EditorWindowController(document: self)
        self.addWindowController(wc)
    }

    // MARK: - File I/O

    public override func read(from data: Data, ofType typeName: String) throws {
        let (text, enc, bom) = TextDocument.decode(data)
        self.contents = text
        self.encoding = enc
        self.hasUTF8BOM = bom
        self.shebangLexer = TextDocument.detectShebangLexer(from: text)
        self.lineEndings = TextDocument.detectLineEndings(from: text)
        // Push to the editor if it's already loaded.
        if let editor = primaryEditorViewController() {
            editor.documentContentsDidLoad()
        }
    }

    /// Human-readable encoding name for the status bar.
    public var encodingDisplayName: String {
        switch encoding {
        case .utf8:              return hasUTF8BOM ? "UTF-8 BOM" : "UTF-8"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian:    return "UTF-16 BE"
        case .utf32LittleEndian: return "UTF-32 LE"
        case .utf32BigEndian:    return "UTF-32 BE"
        case .isoLatin1:         return "Latin-1"
        case .ascii:             return "ASCII"
        case .windowsCP1252:     return "CP1252"
        default:                 return "—"
        }
    }

    public override func data(ofType typeName: String) throws -> Data {
        // Pull latest from editor (may be ahead of self.contents).
        if let editor = primaryEditorViewController() {
            self.contents = editor.currentText
        }
        var data = self.contents.data(using: encoding, allowLossyConversion: false)
            ?? self.contents.data(using: .utf8) ?? Data()
        if hasUTF8BOM, encoding == .utf8 {
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            data = Data(bom) + data
        }
        return data
    }

    public override func write(to url: URL, ofType typeName: String) throws {
        try super.write(to: url, ofType: typeName)
        // Tell Scintilla "this is now the clean state".
        primaryEditorViewController()?.markSavePoint()
    }

    private func primaryEditorViewController() -> EditorViewController? {
        return windowControllers
            .compactMap { ($0 as? EditorWindowController)?.editorViewController }
            .first
    }

    // MARK: - Encoding detection

    /// Best-effort encoding sniff. Order:
    ///   1. UTF-8 BOM (EF BB BF)
    ///   2. UTF-16 LE BOM (FF FE)
    ///   3. UTF-16 BE BOM (FE FF)
    ///   4. UTF-32 BOM (00 00 FE FF / FF FE 00 00) — rare, supported
    ///   5. Otherwise: try UTF-8, fall back to ISO Latin-1 (never throws).
    static func decode(_ data: Data) -> (String, String.Encoding, Bool) {
        let b = [UInt8](data.prefix(4))

        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF {
            let body = data.dropFirst(3)
            return (String(decoding: body, as: UTF8.self), .utf8, true)
        }
        if b.count >= 4, b[0] == 0x00, b[1] == 0x00, b[2] == 0xFE, b[3] == 0xFF {
            return (String(data: data, encoding: .utf32BigEndian) ?? "", .utf32BigEndian, false)
        }
        if b.count >= 4, b[0] == 0xFF, b[1] == 0xFE, b[2] == 0x00, b[3] == 0x00 {
            return (String(data: data, encoding: .utf32LittleEndian) ?? "", .utf32LittleEndian, false)
        }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF {
            return (String(data: data, encoding: .utf16BigEndian) ?? "", .utf16BigEndian, false)
        }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE {
            return (String(data: data, encoding: .utf16LittleEndian) ?? "", .utf16LittleEndian, false)
        }

        if let s = String(data: data, encoding: .utf8) {
            return (s, .utf8, false)
        }
        // ISO Latin-1 is single-byte; can't fail.
        return (String(data: data, encoding: .isoLatin1) ?? "", .isoLatin1, false)
    }

    /// Inspect the first line for `#!…/interpreter` and map to a Lexilla lexer.
    /// Returns nil if no shebang or no known interpreter.
    static func detectShebangLexer(from text: String) -> String? {
        guard text.hasPrefix("#!") else { return nil }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let lower = firstLine.lowercased()
        // The interpreter token is usually the final path component after the
        // last "/" or after "env ".
        let interp: String
        if let envRange = lower.range(of: "env ") {
            interp = String(lower[envRange.upperBound...])
                .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        } else if let slash = lower.lastIndex(of: "/") {
            interp = String(lower[lower.index(after: slash)...])
                .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        } else {
            return nil
        }
        // Strip trailing version digits ("python3" → "python").
        let base = interp.trimmingCharacters(in: .decimalDigits)
        switch base {
        case "python", "pypy":               return "python"
        case "bash", "sh", "zsh", "ksh", "ash", "dash":
                                              return "bash"
        case "node", "deno", "bun":          return "cpp"        // we use cpp for JS
        case "ruby":                          return "ruby"
        case "perl":                          return "perl"
        case "lua":                           return "lua"
        case "php":                           return "phpscript"
        case "tcl", "wish", "expect":        return "tcl"
        case "fish":                          return "bash"
        case "powershell", "pwsh":           return "powershell"
        default:                              return nil
        }
    }

    /// Quick scan: which line-ending dominates this file?
    static func detectLineEndings(from text: String) -> LineEndings {
        var lf = 0, crlf = 0, cr = 0
        let scalars = text.unicodeScalars
        var i = scalars.startIndex
        let end = scalars.endIndex
        while i < end {
            let c = scalars[i]
            if c == "\r" {
                let next = scalars.index(after: i)
                if next < end, scalars[next] == "\n" {
                    crlf += 1
                    i = scalars.index(after: next)
                } else {
                    cr += 1
                    i = next
                }
            } else if c == "\n" {
                lf += 1
                i = scalars.index(after: i)
            } else {
                i = scalars.index(after: i)
            }
        }
        let nonZero = [lf, crlf, cr].filter { $0 > 0 }.count
        if nonZero == 0 { return .lf }
        if nonZero > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }
}
