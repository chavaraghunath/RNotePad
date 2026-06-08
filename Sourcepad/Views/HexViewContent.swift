// SPDX-License-Identifier: MIT
// Sourcepad — Phase 16 hex view.
//
// Renders the document bytes as a three-column hex dump:
//   offset (8 hex chars) │ <16 hex bytes>  │ <16 printable ASCII chars>
//
// Read-only for v1. Editable hex view + binary diff are deferred to a
// future polish pass (the abstraction is in place — just needs a
// per-cell editor).

import AppKit

public final class HexViewContent: NSViewController, EditorContent {

    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private var data: Data

    public init(initialText: String) {
        self.data = initialText.data(using: .utf8) ?? Data()
        super.init(nibName: nil, bundle: nil)
    }

    /// Convenience: load directly from a binary file URL.
    public init(fileURL: URL) {
        self.data = (try? Data(contentsOf: fileURL)) ?? Data()
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 400))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        v.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: v.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = HexViewContent.render(data: data)
        self.view = v
    }

    static func render(data: Data) -> String {
        var out = ""
        out.reserveCapacity(data.count * 4)
        let bytesPerLine = 16
        var offset = 0
        let total = data.count
        while offset < total {
            let line = data.subdata(in: offset..<min(offset + bytesPerLine, total))
            out.append(String(format: "%08x  ", offset))
            for i in 0..<bytesPerLine {
                if i < line.count {
                    out.append(String(format: "%02x ", line[i]))
                } else {
                    out.append("   ")
                }
                if i == 7 { out.append(" ") }
            }
            out.append(" │")
            for b in line {
                if b >= 0x20 && b < 0x7f {
                    out.append(Character(UnicodeScalar(b)))
                } else {
                    out.append(".")
                }
            }
            out.append("│\n")
            offset += bytesPerLine
        }
        return out
    }

    // MARK: - EditorContent

    public var contentView: NSView { view }
    public var currentText: String { String(data: data, encoding: .utf8) ?? "" }
    public func replaceWholeBuffer(with text: String) {
        data = text.data(using: .utf8) ?? Data()
        textView.string = HexViewContent.render(data: data)
    }
    public var activeLexer: String? { nil }
    public func setLexer(_ name: String?) {}
    public var caretInfo: EditorCaretInfo {
        EditorCaretInfo(line0Based: 0, column0Based: 0, byteOffset: 0,
                        lineCount: max(1, (data.count + 15) / 16),
                        bufferByteCount: data.count,
                        selectionByteCount: 0)
    }
    public var supportsPreview: Bool { false }
    public func documentContentsDidLoad() {}
    public func markSavePoint() {}
    public func currentCaretByte() -> Int { 0 }
    public var onTextChanged: (() -> Void)?
}
