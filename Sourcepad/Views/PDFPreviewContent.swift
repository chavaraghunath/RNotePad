// SPDX-License-Identifier: MIT
// Sourcepad — PDF preview content.
//
// Wraps PDFKit.PDFView in an EditorContent. .pdf files are treated as
// binary (TextDocument skips the text decode for them, just like images),
// and EditorContentFactory routes the extension to this type by default —
// no "Open As → PDF" needed.

import AppKit
import PDFKit

public final class PDFPreviewContent: NSViewController, EditorContent {

    private let pdfView = PDFView()
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .underPageBackgroundColor
        v.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: v.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        if let url = fileURL, let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
        v.setAccessibilityLabel("Sourcepad PDF preview")
        self.view = v
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String { "" }
    public func replaceWholeBuffer(with text: String) { _ = text }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        let pages = pdfView.document?.pageCount ?? 0
        return EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                               lineCount: pages, bufferByteCount: 0,
                               selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?
}
