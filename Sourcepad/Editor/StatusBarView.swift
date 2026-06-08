// SPDX-License-Identifier: MIT
// Sourcepad — bottom status bar. Live cursor pos + selection length +
// encoding + line endings + lexer + length. Observes Scintilla's
// SCN_UPDATEUI via .sourcepadEditorUIDidUpdate.

import AppKit

public final class StatusBarView: NSView {

    public weak var editorPane: EditorPaneViewController?
    public weak var document: TextDocument?

    private let cursorLabel  = NSTextField(labelWithString: "Ln 1, Col 1")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let encodingButton = NSButton()
    private let eolButton      = NSButton()
    private let lexerLabel   = NSTextField(labelWithString: "")
    private let lengthLabel  = NSTextField(labelWithString: "")

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 22))
        buildUI()
        NotificationCenter.default.addObserver(self,
            selector: #selector(uiUpdated(_:)),
            name: .sourcepadEditorUIDidUpdate, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let topBorder = NSView()
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        let cells: [NSView] = [cursorLabel, selectionLabel, encodingButton, eolButton, lexerLabel, lengthLabel]

        for label in [cursorLabel, selectionLabel, lexerLabel, lengthLabel] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        for btn in [encodingButton, eolButton] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.contentTintColor = .secondaryLabelColor
            btn.imagePosition = .noImage
            btn.target = self
        }
        encodingButton.title = "—"
        encodingButton.action = #selector(showEncodingMenu(_:))
        encodingButton.toolTip = "Encoding — click to change"
        eolButton.title = "—"
        eolButton.action = #selector(showEOLMenu(_:))
        eolButton.toolTip = "Line endings — click to convert"

        let leftStack = NSStackView(views: [cursorLabel, selectionLabel])
        leftStack.orientation = .horizontal
        leftStack.spacing = 12
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [encodingButton, eolButton, lexerLabel, lengthLabel])
        rightStack.orientation = .horizontal
        rightStack.spacing = 12
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
        _ = cells  // silence "unused" warning if any
    }

    // MARK: - Update

    public func refresh() {
        guard let pane = editorPane else { return }
        let line = pane.currentCursorLine + 1
        let col  = pane.currentCursorColumn + 1
        cursorLabel.stringValue = "Ln \(line), Col \(col)"

        let selLen = pane.currentSelectionByteCount
        selectionLabel.stringValue = selLen > 0 ? "(\(selLen) bytes selected)" : ""
        selectionLabel.isHidden = selLen == 0

        encodingButton.title = document?.encodingDisplayName ?? "—"
        eolButton.title = document?.lineEndings.rawValue ?? "—"
        lexerLabel.stringValue = displayName(forLexer: pane.activeLexer)
        let lines = pane.currentLineCount
        let bytes = pane.currentBufferByteCount
        lengthLabel.stringValue = "\(lines) lines · \(formatBytes(bytes))"
    }

    @objc private func uiUpdated(_ note: Notification) {
        if let pane = note.object as? EditorPaneViewController, pane === editorPane {
            refresh()
        }
    }

    // MARK: - Menu actions

    @objc private func showEncodingMenu(_ sender: Any?) {
        guard let doc = document else { return }
        let menu = NSMenu()
        for (label, enc) in [
            ("UTF-8",    String.Encoding.utf8),
            ("UTF-16 LE", String.Encoding.utf16LittleEndian),
            ("UTF-16 BE", String.Encoding.utf16BigEndian),
            ("Latin-1",  String.Encoding.isoLatin1),
            ("ASCII",    String.Encoding.ascii),
        ] {
            let item = NSMenuItem(title: label, action: #selector(applyEncoding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = enc.rawValue
            item.state = (doc.encoding == enc) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: encodingButton.bounds.height), in: encodingButton)
    }

    @objc private func showEOLMenu(_ sender: Any?) {
        guard let doc = document else { return }
        let menu = NSMenu()
        for label in ["LF", "CRLF", "CR"] {
            let item = NSMenuItem(title: label, action: #selector(applyEOL(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = label
            item.state = (doc.lineEndings.rawValue == label) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: eolButton.bounds.height), in: eolButton)
    }

    @objc private func applyEncoding(_ sender: NSMenuItem) {
        guard let pane = editorPane,
              let doc  = document,
              let raw  = sender.representedObject as? UInt
        else { return }
        let new = String.Encoding(rawValue: raw)
        // Re-encode the current buffer into the new encoding by writing the
        // contents as data with the new encoding and reloading. For UTF-8
        // → UTF-16 we just change the encoding field; the save will write
        // the right bytes. For a destructive re-read (e.g. reinterpreting
        // existing bytes), the user must explicitly re-open.
        doc.encoding = new
        doc.updateChangeCount(.changeDone)  // mark dirty so the user knows to save
        refresh()
        _ = pane  // unused
    }

    @objc private func applyEOL(_ sender: NSMenuItem) {
        guard let pane = editorPane,
              let doc  = document,
              let target = sender.representedObject as? String
        else { return }
        let text = pane.currentText
        // Normalize all line endings to LF first, then convert to target.
        var lf = text.replacingOccurrences(of: "\r\n", with: "\n")
                     .replacingOccurrences(of: "\r",   with: "\n")
        switch target {
        case "CRLF": lf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        case "CR":   lf = lf.replacingOccurrences(of: "\n", with: "\r")
        default: break  // LF — already in that form
        }
        pane.replaceWholeBuffer(with: lf)
        doc.lineEndings = TextDocument.LineEndings(rawValue: target) ?? .lf
        doc.updateChangeCount(.changeDone)
        refresh()
    }

    // MARK: - Formatting helpers

    private func formatBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.2f MB", Double(n) / (1024 * 1024))
    }

    private func displayName(forLexer lexer: String?) -> String {
        guard let l = lexer else { return "Plain Text" }
        // Friendly names for common ones; otherwise return as-is.
        switch l {
        case "cpp":       return "C/C++/JS/TS"
        case "hypertext": return "HTML"
        case "phpscript": return "PHP"
        case "bash":      return "Shell"
        case "props":     return "Properties"
        default:          return l.capitalized
        }
    }
}
