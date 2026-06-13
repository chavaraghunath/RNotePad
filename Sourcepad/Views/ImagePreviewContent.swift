// SPDX-License-Identifier: MIT
// Sourcepad — image preview content.
//
// Mirror of PDFPreviewContent for raster images (PNG/JPG/GIF/BMP/WEBP/HEIC/
// TIFF/ICO). When the user opens an image file we show the image full-pane
// instead of an empty Scintilla buffer with the picture shoved into the
// side preview. EditorContentFactory routes image extensions here.

import AppKit

public final class ImagePreviewContent: NSViewController, EditorContent {

    private let scroll = NSScrollView()
    private let imageView = NSImageView()
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        scroll.documentView = imageView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: v.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])

        if let url = fileURL, let img = NSImage(contentsOf: url) {
            imageView.image = img
            let size = img.size
            // Size the image view to the image's natural pixel size so the
            // scroll view can give scroll bars when the picture is bigger
            // than the pane.
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: size.width),
                imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: size.height),
            ])
        }
        v.setAccessibilityLabel("Sourcepad image preview")
        self.view = v
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String { "" }
    public func replaceWholeBuffer(with text: String) { _ = text }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        let size = imageView.image?.size ?? .zero
        return EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                               lineCount: Int(size.height), bufferByteCount: 0,
                               selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?
}
