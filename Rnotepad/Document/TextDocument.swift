// SPDX-License-Identifier: MIT
// Rnotepad — NSDocument backing a single text file.

import AppKit

@objc(RNPTextDocument)
public final class TextDocument: NSDocument {

    /// In-memory contents. Set from disk via read(from:ofType:) and from the
    /// editor view on save via the EditorViewController pull.
    public var contents: String = ""

    /// The original encoding the file was loaded with. Used for save back.
    public var encoding: String.Encoding = .utf8

    /// True if the file had a UTF-8 BOM.
    public var hasUTF8BOM: Bool = false

    public override init() {
        super.init()
        self.hasUndoManager = false  // Scintilla owns undo.
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
        // Push to the editor if it's already loaded.
        if let editor = primaryEditorViewController() {
            editor.documentContentsDidLoad()
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
}
